import CoreGraphics
import Testing
import Face2EmojiCore

@Test func centresOnFaceAndFlipsY() {
    // 4000×3000 image, face box 400×600 px whose bottom-left is at (1000, 300) from the bottom-left.
    let face = DetectedFace(box: CGRect(x: 0.25, y: 0.1, width: 0.1, height: 0.2), roll: nil)
    let p = FacePlacement.placement(for: face, imageSize: CGSize(width: 4000, height: 3000), emoji: "😀")
    #expect(abs(p.center.x - 0.30) < 1e-9)
    #expect(abs(p.center.y - 0.80) < 1e-9)          // 1 - (0.1 + 0.2/2)
    #expect(abs(p.size - (600 * 1.4) / 4000) < 1e-9) // larger side × 1.4 ÷ width
    #expect(p.rotation == 0)
    #expect(p.emoji == "😀")
}

@Test func rollBecomesClockwiseRotation() {
    // Vision roll is counter-clockwise-positive in its bottom-left space; on screen that is clockwise-negative.
    let face = DetectedFace(box: CGRect(x: 0, y: 0, width: 0.1, height: 0.1), roll: 0.3)
    let p = FacePlacement.placement(for: face, imageSize: CGSize(width: 100, height: 100), emoji: "😀")
    #expect(abs(p.rotation - (-0.3)) < 1e-9)
}
