import CoreGraphics
import Testing
import Face2EmojiCore

@Test func glyphFillsSquareAndIsOpaqueInCentre() {
    let g = EmojiGlyph.image(for: "😀", side: 256)
    #expect(g.width == 256 && g.height == 256)
    #expect(alpha(of: g, x: 128, y: 128) == 255)        // centre fully opaque
    #expect(alpha(of: g, x: 1, y: 1) == 0)              // corner transparent (round glyph)
    #expect(alpha(of: g, x: 128, y: 3) > 0)             // ink reaches the top edge
    #expect(alpha(of: g, x: 3, y: 128) > 0)             // and the left edge
}

@Test func multiScalarEmojiIsOneGlyph() {
    // ZWJ sequence must render as a single glyph filling the square, not two side by side.
    let g = EmojiGlyph.image(for: "😶‍🌫️", side: 256)
    #expect(alpha(of: g, x: 128, y: 128) == 255)
    #expect(alpha(of: g, x: 128, y: 3) > 0)
}

@Test func glyphIsCachedAndShared() async {
    // Concurrent first requests must all end up with the one cached image.
    let images = await withTaskGroup(of: CGImage.self) { group in
        for _ in 0..<8 { group.addTask { EmojiGlyph.image(for: "🎃", side: 64) } }
        return await group.reduce(into: []) { $0.append($1) }
    }
    #expect(images.allSatisfy { $0 === images[0] })
}

@Test func drawCoversPlacementRectOnly() {
    let ctx = whiteContext(width: 400, height: 200)
    let p = EmojiPlacement(emoji: "😀", center: CGPoint(x: 0.25, y: 0.5), size: 0.25)   // 100 px square centred at (100,100) from top-left
    EmojiRenderer.draw([p], in: ctx, imageSize: CGSize(width: 400, height: 200))
    #expect(pixel(ctx, x: 100, y: 100) != white)        // covered
    #expect(pixel(ctx, x: 300, y: 100) == white)        // untouched
    #expect(pixel(ctx, x: 100, y: 20) == white)         // above the emoji
}

@Test func yAxisIsTopLeft() {
    let ctx = whiteContext(width: 200, height: 400)
    let p = EmojiPlacement(emoji: "😀", center: CGPoint(x: 0.5, y: 0.2), size: 0.4)     // near the TOP
    EmojiRenderer.draw([p], in: ctx, imageSize: CGSize(width: 200, height: 400))
    #expect(pixel(ctx, x: 100, y: 80) != white)
    #expect(pixel(ctx, x: 100, y: 320) == white)
}

@Test func rotationIsClockwise() {
    // 🤠 has a hat: ink is asymmetric top vs bottom. Rotating +90° must move the top of the glyph to the right.
    let up = render(EmojiPlacement(emoji: "🤠", center: CGPoint(x: 0.5, y: 0.5), size: 0.8, rotation: 0), side: 200)
    let cw = render(EmojiPlacement(emoji: "🤠", center: CGPoint(x: 0.5, y: 0.5), size: 0.8, rotation: .pi / 2), side: 200)
    #expect(pixel(up, x: 100, y: 30) == pixel(cw, x: 170, y: 100))
}

@Test func drawKeepsGlyphUpright() {
    // Drawn 1:1 over the whole canvas, the result must be the glyph itself over white,
    // neither flipped nor mirrored. 🤠 is asymmetric top to bottom, so a flip changes many samples.
    let glyph = EmojiGlyph.image(for: "🤠")
    let drawn = render(EmojiPlacement(emoji: "🤠", center: CGPoint(x: 0.5, y: 0.5), size: 1), side: glyph.width)
    let image = drawn.makeImage()!
    var mismatches: [String] = []
    for y in stride(from: 8, to: glyph.height, by: 16) {
        for x in stride(from: 8, to: glyph.width, by: 16) {
            let g = TestImages.pixel(of: glyph, x: x, y: y)
            // A premultiplied pixel over white: each channel gains the white let through, 255 − alpha.
            let expected = [g.r, g.g, g.b].map { Int($0) + 255 - Int(g.a) }
            let d = TestImages.pixel(of: image, x: x, y: y)
            if zip([d.r, d.g, d.b].map(Int.init), expected).contains(where: { abs($0 - $1) > 2 }) {
                mismatches.append("(\(x), \(y)): drew \(d), glyph \(g)")
            }
        }
    }
    #expect(mismatches.isEmpty, "\(mismatches.count) samples differ, first: \(mismatches.prefix(3))")
}

private let white = TestImages.RGBA(r: 255, g: 255, b: 255, a: 255)

private func alpha(of image: CGImage, x: Int, y: Int) -> UInt8 {
    TestImages.pixel(of: image, x: x, y: y).a
}

/// An sRGB RGBA8 context filled white, standing in for an upright photo.
private func whiteContext(width: Int, height: Int) -> CGContext {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context
}

/// The pixel at (x, y) of what has been drawn into `context`, rows counted from the top.
private func pixel(_ context: CGContext, x: Int, y: Int) -> TestImages.RGBA {
    TestImages.pixel(of: context.makeImage()!, x: x, y: y)
}

/// `placement` drawn on a white `side`×`side` photo.
private func render(_ placement: EmojiPlacement, side: Int) -> CGContext {
    let context = whiteContext(width: side, height: side)
    EmojiRenderer.draw([placement], in: context, imageSize: CGSize(width: side, height: side))
    return context
}
