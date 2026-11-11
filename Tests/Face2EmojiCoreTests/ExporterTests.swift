import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import Face2EmojiCore

@Test func keepsDimensionsAndAllowlistedMetadataOnly() throws {
    let src = try TestImages.writeJPEG(width: 640, height: 480, properties: [
        kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 37.33, kCGImagePropertyGPSLatitudeRef: "N"],
        kCGImagePropertyIPTCDictionary: [kCGImagePropertyIPTCCity: "Cupertino", kCGImagePropertyIPTCCaptionAbstract: "secret"],
        kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2025:06:01 12:00:00",
                                         kCGImagePropertyExifUserComment: "hello", kCGImagePropertyExifLensModel: "L"],
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFModel: "Cam", kCGImagePropertyTIFFArtist: "Me"]])
    let out = tempURL("out.jpg")
    try Exporter.export(source: src, placements: [], to: out)
    let props = try properties(of: out)
    #expect(props[kCGImagePropertyPixelWidth] as? Int == 640 && props[kCGImagePropertyPixelHeight] as? Int == 480)
    #expect(props[kCGImagePropertyGPSDictionary] == nil)
    #expect(props[kCGImagePropertyIPTCDictionary] == nil)
    let exif = try #require(props[kCGImagePropertyExifDictionary] as? [CFString: Any])
    #expect(exif[kCGImagePropertyExifDateTimeOriginal] as? String == "2025:06:01 12:00:00")
    #expect(exif[kCGImagePropertyExifLensModel] as? String == "L")
    #expect(exif[kCGImagePropertyExifUserComment] == nil)
    let tiff = try #require(props[kCGImagePropertyTIFFDictionary] as? [CFString: Any])
    #expect(tiff[kCGImagePropertyTIFFModel] as? String == "Cam")
    #expect(tiff[kCGImagePropertyTIFFArtist] == nil)
    #expect(try !Data(contentsOf: out).contains(Data("Cupertino".utf8)))   // not hiding in XMP either
    #expect(try !Data(contentsOf: out).contains(Data("secret".utf8)))
}
@Test func writesNoIPTCOrXMPBlockAtAll() throws {
    // ImageIO adds an empty Photoshop/IPTC block (APP13) to any JPEG it is given properties for.
    let src = try TestImages.writeJPEG(width: 64, height: 48, properties: [
        kCGImagePropertyIPTCDictionary: [kCGImagePropertyIPTCCity: "Cupertino"],
        kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2025:06:01 12:00:00"]])
    let out = tempURL("out.jpg")
    try Exporter.export(source: src, placements: [], to: out)
    let bytes = try Data(contentsOf: out)
    #expect(!bytes.contains(Data("Photoshop 3.0".utf8)))
    #expect(!bytes.contains(Data("8BIM".utf8)))
    #expect(!bytes.contains(Data("http://ns.adobe.com/xap/1.0/".utf8)))
    let exif = try #require(properties(of: out)[kCGImagePropertyExifDictionary] as? [CFString: Any])
    #expect(exif[kCGImagePropertyExifDateTimeOriginal] as? String == "2025:06:01 12:00:00")   // still a valid JPEG with EXIF
    #expect(try ImageLoader.loadUpright(out, maxPixelSize: nil).width == 64)
}
@Test func drawsEmojiWherePlacedAndNowhereElse() throws {
    let src = try TestImages.writeJPEG(width: 400, height: 200, gray: 0.5)
    let out = tempURL("out.jpg")
    try Exporter.export(source: src, placements: [EmojiPlacement(emoji: "😀", center: CGPoint(x: 0.25, y: 0.5), size: 0.25)], to: out)
    let img = try ImageLoader.loadUpright(out, maxPixelSize: nil)
    #expect(isYellowish(pixel(img, x: 100, y: 100)))
    #expect(isMidGray(pixel(img, x: 300, y: 100)))
}
@Test func orientationTaggedSourceComesOutUpright() throws {
    let rotated = try TestImages.reencode(TestImages.fixture("one-face.jpg"), exifOrientation: 6)
    let out = tempURL("out.jpg")
    try Exporter.export(source: rotated, placements: [], to: out)
    let props = try properties(of: out)
    #expect(props[kCGImagePropertyPixelWidth] as? Int == 1280 && props[kCGImagePropertyPixelHeight] as? Int == 1600)
    #expect((props[kCGImagePropertyOrientation] as? Int ?? 1) == 1)
}
@Test func keepsColourProfile() throws {
    let src = try TestImages.writeJPEG(width: 64, height: 64, colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!)
    let out = tempURL("out.jpg")
    try Exporter.export(source: src, placements: [], to: out)
    #expect(try ImageLoader.loadUpright(out, maxPixelSize: nil).colorSpace?.name == CGColorSpace.displayP3)
}
@Test func exportClipsOffImageEmoji() throws {
    let src = try TestImages.writeJPEG(width: 200, height: 200)
    let out = tempURL("out.jpg")
    try Exporter.export(source: src, placements: [
        EmojiPlacement(emoji: "😀", center: CGPoint(x: 0.0, y: 0.0), size: 0.5),      // straddles the corner
        EmojiPlacement(emoji: "😀", center: CGPoint(x: 3.0, y: -2.0), size: 0.5)],    // entirely outside
        to: out)
    let img = try ImageLoader.loadUpright(out, maxPixelSize: nil)
    #expect(img.width == 200 && img.height == 200)
    // The brief sampled (20, 20), but that is 70% across and down the glyph, on 😀's grin
    // (a brown lip line). (5, 5) is the face's yellow, inside the visible quarter.
    #expect(isYellowish(pixel(img, x: 5, y: 5)))
}
@Test func exportsGreyscaleSource() throws {
    let src = try TestImages.writeJPEG(width: 100, height: 100, colorSpace: CGColorSpaceCreateDeviceGray())
    let out = tempURL("out.jpg")
    try Exporter.export(source: src, placements: [EmojiPlacement(emoji: "😀", center: CGPoint(x: 0.5, y: 0.5), size: 0.5)], to: out)
    #expect(isYellowish(pixel(try ImageLoader.loadUpright(out, maxPixelSize: nil), x: 50, y: 50)))  // colour emoji survives
}
@Test func flattensTransparencyOntoWhite() throws {
    let src = try writeTransparentPNG(width: 20, height: 20)
    let out = tempURL("out.jpg")
    try Exporter.export(source: src, placements: [], to: out)
    let p = pixel(try ImageLoader.loadUpright(out, maxPixelSize: nil), x: 10, y: 10)
    #expect([p.r, p.g, p.b].allSatisfy { $0 >= 250 }, "\(p)")
}
@Test func refusesToOverwrite() throws {
    let src = try TestImages.writeJPEG(width: 10, height: 10)
    let out = tempURL("out.jpg"); try Data("x".utf8).write(to: out)
    #expect(throws: (any Error).self) { try Exporter.export(source: src, placements: [], to: out) }
    #expect(try Data(contentsOf: out) == Data("x".utf8))
}

/// The image properties ImageIO reads back from the file at `url`.
private func properties(of url: URL) throws -> [CFString: Any] {
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
}

/// A fully transparent PNG.
private func writeTransparentPNG(width: Int, height: Int) throws -> URL {
    let context = try #require(CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.clear(CGRect(x: 0, y: 0, width: width, height: height))
    let url = tempURL("clear.png")
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
    try #require(CGImageDestinationFinalize(destination))
    return url
}

/// The pixel at column `x`, row `y` counted from the top, in 8-bit sRGB.
private func pixel(_ image: CGImage, x: Int, y: Int) -> TestImages.RGBA {
    TestImages.pixel(of: image, x: x, y: y)
}

/// The yellow of a 😀 face: strong red and green, little blue.
private func isYellowish(_ p: TestImages.RGBA) -> Bool {
    p.r > 200 && p.g > 150 && p.b < 100
}

/// sRGB 0.5 grey after a JPEG round trip: every channel near 128 (188 would be 0.5 in linear light).
private func isMidGray(_ p: TestImages.RGBA) -> Bool {
    [p.r, p.g, p.b].allSatisfy { (120...136).contains($0) }
}
