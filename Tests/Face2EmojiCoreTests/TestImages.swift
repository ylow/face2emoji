import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

/// Builds test inputs with ImageIO and CoreGraphics directly, so tests of `ImageLoader`
/// do not depend on `ImageLoader` to make their own inputs.
enum TestImages {
    static func fixture(_ name: String) -> URL {
        guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures") else {
            fatalError("Missing test fixture \(name)")
        }
        return url
    }

    /// Writes a JPEG of solid `gray` to a temp file with the given properties dictionary.
    static func writeJPEG(width: Int, height: Int, gray: CGFloat = 0.5, properties: [CFString: Any] = [:]) throws -> URL {
        let context = try bitmap(width: width, height: height)
        context.setFillColor(CGColor(srgbRed: gray, green: gray, blue: gray, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try write(try #require(context.makeImage()), properties: properties)
    }

    /// Re-encodes `source` with its pixels rotated so that EXIF `orientation` displays it upright again.
    /// `source` must carry no orientation tag of its own (the fixtures carry none).
    static func reencode(_ source: URL, exifOrientation: Int) throws -> URL {
        let upright = CIImage(cgImage: try storedPixels(of: source))
        // `oriented(o)` turns pixels stored under tag `o` upright. To store under tag `o` we apply
        // the inverse turn: every orientation is its own inverse except 6 and 8, which undo each other.
        let inverse = [6: 8, 8: 6][exifOrientation] ?? exifOrientation
        let stored = upright.oriented(forExifOrientation: Int32(inverse))
        let pixels = try #require(CIContext().createCGImage(stored, from: stored.extent))
        return try write(pixels, properties: [kCGImagePropertyOrientation: exifOrientation])
    }

    /// The pixels of `url` turned `degrees` clockwise as seen on screen about the image centre,
    /// on a canvas of the same size (corners that leave the canvas are cut off).
    static func rotatedClockwise(_ url: URL, degrees: CGFloat) throws -> CGImage {
        let image = try storedPixels(of: url)
        let width = CGFloat(image.width), height = CGFloat(image.height)
        let context = try bitmap(width: image.width, height: image.height)
        // CoreGraphics' y axis points up, so a clockwise turn on screen is a negative angle.
        context.translateBy(x: width / 2, y: height / 2)
        context.rotate(by: -degrees * .pi / 180)
        context.translateBy(x: -width / 2, y: -height / 2)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    private static func storedPixels(of url: URL) throws -> CGImage {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    private static func bitmap(width: Int, height: Int) throws -> CGContext {
        let sRGB = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        return try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: sRGB, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
    }

    private static func write(_ image: CGImage, properties: [CFString: Any]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).jpg")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        try #require(CGImageDestinationFinalize(destination))
        return url
    }
}
