import Face2EmojiCore
import SwiftUI

/// Draws `image` aspect-fit with `placements` on top. Non-interactive. Emoji views are positioned with
/// `placement.rect(in: fittedSize)` and `rotationEffect(.radians(placement.rotation))`, using `EmojiGlyph.image`.
///
/// Emoji are clipped to the photo, as they are at export.
struct PhotoCanvasView: View {
    let image: CGImage
    let placements: [EmojiPlacement]

    init(image: CGImage, placements: [EmojiPlacement]) {
        self.image = image
        self.placements = placements
    }

    var body: some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    ForEach(placements) { placement in
                        let rect = placement.rect(in: geometry.size)
                        Image(decorative: EmojiGlyph.image(for: placement.emoji), scale: 1)
                            .resizable()
                            .frame(width: rect.width, height: rect.height)
                            .rotationEffect(.radians(placement.rotation))
                            .position(x: rect.midX, y: rect.midY)
                    }
                }
            }
            .clipped()
    }
}
