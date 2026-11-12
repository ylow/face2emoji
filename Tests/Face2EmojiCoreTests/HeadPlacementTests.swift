import CoreGraphics
import Testing
import Face2EmojiCore

private let imageSize = CGSize(width: 4000, height: 3000)

@Test func centresOnFaceAndFlipsY() {
    // Face box 400×600 px whose bottom-left is at (1000, 300) from the bottom-left.
    let face = DetectedFace(box: CGRect(x: 0.25, y: 0.1, width: 0.1, height: 0.2), roll: nil)
    let p = HeadPlacement.placement(for: face, imageSize: imageSize, emoji: "😀")
    #expect(abs(p.center.x - 0.30) < 1e-9)
    #expect(abs(p.center.y - (0.80 - 0.2 * 600 / 3000)) < 1e-9) // 1 - (0.1 + 0.2/2), raised 0.2 × 600 px
    #expect(abs(p.size - (600 * 2.1) / 4000) < 1e-9)            // larger side × 2.1 ÷ width
    #expect(p.rotation == 0)
    #expect(p.emoji == "😀")
}

@Test func rollBecomesClockwiseRotation() {
    // Vision roll is counter-clockwise-positive in its bottom-left space; on screen that is clockwise-negative.
    let face = DetectedFace(box: CGRect(x: 0, y: 0, width: 0.1, height: 0.1), roll: 0.3)
    let p = HeadPlacement.placement(for: face, imageSize: CGSize(width: 100, height: 100), emoji: "😀")
    #expect(abs(p.rotation - (-0.3)) < 1e-9)
}

@Test func tiltedFaceIsRaisedAlongItsOwnUpAxis() {
    // The face of the first test, its head turned 30° clockwise on screen (Vision roll −30°). The centre moves
    // 0.2 × 600 px = 120 px toward the top of the head: right by 120 sin 30° px and up by 120 cos 30° px.
    let face = DetectedFace(box: CGRect(x: 0.25, y: 0.1, width: 0.1, height: 0.2), roll: -.pi / 6)
    let p = HeadPlacement.placement(for: face, imageSize: imageSize, emoji: "😀")
    #expect(abs(p.rotation - .pi / 6) < 1e-9)
    #expect(abs(p.center.x - (0.30 + 120 * sin(Double.pi / 6) / 4000)) < 1e-9)   // 0.315
    #expect(abs(p.center.y - (0.80 - 120 * cos(Double.pi / 6) / 3000)) < 1e-9)  // ≈ 0.76536
    #expect(abs(p.size - (600 * 2.1) / 4000) < 1e-9)
}

@Test func bodyHeadHangsFromTheTopOfTheBox() {
    // Body box 1000 px wide whose top edge is 300 px below the top of the image. The emoji is 0.9 × 1000 =
    // 900 px across, its top edge 0.1 × 900 = 90 px above the box's: it spans y 210…1110 px.
    let body = DetectedBody(box: CGRect(x: 0.5, y: 0.2, width: 0.25, height: 0.7), confidence: 0.5)
    let p = HeadPlacement.placement(for: body, imageSize: imageSize, emoji: "😀")
    #expect(abs(p.center.x - 0.625) < 1e-9)
    #expect(abs(p.center.y - 660.0 / 3000) < 1e-9)
    #expect(abs(p.size - 900.0 / 4000) < 1e-9)
    #expect(p.rotation == 0)
    #expect(p.emoji == "😀")
}

/// A face whose centre is inside the head emoji of `body` below: (0.6, 1 − 0.83) = 2400 px across, 510 px down,
/// against the head's centre at (2500, 660) px and radius 450 px.
private let faceOfBody = DetectedFace(box: CGRect(x: 0.58, y: 0.8, width: 0.04, height: 0.06), roll: nil)
private let body = DetectedBody(box: CGRect(x: 0.5, y: 0.2, width: 0.25, height: 0.7), confidence: 0.5)
/// Far to the left of `body`'s head.
private let otherFace = DetectedFace(box: CGRect(x: 0.05, y: 0.5, width: 0.04, height: 0.06), roll: nil)

@Test func bodyWhoseHeadHasAFaceGetsNoSecondEmoji() {
    let detection = Detection(faces: [faceOfBody], bodies: [body])
    let ps = HeadPlacement.placements(for: detection, imageSize: imageSize, emoji: "😀", bodyConfidenceThreshold: 0)
    #expect(ps.map(\.center) == [HeadPlacement.placement(for: faceOfBody, imageSize: imageSize, emoji: "😀").center])
}

@Test func bodyWithoutAFaceIsCoveredAfterTheFaces() {
    let detection = Detection(faces: [otherFace], bodies: [body])
    let ps = HeadPlacement.placements(for: detection, imageSize: imageSize, emoji: "😀", bodyConfidenceThreshold: 0.4)
    #expect(ps.map(\.center) == [
        HeadPlacement.placement(for: otherFace, imageSize: imageSize, emoji: "😀").center,
        HeadPlacement.placement(for: body, imageSize: imageSize, emoji: "😀").center,
    ])
}

@Test func bodyIsCoveredOnlyWhenItsConfidenceIsAboveTheThreshold() {
    let detection = Detection(faces: [otherFace], bodies: [body])
    for threshold: Float in [0.5, 0.9, 1] {
        let ps = HeadPlacement.placements(for: detection, imageSize: imageSize, emoji: "😀", bodyConfidenceThreshold: threshold)
        #expect(ps.count == 1, "threshold \(threshold)")
    }
}
