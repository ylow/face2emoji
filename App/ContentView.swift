import Face2EmojiCore
import SwiftUI
import UniformTypeIdentifiers

/// The window's content: a prompt to drop photos until there are some, then the filmstrip and the
/// editor. Photos can be dropped anywhere on it; the arrow keys move through them.
struct ContentView: View {
    @Environment(Batch.self) private var batch
    @State private var skippedMessage: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay { DropTargetView(onDrop: add(_:failedCount:)) }
            // Arrow keys reach this handler only when no focused view inside, such as a text field,
            // handles them first.
            .focusable()
            .focusEffectDisabled()
            .focused($isFocused)
            .defaultFocus($isFocused, true)
            .onKeyPress(keys: [.leftArrow, .upArrow, .rightArrow, .downArrow], action: navigate)
            .toolbar {
                if let position {
                    ToolbarItem(placement: .status) {
                        Text(position).monospacedDigit()
                    }
                }
            }
            .alert(skippedMessage ?? "", isPresented: isShowingSkippedMessage) {}
            #if DEBUG
            .onAppear(perform: addDebugPhotos)
            #endif
    }

    @ViewBuilder private var content: some View {
        if batch.photos.isEmpty {
            Text("Drop photos here")
                .font(.title2)
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 0) {
                FilmstripView()
                    .frame(width: 110)
                Divider()
                EditorView()
            }
        }
    }

    /// "3 of 12"; nil when there is no current photo.
    private var position: String? {
        guard let id = batch.currentPhotoID, let index = batch.photos.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        return "\(index + 1) of \(batch.photos.count)"
    }

    private var isShowingSkippedMessage: Binding<Bool> {
        Binding(get: { skippedMessage != nil }, set: { if !$0 { skippedMessage = nil } })
    }

    /// Adds the image files among `sources`; files of other types are ignored without a word. Image files
    /// that cannot be decoded and `failedCount` (promised files that never arrived) are reported together.
    private func add(_ sources: [PhotoSource], failedCount: Int) {
        let images = sources.filter { UTType(filenameExtension: $0.url.pathExtension)?.conforms(to: .image) ?? false }
        // Not a view-bound task: cancelling `add` could leave photos without their faces.
        Task {
            let unreadable = await batch.add(images) + failedCount
            if unreadable > 0 { skippedMessage = "\(unreadable) item(s) could not be read as photos." }
        }
    }

    private func navigate(_ press: KeyPress) -> KeyPress.Result {
        // Leave modified arrows to whatever else wants them.
        guard press.modifiers.isDisjoint(with: [.command, .option, .control, .shift]) else { return .ignored }
        switch press.key {
        case .leftArrow, .upArrow: batch.selectPreviousPhoto()
        default: batch.selectNextPhoto()
        }
        return .handled
    }

    #if DEBUG
    /// FACE2EMOJI_DEBUG_LOAD=<path>:<path>… adds those files at launch, as dropping them would.
    private func addDebugPhotos() {
        guard let paths = ProcessInfo.processInfo.environment["FACE2EMOJI_DEBUG_LOAD"] else { return }
        let sources = paths.split(separator: ":").map { path in
            let url = URL(filePath: String(path))
            return PhotoSource(url: url, originalName: url.lastPathComponent)
        }
        add(sources, failedCount: 0)
    }
    #endif
}
