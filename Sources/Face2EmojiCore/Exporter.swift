import CoreGraphics
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Writes one photo, with its emojis drawn in, as a JPEG.
public enum Exporter {
    public static let jpegQuality = 0.9

    /// The photo could not be drawn or encoded as a JPEG.
    public struct EncodingFailed: Error {}

    /// Writes `source` as a JPEG at `destination`: upright (orientation tag 1), at its full pixel
    /// size, with `placements` drawn in. Keeps the source's colour profile when it is RGB and
    /// converts other sources to sRGB. Of the source's metadata only the allowlisted fields survive.
    /// Throws, leaving `destination` untouched, if anything already exists there.
    public static func export(source: URL, placements: [EmojiPlacement], to destination: URL) throws {
        let jpeg = try encodeJPEG(compose(source, placements), metadata: allowlistedMetadata(of: source))
        // Write beside the destination, then move into place, so a failed write never leaves
        // a partial file under the destination's name.
        let temporary = destination.deletingLastPathComponent().appending(path: ".\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try jpeg.write(to: temporary)
        try moveWithoutReplacing(temporary, to: destination)
    }

    /// The metadata kept, by property dictionary. Everything else, including the whole GPS, IPTC
    /// and XMP blocks and maker notes, is dropped: much of it reveals place or identity.
    /// (Computed because CFString is not Sendable, so it cannot be a stored static.)
    private static var allowlist: [CFString: Set<CFString>] { [
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake, kCGImagePropertyTIFFModel, kCGImagePropertyTIFFDateTime],
        kCGImagePropertyExifDictionary: [
            kCGImagePropertyExifDateTimeOriginal, kCGImagePropertyExifDateTimeDigitized,
            kCGImagePropertyExifOffsetTime, kCGImagePropertyExifOffsetTimeOriginal, kCGImagePropertyExifOffsetTimeDigitized,
            kCGImagePropertyExifSubsecTimeOriginal, kCGImagePropertyExifSubsecTimeDigitized,
            kCGImagePropertyExifExposureTime, kCGImagePropertyExifFNumber, kCGImagePropertyExifISOSpeedRatings,
            kCGImagePropertyExifExposureBiasValue, kCGImagePropertyExifExposureProgram, kCGImagePropertyExifMeteringMode,
            kCGImagePropertyExifFlash, kCGImagePropertyExifWhiteBalance,
            kCGImagePropertyExifFocalLength, kCGImagePropertyExifFocalLenIn35mmFilm,
            kCGImagePropertyExifLensMake, kCGImagePropertyExifLensModel, kCGImagePropertyExifLensSpecification,
        ],
    ] }

    /// The upright photo at full size with `placements` drawn on it, in the photo's colour space
    /// if that is RGB, otherwise in sRGB (emoji are in colour even on a greyscale photo).
    private static func compose(_ source: URL, _ placements: [EmojiPlacement]) throws -> CGImage {
        let photo = try ImageLoader.loadUpright(source, maxPixelSize: nil)
        let space = photo.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil, width: photo.width, height: photo.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw EncodingFailed() }
        let size = CGSize(width: photo.width, height: photo.height)
        // JPEG has no transparency: flatten any transparent parts onto white rather than black.
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        context.draw(photo, in: CGRect(origin: .zero, size: size))
        EmojiRenderer.draw(placements, in: context, imageSize: size)
        guard let image = context.makeImage() else { throw EncodingFailed() }
        return image
    }

    /// The source's allowlisted metadata, as `CGImageDestinationAddImage` properties.
    private static func allowlistedMetadata(of source: URL) -> [CFString: Any] {
        // The pixels are written upright. ImageIO writes the pixel-dimension fields from the image.
        var kept: [CFString: Any] = [kCGImagePropertyOrientation: 1]
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(
                  imageSource, CGImageSourceGetPrimaryImageIndex(imageSource), nil
              ) as? [CFString: Any]
        else { return kept }
        for (dictionaryKey, keys) in allowlist {
            guard let dictionary = properties[dictionaryKey] as? [CFString: Any] else { continue }
            let allowed = dictionary.filter { keys.contains($0.key) }
            if !allowed.isEmpty { kept[dictionaryKey] = allowed }
        }
        return kept
    }

    /// `image` as JPEG data carrying `metadata` and no other metadata block.
    private static func encodeJPEG(_ image: CGImage, metadata: [CFString: Any]) throws -> Data {
        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(encoded, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw EncodingFailed() }
        var properties = metadata
        properties[kCGImageDestinationLossyCompressionQuality] = jpegQuality
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw EncodingFailed() }
        var jpeg = encoded as Data
        removeAPP13Segments(from: &jpeg)
        return jpeg
    }

    /// Removes the APP13 (Photoshop) segments of `jpeg`. Given any properties at all, ImageIO
    /// adds one holding an empty IPTC record; no ImageIO option leaves it out.
    private static func removeAPP13Segments(from jpeg: inout Data) {
        // After the start-of-image marker come marker segments, each 0xFF, a marker byte and a
        // big-endian length that counts itself, until start-of-scan (0xDA) begins the image data.
        var offset = jpeg.startIndex + 2
        while offset + 4 <= jpeg.endIndex, jpeg[offset] == 0xFF, jpeg[offset + 1] != 0xDA {
            let end = offset + 2 + (Int(jpeg[offset + 2]) << 8 | Int(jpeg[offset + 3]))
            guard end <= jpeg.endIndex else { return }
            if jpeg[offset + 1] == 0xED {
                jpeg.removeSubrange(offset..<end)
            } else {
                offset = end
            }
        }
    }

    /// Renames `file` to `destination`, failing if anything is already there.
    private static func moveWithoutReplacing(_ file: URL, to destination: URL) throws {
        let failure = file.withUnsafeFileSystemRepresentation { from in
            destination.withUnsafeFileSystemRepresentation { to in
                renamex_np(from, to, UInt32(RENAME_EXCL)) == 0 ? nil : errno
            }
        }
        guard let failure else { return }
        guard failure == ENOTSUP else { throw POSIXError(POSIXErrorCode(rawValue: failure) ?? .EIO) }
        // FAT and exFAT volumes cannot rename exclusively. moveItem refuses an existing
        // destination too, but checks before renaming rather than atomically.
        try FileManager.default.moveItem(at: file, to: destination)
    }
}
