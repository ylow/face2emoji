import CoreGraphics
import Foundation
import Testing
import Face2EmojiCore

private func placements(for image: CGImage, _ detection: Detection) -> [EmojiPlacement] {
    HeadPlacement.placements(
        for: detection, imageSize: CGSize(width: image.width, height: image.height), emoji: "😀",
        bodyConfidenceThreshold: HeadPlacement.defaultBodyConfidenceThreshold
    )
}

/// Whether `point` (normalised, top-left origin) lies within the round emoji of `placement`.
private func covers(_ placement: EmojiPlacement, _ point: CGPoint, in image: CGImage) -> Bool {
    let width = CGFloat(image.width), height = CGFloat(image.height)
    let dx = (point.x - placement.center.x) * width, dy = (point.y - placement.center.y) * height
    return (dx * dx + dy * dy).squareRoot() <= placement.size * width / 2
}

@Test func findsOneFace() async throws {
    let img = try ImageLoader.loadUpright(TestImages.fixture("one-face.jpg"), maxPixelSize: nil)
    let faces = try await VisionHeadDetector().detect(in: img).faces
    #expect(faces.count == 1)
    let box = try #require(faces.first).box
    #expect(box.midY > 0.5)                       // bottom-left origin: the face is in the upper half
    #expect(CGRect(x: 0, y: 0, width: 1, height: 1).contains(box))
}

@Test func findsThreeFaces() async throws {
    let img = try ImageLoader.loadUpright(TestImages.fixture("three-faces.jpg"), maxPixelSize: nil)
    #expect(try await VisionHeadDetector().detect(in: img).faces.count == 3)
}

@Test(arguments: [("one-face.jpg", 1), ("three-faces.jpg", 3)])
func everyoneGetsOneEmoji(fixture: String, people: Int) async throws {
    // Each person is found both by face and by body; the body must not add a second emoji.
    let img = try ImageLoader.loadUpright(TestImages.fixture(fixture), maxPixelSize: nil)
    let detection = try await VisionHeadDetector().detect(in: img)
    #expect(detection.bodies.count == people)
    #expect(placements(for: img, detection).count == people)
}

@available(macOS 27, *)
@Test(arguments: ["one-face.jpg", "three-faces.jpg"])
func coversHeadsWhoseFacesAreHidden(fixture: String) async throws {
    let url = TestImages.fixture(fixture)
    let original = try ImageLoader.loadUpright(url, maxPixelSize: nil)
    let faces = try await VisionHeadDetector().detect(in: original).faces.map(\.box)
    let hidden = try TestImages.hidingFaces(url, faces)
    let detection = try await VisionHeadDetector().detect(in: hidden)
    try #require(detection.faces.isEmpty)
    let heads = placements(for: hidden, detection)
    #expect(heads.count == faces.count)
    for face in faces {
        // The whole hidden face: its centre and the ends of its brows, at the top corners of the box.
        let points = [(face.midX, face.midY), (face.minX, face.maxY), (face.maxX, face.maxY)].map { CGPoint(x: $0, y: 1 - $1) }
        #expect(heads.contains { head in points.allSatisfy { covers(head, $0, in: hidden) } }, "face at \(face)")
    }
}

@Test func orientationTaggedPhotoGivesSameFace() async throws {
    let plain = try ImageLoader.loadUpright(TestImages.fixture("one-face.jpg"), maxPixelSize: nil)
    let rotated = try ImageLoader.loadUpright(TestImages.reencode(TestImages.fixture("one-face.jpg"), exifOrientation: 6), maxPixelSize: nil)
    let a = try #require(try await VisionHeadDetector().detect(in: plain).faces.first).box
    let b = try #require(try await VisionHeadDetector().detect(in: rotated).faces.first).box
    #expect(abs(a.midX - b.midX) < 0.03 && abs(a.midY - b.midY) < 0.03)
}

@Test func rollSignMatchesPlacementConvention() async throws {
    // Rotate the one-face fixture's pixels 20° clockwise (as seen on screen), detect, convert.
    // The placement rotation must grow by about +0.35 rad relative to the untilted image.
    // The fixture face is itself tilted ~9° counter-clockwise, so compare against it rather than against 0.
    let level: CGImage = try TestImages.rotatedClockwise(TestImages.fixture("one-face.jpg"), degrees: 0)
    let tilted: CGImage = try TestImages.rotatedClockwise(TestImages.fixture("one-face.jpg"), degrees: 20)
    let levelFace = try #require(try await VisionHeadDetector().detect(in: level).faces.first)
    let face = try #require(try await VisionHeadDetector().detect(in: tilted).faces.first)
    let p0 = HeadPlacement.placement(for: levelFace, imageSize: CGSize(width: level.width, height: level.height), emoji: "😀")
    let p = HeadPlacement.placement(for: face, imageSize: CGSize(width: tilted.width, height: tilted.height), emoji: "😀")
    #expect(abs((p.rotation - p0.rotation) - 0.349) < 0.15)
}
