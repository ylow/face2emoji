import CoreGraphics
import Foundation

/// One emoji covering part of a photo, stored relative to the upright image so it
/// survives any change of display size.
public struct EmojiPlacement: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var emoji: String
    /// Centre of the emoji, normalised (x ÷ image width, y ÷ image height), origin top-left.
    public var center: CGPoint
    /// Side of the emoji's square ÷ image width.
    public var size: CGFloat
    /// Radians, positive = clockwise as seen on screen.
    public var rotation: CGFloat

    public init(id: UUID = UUID(), emoji: String, center: CGPoint, size: CGFloat, rotation: CGFloat = 0) {
        self.id = id
        self.emoji = emoji
        self.center = center
        self.size = size
        self.rotation = rotation
    }

    /// Unrotated square in a top-left-origin space of `canvas` size (pixels or points).
    public func rect(in canvas: CGSize) -> CGRect {
        let side = size * canvas.width
        return CGRect(
            x: center.x * canvas.width - side / 2,
            y: center.y * canvas.height - side / 2,
            width: side,
            height: side
        )
    }
}
