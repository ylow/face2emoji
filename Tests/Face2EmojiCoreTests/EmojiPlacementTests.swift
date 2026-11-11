import CoreGraphics
import Testing
import Face2EmojiCore

@Test func rectScalesBySizeTimesWidth() {
    let p = EmojiPlacement(emoji: "😀", center: CGPoint(x: 0.5, y: 0.25), size: 0.2)
    #expect(p.rect(in: CGSize(width: 1000, height: 800)) == CGRect(x: 400, y: 100, width: 200, height: 200))
}
