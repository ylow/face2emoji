import Face2EmojiCore
import SwiftUI

/// The current photo, large, with its emoji. Display only.
///
/// Shows the photo's thumbnail at once and swaps in a preview (longest side ≤ 2560 px) once it has
/// loaded; only the current photo's preview is held.
struct EditorView: View {
    @Environment(Batch.self) private var batch
    @State private var preview: Preview?

    private struct Preview {
        var photoID: PhotoItem.ID
        var image: CGImage
    }

    private nonisolated static let previewMaxPixelSize = 2560

    var body: some View {
        ZStack {
            if let photo = batch.currentPhoto {
                PhotoCanvasView(image: image(of: photo), placements: photo.placements)
                    .padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: batch.currentPhotoID) { await loadPreview() }
    }

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
