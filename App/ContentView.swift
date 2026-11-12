import Face2EmojiCore
import SwiftUI
import UniformTypeIdentifiers

/// The window's content: a prompt to drop photos until there are some, then the filmstrip and the
/// editor. Photos can be dropped anywhere on it; the arrow keys move through them, and Delete removes
/// the selected emoji, or the current photo when no emoji is selected.
struct ContentView: View {
    @Environment(Batch.self) private var batch
    @State private var skippedMessage: String?
    @FocusState private var isFocused: Bool

    /// The key labelled "delete" (⌫) on a Mac keyboard. It reaches `onKeyPress` as U+007F, not as
    /// `KeyEquivalent.delete` (U+0008).
    private static let backspace = KeyEquivalent("\u{7F}")

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay { DropTargetView(onDrop: add(_:failedCount:)) }
            // Keys reach these handlers only when no focused view inside, such as a text field,
            // handles them first.
            .focusable()
            .focusEffectDisabled()
            .focused($isFocused)
            .defaultFocus($isFocused, true)
            .onKeyPress(keys: [.leftArrow, .upArrow, .rightArrow, .downArrow], action: navigate)
            // Not on key repeat: once the selected emoji is gone, a held key would remove photo after photo.
            .onKeyPress(keys: [Self.backspace, .delete, .deleteForward], phases: .down, action: delete)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Add Emoji") { batch.addEmoji() }
                        .disabled(batch.currentPhoto == nil)
                    Menu {
                        ForEach(EmojiCatalog.all, id: \.self) { emoji in
                            Button(emoji) { batch.defaultEmoji = emoji }
                        }
                    } label: {
                        Text("Default: \(batch.defaultEmoji)")
                    }
                }
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

    private func delete(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.isDisjoint(with: [.command, .option, .control, .shift]) else { return .ignored }
        if batch.selectedEmojiID != nil {
            batch.deleteSelectedEmoji()
        } else if let current = batch.currentPhotoID {
            batch.removePhoto(current)
        } else {
            return .ignored
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
