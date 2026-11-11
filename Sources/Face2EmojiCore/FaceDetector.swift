import CoreGraphics
import Vision

public protocol FaceDetecting: Sendable {
    /// `image` is already upright.
    func detectFaces(in image: CGImage) async throws -> [DetectedFace]
}

/// Finds faces with Vision's face-rectangles request.
public struct VisionFaceDetector: FaceDetecting {
    public init() {}

    /// Runs on the global concurrent executor, never on the caller's actor.
    @concurrent
    public func detectFaces(in image: CGImage) async throws -> [DetectedFace] {
        // Pinned: revision4 (macOS 27+, the default there) reports roll clockwise-positive,
        // revision3 counter-clockwise-positive. revision3 behaves the same on every supported OS.
        let request = DetectFaceRectanglesRequest(.revision3)
        let observations = try await request.perform(on: image, orientation: .up)
        return observations.map { observation in
            DetectedFace(
                box: observation.boundingBox.cgRect,
                roll: observation.roll.converted(to: .radians).value
            )
        }
    }
}
