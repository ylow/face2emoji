import Face2EmojiCore
import SwiftUI

/// The current photo, large, with its emoji, which are edited here.
///
/// Shows the photo's thumbnail at once and swaps in a preview (longest side ≤ 2560 px) once it has
/// loaded; only the current photo's preview is held.
///
/// Mouse-down on an emoji selects it; anywhere else deselects. Dragging an emoji more than 3 pt moves
/// it, dragging the selected emoji's handle resizes it, and a click on an emoji opens the picker to
/// replace it. A drag changes the batch once, on release, so each is one undo step.
struct EditorView: View {
    @Environment(Batch.self) private var batch
    @State private var preview: Preview?
    /// From mouse-down to mouse-up.
    @State private var press: Press?
    /// The emoji whose picker is open; it shows while that emoji stays selected.
    @State private var pickerEmojiID: EmojiPlacement.ID?

    private struct Preview {
        var photoID: PhotoItem.ID
        var image: CGImage
    }

    private struct Press {
        var photoID: PhotoItem.ID
        var start: CGPoint
        var target: Target
        /// The pointer has gone more than `dragThreshold` from `start`: a drag, not a click.
        var isDrag = false
        /// The emoji as the drag has made it so far. The batch is left alone until mouse-up.
        var draft: EmojiPlacement?
    }

    /// What a press acts on, decided at mouse-down.
    private enum Target {
        /// A drag moves it; a click opens its picker.
        case emoji(EmojiPlacement)
        /// The selected emoji, by its resize handle: a drag resizes it.
        case resizeHandle(EmojiPlacement)
        /// Empty photo or margin.
        case nothing
    }

    private static let margin: CGFloat = 16
    private static let dragThreshold: CGFloat = 3
    private nonisolated static let previewMaxPixelSize = 2560

    var body: some View {
        GeometryReader { proxy in
            if let photo = batch.currentPhoto {
                let image = image(of: photo)
                let bounds = CGRect(origin: .zero, size: proxy.size).insetBy(dx: Self.margin, dy: Self.margin)
                if let geometry = EditorGeometry(imageSize: CGSize(width: image.width, height: image.height), bounds: bounds) {
                    canvas(of: photo, image: image, geometry: geometry)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
        }
        // The selection may stick out of the photo, but not out of the editor.
        .clipped()
        .task(id: batch.currentPhotoID) { await loadPreview() }
    }

    /// The photo in `geometry.photoFrame`, so that what is drawn and what the pointer hits agree, and
    /// the selection on top of it, not clipped to the photo. Takes presses anywhere, margin included.
    private func canvas(of photo: PhotoItem, image: CGImage, geometry: EditorGeometry) -> some View {
        let placements = shownPlacements(of: photo)
        let frame = geometry.photoFrame
        return ZStack {
            PhotoCanvasView(image: image, placements: placements)
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
            if let selected = placements.first(where: { $0.id == batch.selectedEmojiID }) {
                selection(of: selected, in: geometry)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { follow($0, in: geometry) }
                .onEnded { value in
                    follow(value, in: geometry)
                    release()
                }
        )
    }

    private func selection(of placement: EmojiPlacement, in geometry: EditorGeometry) -> some View {
        let square = geometry.square(of: placement)
        return SelectionFrame(side: square.width)
            .popover(isPresented: isPickerShown(for: placement.id)) {
                EmojiPickerView { replace(placement.id, with: $0) }
            }
            .rotationEffect(.radians(placement.rotation))
            .position(x: square.midX, y: square.midY)
    }

    /// The photo's emoji, the one being dragged where the drag has put it.
    private func shownPlacements(of photo: PhotoItem) -> [EmojiPlacement] {
        guard let press, press.photoID == photo.id, let draft = press.draft else { return photo.placements }
        return photo.placements.map { $0.id == draft.id ? draft : $0 }
    }

    // MARK: - Pressing

    /// Starts a press at mouse-down, then follows the pointer.
    private func follow(_ value: DragGesture.Value, in geometry: EditorGeometry) {
        // A new start is a new press, even if SwiftUI cancelled the last one without ending it.
        if press?.start != value.startLocation { press = startPress(at: value.startLocation, in: geometry) }
        guard var press else { return }
        if !press.isDrag, hypot(value.translation.width, value.translation.height) > Self.dragThreshold {
            press.isDrag = true
        }
        if press.isDrag {
            switch press.target {
            case let .emoji(placement): press.draft = geometry.moving(placement, by: value.translation)
            case let .resizeHandle(placement): press.draft = geometry.resizing(placement, handleTo: value.location)
            case .nothing: break
            }
        }
        self.press = press
    }

    /// Mouse-down selects what is under the pointer: the selected emoji's handle first, then the
    /// topmost emoji. Elsewhere it deselects.
    private func startPress(at point: CGPoint, in geometry: EditorGeometry) -> Press? {
        pickerEmojiID = nil
        guard let photo = batch.currentPhoto else { return nil }
        let target: Target
        if let selected = photo.placements.first(where: { $0.id == batch.selectedEmojiID }),
           geometry.isOnResizeHandle(point, of: selected) {
            target = .resizeHandle(selected)
        } else if let hit = geometry.topmostPlacement(at: point, in: photo.placements) {
            batch.selectedEmojiID = hit.id
            target = .emoji(hit)
        } else {
            batch.selectedEmojiID = nil
            target = .nothing
        }
        return Press(photoID: photo.id, start: point, target: target)
    }

    /// Mouse-up: a drag changes the batch; a click on an emoji opens its picker.
    private func release() {
        guard let press else { return }
        self.press = nil
        // Another photo became current during the press: nothing of it is in view any more.
        guard press.photoID == batch.currentPhotoID else { return }
        if let draft = press.draft {
            batch.update(draft, in: press.photoID)
        } else if !press.isDrag, case let .emoji(placement) = press.target {
            pickerEmojiID = placement.id
        }
    }

    // MARK: - Picker

    private func isPickerShown(for emojiID: EmojiPlacement.ID) -> Binding<Bool> {
        Binding(get: { pickerEmojiID == emojiID }, set: { if !$0 { pickerEmojiID = nil } })
    }

    private func replace(_ emojiID: EmojiPlacement.ID, with emoji: String) {
        pickerEmojiID = nil
        guard let photo = batch.currentPhoto, var placement = photo.placements.first(where: { $0.id == emojiID }) else {
            return
        }
        placement.emoji = emoji
        batch.update(placement, in: photo.id)
    }

    // MARK: - Preview

    private func image(of photo: PhotoItem) -> CGImage {
        if let preview, preview.photoID == photo.id { return preview.image }
        return photo.thumbnail
    }

    private func loadPreview() async {
        preview = nil
        guard let photo = batch.currentPhoto else { return }
        let image = await Self.decodePreview(of: photo.source.url)
        // Cancelled: another photo has become current meanwhile.
        guard !Task.isCancelled, let image else { return }
        preview = Preview(photoID: photo.id, image: image)
    }

    /// nil when cancelled before decoding started, or when the file cannot be decoded; the thumbnail
    /// then stays.
    @concurrent private nonisolated static func decodePreview(of url: URL) async -> CGImage? {
        guard !Task.isCancelled else { return nil }
        return try? ImageLoader.loadUpright(url, maxPixelSize: previewMaxPixelSize)
    }
}

/// The selected emoji's outline, `side` points square and unturned, with the resize handle centred
/// on its bottom-right corner.
private struct SelectionFrame: View {
    let side: CGFloat

    var body: some View {
        ZStack {
            Rectangle().stroke(Color.accentColor, lineWidth: 2)
            Rectangle()
                .fill(.white)
                .overlay { Rectangle().strokeBorder(Color.accentColor, lineWidth: 1.5) }
                .frame(width: EditorGeometry.resizeHandleSide, height: EditorGeometry.resizeHandleSide)
                .position(x: side, y: side)
        }
        .frame(width: side, height: side)
    }
}
