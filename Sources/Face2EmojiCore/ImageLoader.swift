import CoreGraphics
import Foundation
import ImageIO

/// Reads photos from disk as upright pixels, applying any EXIF orientation tag.
public enum ImageLoader {
    /// The file cannot be opened or decoded as an image.
    public struct NotAnImage: Error {}

    /// Pixel size after applying the orientation tag.
    public static func uprightPixelSize(of url: URL) throws -> CGSize {
        let (source, index) = try primaryImage(at: url)
        return try uprightPixelSize(of: source, at: index)
    }

    /// Decoded with the orientation tag applied. `maxPixelSize` bounds the longest side; nil = full size.
    public static func loadUpright(_ url: URL, maxPixelSize: Int?) throws -> CGImage {
        let (source, index) = try primaryImage(at: url)
        let longestSide: Int
        if let maxPixelSize {
            longestSide = maxPixelSize
        } else {
            let size = try uprightPixelSize(of: source, at: index)
            longestSide = Int(max(size.width, size.height))
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longestSide,
            // Decode here, on the caller's thread, rather than lazily on first draw.
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else {
            throw NotAnImage()
        }
        return image
    }

    private static func primaryImage(at url: URL) throws -> (CGImageSource, Int) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 else {
            throw NotAnImage()
        }
        return (source, CGImageSourceGetPrimaryImageIndex(source))
    }

    private static func uprightPixelSize(of source: CGImageSource, at index: Int) throws -> CGSize {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { throw NotAnImage() }
        // Tags 5–8 turn the image a quarter turn, swapping its width and height.
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        return orientation >= 5 ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }
}
