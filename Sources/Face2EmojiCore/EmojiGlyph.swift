import CoreGraphics
import CoreText
import Foundation
import Synchronization

/// Emoji glyphs as square bitmaps, drawn with the system colour emoji font.
public enum EmojiGlyph {
    /// Square image, `side`×`side` px, transparent background, the glyph scaled so its
    /// ink bounds touch the square's edges (no font padding). Thread-safe, cached.
    ///
    /// Ink is what is more than a quarter opaque. Ink bounds that are not square fill the
    /// square along their longer side and are centred along the other.
    public static func image(for emoji: String, side: Int = 512) -> CGImage {
        let key = Key(emoji: emoji, side: side)
        if let cached = cache.withLock({ $0[key] }) { return cached }
        // Render outside the lock. Should another thread render the same glyph meanwhile,
        // keep whichever was stored first so every caller shares one image.
        let image = render(emoji, side: side)
        return cache.withLock { cache in
            if let stored = cache[key] { return stored }
            cache[key] = image
            return image
        }
    }

    private struct Key: Hashable {
        var emoji: String
        var side: Int
    }

    private static let cache = Mutex<[Key: CGImage]>([:])

    /// Pixels must be more than a quarter opaque to count as ink. Apple Color Emoji's bitmaps
    /// carry marks that are not part of the drawing: specks at most 16% opaque in two corners
    /// of the em square, and drop shadows under 2% opaque. The threshold skips those while
    /// keeping translucent parts of a drawing, such as the fog of 😶‍🌫️.
    private static let inkAlphaThreshold: UInt8 = 64

    private static func render(_ emoji: String, side: Int) -> CGImage {
        precondition(side > 0, "side must be positive")
        // "Apple Color Emoji", by the PostScript name CTFontCreateWithName prefers.
        let font = CTFontCreateWithName("AppleColorEmoji" as CFString, CGFloat(side), nil)
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: emoji, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        )
        // CTLineGetImageBounds is the union of the glyphs' bitmap boxes. For Apple Color Emoji
        // that is the whole em square, with the drawing inset in it by a margin that varies from
        // glyph to glyph. So draw that box filling the square once to find the ink, then draw
        // again with the ink filling it.
        let measuring = bitmap(side: side)
        let box = CTLineGetImageBounds(line, nil)
        guard !box.isEmpty else { return measuring.makeImage()! }
        let boxFit = fitting(box, into: CGFloat(side))
        measuring.concatenate(boxFit)
        CTLineDraw(line, measuring)
        guard let ink = inkBounds(in: measuring)?.applying(boxFit.inverted()) else { return measuring.makeImage()! }
        let context = bitmap(side: side)
        context.concatenate(fitting(ink, into: CGFloat(side)))
        CTLineDraw(line, context)
        return context.makeImage()!
    }

    /// Bounding box of the pixels more opaque than `inkAlphaThreshold`, in the context's
    /// bottom-left pixel space; nil if there are none. `context` must come from `bitmap(side:)`.
    private static func inkBounds(in context: CGContext) -> CGRect? {
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        var minX = Int.max, maxX = Int.min, minRow = Int.max, maxRow = Int.min
        for row in 0..<context.height {
            let rowStart = row * context.bytesPerRow
            for x in 0..<context.width where bytes[rowStart + x * 4 + 3] > inkAlphaThreshold {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minRow = min(minRow, row)
                maxRow = max(maxRow, row)
            }
        }
        guard minX <= maxX else { return nil }
        // Rows in memory run top-down; CoreGraphics' y axis points up.
        return CGRect(x: minX, y: context.height - 1 - maxRow, width: maxX - minX + 1, height: maxRow - minRow + 1)
    }

    /// Maps `rect` onto the `side`×`side` square: scaled uniformly until its longer side
    /// fills the square, and centred.
    private static func fitting(_ rect: CGRect, into side: CGFloat) -> CGAffineTransform {
        let scale = side / max(rect.width, rect.height)
        return CGAffineTransform(translationX: side / 2, y: side / 2)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -rect.midX, y: -rect.midY)
    }

    /// Transparent RGBA8 sRGB. Apple Color Emoji's colours all lie within sRGB.
    private static func bitmap(side: Int) -> CGContext {
        CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
    }
}
