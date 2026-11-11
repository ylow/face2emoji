import CoreGraphics

/// A face as reported by detection.
public struct DetectedFace: Equatable, Sendable {
    /// Vision-style: normalised, origin bottom-left, upright image.
    public var box: CGRect
    /// Radians, Vision's sign convention; nil when detection reports no roll.
    public var roll: CGFloat?

    public init(box: CGRect, roll: CGFloat?) {
        self.box = box
        self.roll = roll
    }
}

/// Turns a detected face into the emoji placement that covers it.
public enum FacePlacement {
    /// Emoji side ÷ the larger pixel side of the face box, so the emoji covers the
    /// whole head rather than only eyes-to-chin.
    public static let coverFactor: CGFloat = 1.4

    public static func placement(for face: DetectedFace, imageSize: CGSize, emoji: String) -> EmojiPlacement {
        let box = face.box
        let faceSide = max(box.width * imageSize.width, box.height * imageSize.height)
        return EmojiPlacement(
            emoji: emoji,
            center: CGPoint(x: box.midX, y: 1 - box.midY),
            size: faceSide * coverFactor / imageSize.width,
            // Vision's roll is counter-clockwise-positive in its bottom-left space,
            // which is clockwise-negative on screen.
            rotation: face.roll.map { -$0 } ?? 0
        )
    }
}
