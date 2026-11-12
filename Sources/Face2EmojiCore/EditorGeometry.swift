import CoreGraphics
import Foundation

/// Where the editor draws a photo and its emoji, and what the pointer means there.
///
/// The photo is drawn scaled to fit `bounds`, centred, at `photoFrame`. Each emoji is drawn in that
/// frame at `EmojiPlacement.rect(in:)`, turned clockwise about its centre by its rotation. Points are
/// in the editor view's space, origin top-left.
public struct EditorGeometry: Sendable {
    /// Side, in points, of the selected emoji's resize handle: a square centred on the emoji's
    /// bottom-right corner, turned with the emoji.
    public static let resizeHandleSide: CGFloat = 10
    /// A resize never makes an emoji's side smaller than this, in points.
    public static let minimumSide: CGFloat = 12

    /// Where the photo is drawn.
    public let photoFrame: CGRect

    /// `imageSize` (only its aspect ratio counts) scaled to fit `bounds` and centred in it. nil when
    /// either is empty: there is then nothing to draw or point at.
    public init?(imageSize: CGSize, bounds: CGRect) {
        guard imageSize.width > 0, imageSize.height > 0, !bounds.isEmpty else { return nil }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        photoFrame = CGRect(
            x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height
        )
    }

    /// `point` in placement coordinates: x ÷ the photo's width and y ÷ its height, from its top-left
    /// corner. Off the photo they fall outside 0…1.
    public func normalized(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - photoFrame.minX) / photoFrame.width, y: (point.y - photoFrame.minY) / photoFrame.height)
    }

    /// The point at placement coordinates `normalized`; the inverse of `normalized(_:)`.
    public func point(atNormalized normalized: CGPoint) -> CGPoint {
        CGPoint(x: photoFrame.minX + normalized.x * photoFrame.width, y: photoFrame.minY + normalized.y * photoFrame.height)
    }

    /// The placement's square before it is turned.
    public func square(of placement: EmojiPlacement) -> CGRect {
        placement.rect(in: photoFrame.size).offsetBy(dx: photoFrame.minX, dy: photoFrame.minY)
    }

    /// The placement drawn on top among those whose turned square contains `point`: the last of
    /// them in `placements`.
    public func topmostPlacement(at point: CGPoint, in placements: [EmojiPlacement]) -> EmojiPlacement? {
        placements.last { placement in
            let offset = offset(of: point, from: placement), half = side(of: placement) / 2
            return abs(offset.x) <= half && abs(offset.y) <= half
        }
    }

    /// Whether `point` is on the placement's resize handle.
    public func isOnResizeHandle(_ point: CGPoint, of placement: EmojiPlacement) -> Bool {
        let offset = offset(of: point, from: placement), half = side(of: placement) / 2
        return abs(offset.x - half) <= Self.resizeHandleSide / 2 && abs(offset.y - half) <= Self.resizeHandleSide / 2
    }

    /// The placement moved by `translation` points, so that the point grabbed stays under the
    /// pointer. Nothing keeps it on the photo.
    public func moving(_ placement: EmojiPlacement, by translation: CGSize) -> EmojiPlacement {
        let center = point(atNormalized: placement.center)
        var moved = placement
        moved.center = normalized(CGPoint(x: center.x + translation.width, y: center.y + translation.height))
        return moved
    }

    /// The placement resized so that its resize handle is under `pointer`: its side becomes
    /// 2 × max(|dx|, |dy|), where (dx, dy) is the pointer's offset from its centre in its turned
    /// frame, and at least `minimumSide`. Centre and rotation stay.
    public func resizing(_ placement: EmojiPlacement, handleTo pointer: CGPoint) -> EmojiPlacement {
        let offset = offset(of: pointer, from: placement)
        var resized = placement
        resized.size = max(2 * max(abs(offset.x), abs(offset.y)), Self.minimumSide) / photoFrame.width
        return resized
    }

    /// Side of the placement's square, in points.
    private func side(of placement: EmojiPlacement) -> CGFloat {
        placement.size * photoFrame.width
    }

    /// `point` relative to the placement's centre, in the placement's own frame: x along its bottom
    /// edge, y along its right edge, as they lie once turned.
    private func offset(of point: CGPoint, from placement: EmojiPlacement) -> CGPoint {
        let center = self.point(atNormalized: placement.center)
        let dx = point.x - center.x, dy = point.y - center.y
        let cosine = cos(placement.rotation), sine = sin(placement.rotation)
        // Turning clockwise on screen by r, with y pointing down, takes (x, y) to
        // (x cos r − y sin r, x sin r + y cos r); this undoes it.
        return CGPoint(x: dx * cosine + dy * sine, y: -dx * sine + dy * cosine)
    }
}
