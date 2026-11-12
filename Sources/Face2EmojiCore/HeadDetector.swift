import CoreGraphics
import Vision

/// A face as reported by detection.
public struct DetectedFace: Equatable, Sendable {
    /// Vision-style: normalised, origin bottom-left, upright image. Runs from the eyebrows to the chin.
    public var box: CGRect
    /// Radians, Vision's sign convention; nil when detection reports no roll.
    public var roll: CGFloat?

    public init(box: CGRect, roll: CGFloat?) {
        self.box = box
        self.roll = roll
    }
}

/// A person's head and shoulders as reported by detection, found whether or not the face can be seen.
public struct DetectedBody: Equatable, Sendable {
    /// Vision-style: normalised, origin bottom-left, upright image. Its top edge runs along the
    /// crown of the head.
    public var box: CGRect
    /// 0...1.
    public var confidence: Float

    public init(box: CGRect, confidence: Float) {
        self.box = box
        self.confidence = confidence
    }
}

/// What detection finds in one image. A person can be in both lists.
public struct Detection: Equatable, Sendable {
    public var faces: [DetectedFace]
    public var bodies: [DetectedBody]

    public init(faces: [DetectedFace] = [], bodies: [DetectedBody] = []) {
        self.faces = faces
        self.bodies = bodies
    }
}

public protocol HeadDetecting: Sendable {
    /// `image` is already upright.
    func detect(in image: CGImage) async throws -> Detection
}

/// Finds faces with Vision's face-rectangles request and upper bodies with its human-rectangles
/// request, the two at once.
public struct VisionHeadDetector: HeadDetecting {
    public init() {}

    /// Runs on the global concurrent executor, never on the caller's actor.
    @concurrent
    public func detect(in image: CGImage) async throws -> Detection {
        async let faces = Self.faces(in: image)
        async let bodies = Self.bodies(in: image)
        return try await Detection(faces: faces, bodies: bodies)
    }

    private static func faces(in image: CGImage) async throws -> [DetectedFace] {
        // Pinned: revision4 (macOS 27+, the default there) reports roll clockwise-positive,
        // revision3 counter-clockwise-positive. revision3 behaves the same on every supported OS.
        let request = DetectFaceRectanglesRequest(.revision3)
        return try await request.perform(on: image, orientation: .up).map { observation in
            DetectedFace(box: observation.boundingBox.cgRect, roll: observation.roll.converted(to: .radians).value)
        }
    }

    private static func bodies(in image: CGImage) async throws -> [DetectedBody] {
        // Pinned, so that a new OS default cannot quietly move the boxes that `HeadPlacement` is tuned to.
        // revision3 (macOS 27+) still finds people whose face is hidden where revision2 often does not.
        let revision: DetectHumanRectanglesRequest.Revision
        if #available(macOS 27, *) { revision = .revision3 } else { revision = .revision2 }
        var request = DetectHumanRectanglesRequest(revision)
        request.upperBodyOnly = true
        return try await request.perform(on: image, orientation: .up).map { observation in
            DetectedBody(box: observation.boundingBox.cgRect, confidence: observation.confidence)
        }
    }
}
