import CoreGraphics

/// Turns detected faces and bodies into emoji placements that cover whole heads, hair and ears included.
public enum HeadPlacement {
    /// Emoji side ÷ the larger pixel side of a face box.
    public static let faceCoverFactor: CGFloat = 2.1

    /// How far the emoji's centre is raised above the face box's centre, as a fraction of the box's
    /// pixel height, along the face's own up axis. The box runs from the eyebrows to the chin, so its
    /// centre is low on the head.
    public static let faceCenterRaise: CGFloat = 0.2

    /// Emoji side ÷ the pixel width of a body box. Generous because the head is not always in the
    /// middle of the box: a raised or turned shoulder widens it on one side.
    public static let bodyCoverFactor: CGFloat = 0.9

    /// How far the emoji's top edge sits above the body box's top edge, which runs along the crown,
    /// as a fraction of the emoji's side.
    public static let bodyTopMargin: CGFloat = 0.1

    /// Every body Vision reports. Vision has a cutoff of its own: it reported nothing on 30 landscape
    /// wallpapers or on crops of the fixtures without a person, and as little as 0.28 for a fixture
    /// person whose face was hidden.
    public static let defaultBodyConfidenceThreshold: Float = 0

    /// One placement per face, then one per body whose confidence is above `bodyConfidenceThreshold`
    /// and whose head emoji does not already contain a face's centre (that person is covered by the
    /// face's emoji). A threshold of 1 or more covers faces only.
    public static func placements(
        for detection: Detection, imageSize: CGSize, emoji: String, bodyConfidenceThreshold: Float
    ) -> [EmojiPlacement] {
        let faces = detection.faces.map { placement(for: $0, imageSize: imageSize, emoji: emoji) }
        let faceCenters = detection.faces.map { CGPoint(x: $0.box.midX, y: 1 - $0.box.midY) }
        let bodies = detection.bodies
            .filter { $0.confidence > bodyConfidenceThreshold }
            .map { placement(for: $0, imageSize: imageSize, emoji: emoji) }
            .filter { head in !faceCenters.contains { contains(head, $0, imageSize: imageSize) } }
        return faces + bodies
    }

    public static func placement(for face: DetectedFace, imageSize: CGSize, emoji: String) -> EmojiPlacement {
        let box = face.box
        let faceSide = max(box.width * imageSize.width, box.height * imageSize.height)
        // Vision's roll is counter-clockwise-positive in its bottom-left space,
        // which is clockwise-negative on screen.
        let rotation = face.roll.map { -$0 } ?? 0
        // On screen (y down), a head turned `rotation` clockwise has its up axis at (sin, -cos).
        let raise = faceCenterRaise * box.height * imageSize.height
        return EmojiPlacement(
            emoji: emoji,
            center: CGPoint(
                x: box.midX + raise * sin(rotation) / imageSize.width,
                y: 1 - box.midY - raise * cos(rotation) / imageSize.height
            ),
            size: faceSide * faceCoverFactor / imageSize.width,
            rotation: rotation
        )
    }

    /// Centred across the box, hanging from just above its top edge. Upright: a body box tells
    /// nothing of the head's roll.
    public static func placement(for body: DetectedBody, imageSize: CGSize, emoji: String) -> EmojiPlacement {
        let side = bodyCoverFactor * body.box.width * imageSize.width
        let top = (1 - body.box.maxY) * imageSize.height - bodyTopMargin * side
        return EmojiPlacement(
            emoji: emoji,
            center: CGPoint(x: body.box.midX, y: (top + side / 2) / imageSize.height),
            size: side / imageSize.width
        )
    }

    /// Whether `point` (normalised, top-left origin) lies within the round emoji of `placement`.
    private static func contains(_ placement: EmojiPlacement, _ point: CGPoint, imageSize: CGSize) -> Bool {
        let dx = (point.x - placement.center.x) * imageSize.width
        let dy = (point.y - placement.center.y) * imageSize.height
        let radius = placement.size * imageSize.width / 2
        return dx * dx + dy * dy <= radius * radius
    }
}
