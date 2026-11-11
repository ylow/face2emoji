import CoreGraphics

/// Draws emoji placements onto an upright photo.
public enum EmojiRenderer {
    /// `context` is a bitmap context in CoreGraphics' default bottom-left space whose
    /// full extent, `imageSize`, is the upright photo. Draws each placement's glyph
    /// in its rect, rotated about its centre, with high interpolation quality.
    public static func draw(_ placements: [EmojiPlacement], in context: CGContext, imageSize: CGSize) {
        context.saveGState()
        defer { context.restoreGState() }
        context.interpolationQuality = .high
        for placement in placements {
            let rect = placement.rect(in: imageSize)
            context.saveGState()
            // Placements count y down from the top and turn clockwise-positive on screen;
            // CoreGraphics' y axis points up, so mirror the centre and negate the angle.
            context.translateBy(x: rect.midX, y: imageSize.height - rect.midY)
            context.rotate(by: -placement.rotation)
            context.draw(
                EmojiGlyph.image(for: placement.emoji),
                in: CGRect(x: -rect.width / 2, y: -rect.height / 2, width: rect.width, height: rect.height)
            )
            context.restoreGState()
        }
    }
}
