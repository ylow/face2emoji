import Face2EmojiCore
import SwiftUI

/// Every photo of the batch as a thumbnail with its emoji, top to bottom. Clicking one makes it current;
/// the current one is outlined and kept in view.
struct FilmstripView: View {
    @Environment(Batch.self) private var batch

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView(.vertical) {
                LazyVStack(spacing: 8) {
                    ForEach(batch.photos) { photo in
                        thumbnail(of: photo)
                            .id(photo.id)
                    }
                }
                .padding(8)
            }
            .onChange(of: batch.currentPhotoID, initial: true) { _, currentID in
                guard let currentID else { return }
                // No anchor: scroll only as far as needed to show it whole.
                withAnimation { scroller.scrollTo(currentID) }
            }
        }
    }

    private func thumbnail(of photo: PhotoItem) -> some View {
        let isCurrent = photo.id == batch.currentPhotoID
        return PhotoCanvasView(image: photo.thumbnail, placements: photo.placements)
            .overlay {
                if photo.isDetecting {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(3)
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isCurrent ? Color.accentColor : .clear, lineWidth: 3)
            }
            .contentShape(Rectangle())
            .onTapGesture { select(photo) }
            .contextMenu {
                Button("Remove Photo") { batch.removePhoto(photo.id) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(photo.source.originalName)
            .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { select(photo) }
    }

    private func select(_ photo: PhotoItem) {
        // Re-selecting the current photo would clear its emoji selection.
        if batch.currentPhotoID != photo.id { batch.currentPhotoID = photo.id }
    }
}
