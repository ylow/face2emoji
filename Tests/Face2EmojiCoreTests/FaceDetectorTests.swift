import CoreGraphics
import Foundation
import Testing
import Face2EmojiCore

@Test func findsOneFace() async throws {
    let img = try ImageLoader.loadUpright(TestImages.fixture("one-face.jpg"), maxPixelSize: nil)
    let faces = try await VisionFaceDetector().detectFaces(in: img)
    #expect(faces.count == 1)
    let box = try #require(faces.first).box
    #expect(box.midY > 0.5)                       // bottom-left origin: the face is in the upper half
    #expect(CGRect(x: 0, y: 0, width: 1, height: 1).contains(box))
}

@Test func findsThreeFaces() async throws {
    let img = try ImageLoader.loadUpright(TestImages.fixture("three-faces.jpg"), maxPixelSize: nil)
    #expect(try await VisionFaceDetector().detectFaces(in: img).count == 3)
}

@Test func orientationTaggedPhotoGivesSameFace() async throws {
    let plain = try ImageLoader.loadUpright(TestImages.fixture("one-face.jpg"), maxPixelSize: nil)
    let rotated = try ImageLoader.loadUpright(TestImages.reencode(TestImages.fixture("one-face.jpg"), exifOrientation: 6), maxPixelSize: nil)
    let a = try #require(try await VisionFaceDetector().detectFaces(in: plain).first).box
    let b = try #require(try await VisionFaceDetector().detectFaces(in: rotated).first).box
    #expect(abs(a.midX - b.midX) < 0.03 && abs(a.midY - b.midY) < 0.03)
}

@Test func rollSignMatchesPlacementConvention() async throws {
    // Rotate the one-face fixture's pixels 20° clockwise (as seen on screen), detect, convert.
    // The placement rotation must grow by about +0.35 rad relative to the untilted image.
    // The fixture face is itself tilted ~9° counter-clockwise, so compare against it rather than against 0.
    let level: CGImage = try TestImages.rotatedClockwise(TestImages.fixture("one-face.jpg"), degrees: 0)
    let tilted: CGImage = try TestImages.rotatedClockwise(TestImages.fixture("one-face.jpg"), degrees: 20)
    let levelFace = try #require(try await VisionFaceDetector().detectFaces(in: level).first)
    let face = try #require(try await VisionFaceDetector().detectFaces(in: tilted).first)
    let p0 = FacePlacement.placement(for: levelFace, imageSize: CGSize(width: level.width, height: level.height), emoji: "😀")
    let p = FacePlacement.placement(for: face, imageSize: CGSize(width: tilted.width, height: tilted.height), emoji: "😀")
    #expect(abs((p.rotation - p0.rotation) - 0.349) < 0.15)
}
