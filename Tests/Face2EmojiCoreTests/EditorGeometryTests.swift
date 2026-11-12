import CoreGraphics
import Foundation
import Testing
import Face2EmojiCore

/// A 400×200 photo fitted into 300×300 points at (16, 16): drawn at (16, 91), 300×150.
private let geometry = EditorGeometry(
    imageSize: CGSize(width: 400, height: 200), bounds: CGRect(x: 16, y: 16, width: 300, height: 300)
)!

/// In the middle of the photo, at (166, 166), 100 points across.
private func placement(rotation: CGFloat = 0) -> EmojiPlacement {
    EmojiPlacement(emoji: "😀", center: CGPoint(x: 0.5, y: 0.5), size: 1.0 / 3, rotation: rotation)
}

private let center = CGPoint(x: 166, y: 166)

private func point(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint {
    CGPoint(x: center.x + dx, y: center.y + dy)
}

private func isClose(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 1e-9 }
private func isClose(_ a: CGPoint, _ b: CGPoint) -> Bool { isClose(a.x, b.x) && isClose(a.y, b.y) }
private func isClose(_ a: CGRect, _ b: CGRect) -> Bool {
    isClose(a.origin, b.origin) && isClose(a.width, b.width) && isClose(a.height, b.height)
}

// MARK: - Fitting and conversions

@Test func photoIsScaledToFitAndCentred() {
    #expect(isClose(geometry.photoFrame, CGRect(x: 16, y: 91, width: 300, height: 150)))
    let tall = EditorGeometry(imageSize: CGSize(width: 1000, height: 2000), bounds: CGRect(x: 0, y: 0, width: 400, height: 300))
    #expect(isClose(tall!.photoFrame, CGRect(x: 125, y: 0, width: 150, height: 300)))
}

@Test func nothingToFitHasNoGeometry() {
    #expect(EditorGeometry(imageSize: .zero, bounds: CGRect(x: 0, y: 0, width: 300, height: 300)) == nil)
    #expect(EditorGeometry(imageSize: CGSize(width: 400, height: 200), bounds: .zero) == nil)
    #expect(EditorGeometry(imageSize: CGSize(width: 400, height: 200), bounds: .null) == nil)
}

@Test func normalisedIsRelativeToThePhoto() {
    #expect(isClose(geometry.normalized(CGPoint(x: 16, y: 91)), .zero))
    #expect(isClose(geometry.normalized(CGPoint(x: 316, y: 241)), CGPoint(x: 1, y: 1)))
    #expect(isClose(geometry.normalized(CGPoint(x: 91, y: 203.5)), CGPoint(x: 0.25, y: 0.75)))
}

@Test func pointRoundTripsThroughNormalised() {
    // On the photo, in the margin and well off the photo.
    for p in [CGPoint(x: 37.5, y: 211.25), CGPoint(x: 5, y: 300), CGPoint(x: -120.3, y: 999.9)] {
        #expect(isClose(geometry.point(atNormalized: geometry.normalized(p)), p))
    }
}

@Test func squareIsWhereTheCanvasDrawsTheEmoji() {
    let p = placement()
    #expect(isClose(geometry.square(of: p), CGRect(x: 116, y: 116, width: 100, height: 100)))
    // The canvas draws at `rect(in:)` within the photo's frame.
    let inCanvas = p.rect(in: geometry.photoFrame.size)
    #expect(isClose(geometry.square(of: p), inCanvas.offsetBy(dx: geometry.photoFrame.minX, dy: geometry.photoFrame.minY)))
}

// MARK: - Hit-testing

@Test func hitIsInsideTheRotatedSquareOnly() {
    let diamond = placement(rotation: .pi / 4)
    #expect(geometry.topmostPlacement(at: center, in: [diamond])?.id == diamond.id)
    // Beyond the unrotated square's side but inside the turned one's corner.
    #expect(geometry.topmostPlacement(at: point(60, 0), in: [diamond])?.id == diamond.id)
    // Inside the unrotated square's corner, which turning has moved away.
    #expect(geometry.topmostPlacement(at: point(45, 45), in: [diamond]) == nil)
    #expect(geometry.topmostPlacement(at: point(45, 45), in: [placement()]) != nil)
    #expect(geometry.topmostPlacement(at: point(0, 80), in: [diamond]) == nil)
}

@Test func laterPlacementIsOnTop() {
    let below = placement()
    let above = EmojiPlacement(emoji: "🐶", center: CGPoint(x: 0.6, y: 0.5), size: 1.0 / 3) // centre (196, 166)
    let both = [below, above]
    #expect(geometry.topmostPlacement(at: point(20, 0), in: both)?.id == above.id)
    #expect(geometry.topmostPlacement(at: point(-40, 0), in: both)?.id == below.id)
    #expect(geometry.topmostPlacement(at: point(70, 0), in: both)?.id == above.id)
    #expect(geometry.topmostPlacement(at: point(0, 60), in: both) == nil)
    #expect(geometry.topmostPlacement(at: point(20, 0), in: [above, below])?.id == below.id)
}

@Test func handleSitsOnTheTurnedBottomRightCorner() {
    #expect(EditorGeometry.resizeHandleSide == 10)
    #expect(geometry.isOnResizeHandle(point(50, 50), of: placement()))
    #expect(geometry.isOnResizeHandle(point(46, 54), of: placement()))
    #expect(!geometry.isOnResizeHandle(point(56, 50), of: placement()))
    #expect(!geometry.isOnResizeHandle(point(-50, 50), of: placement()))
    // Turned a quarter clockwise, the bottom-right corner is at the bottom left on screen.
    let turned = placement(rotation: .pi / 2)
    #expect(geometry.isOnResizeHandle(point(-46, 46), of: turned))
    #expect(!geometry.isOnResizeHandle(point(50, 50), of: turned))
    #expect(!geometry.isOnResizeHandle(point(-50, 56), of: turned))
}

// MARK: - Move

@Test func moveKeepsTheGrabOffset() {
    let p = placement(rotation: 0.3)
    let grab = point(10, -10)
    let translation = CGSize(width: 30, height: -15)
    let moved = geometry.moving(p, by: translation)
    #expect(isClose(moved.center, CGPoint(x: 0.6, y: 0.4)))
    let pointer = CGPoint(x: grab.x + translation.width, y: grab.y + translation.height)
    let newCenter = geometry.point(atNormalized: moved.center)
    #expect(isClose(CGPoint(x: pointer.x - newCenter.x, y: pointer.y - newCenter.y), CGPoint(x: 10, y: -10)))
    #expect(moved.id == p.id && moved.emoji == p.emoji && moved.size == p.size && moved.rotation == p.rotation)
}

@Test func moveMayLeaveThePhoto() {
    let moved = geometry.moving(placement(), by: CGSize(width: 300, height: -150))
    #expect(isClose(moved.center, CGPoint(x: 1.5, y: -0.5)))
}

// MARK: - Resize

@Test func resizeSideIsTwiceTheLargerPointerOffset() {
    let p = placement()
    let resized = geometry.resizing(p, handleTo: point(30, 10))
    #expect(isClose(resized.size, 60.0 / 300))
    #expect(isClose(geometry.resizing(p, handleTo: point(-5, -40)).size, 80.0 / 300))
    #expect(resized.id == p.id && resized.emoji == p.emoji && resized.center == p.center && resized.rotation == p.rotation)
}

@Test func resizeMeasuresThePointerInTheTurnedFrame() {
    // 40 points to the right is (28.28, -28.28) in a frame turned 45° clockwise.
    let turned = placement(rotation: .pi / 4)
    let resized = geometry.resizing(turned, handleTo: point(40, 0))
    #expect(isClose(resized.size, 2 * 40 * sin(CGFloat.pi / 4) / 300))
    #expect(resized.center == turned.center && resized.rotation == turned.rotation)
    // Turned a quarter, the handle's corner lies down and to the left.
    #expect(isClose(geometry.resizing(placement(rotation: .pi / 2), handleTo: point(-30, 30)).size, 60.0 / 300))
}

@Test func resizedHandleIsUnderThePointer() {
    for rotation in [0, 0.4, -2.0] as [CGFloat] {
        let p = placement(rotation: rotation)
        // A pointer on the line from the centre through the turned bottom-right corner.
        let pointer = point(35 * (cos(rotation) - sin(rotation)), 35 * (sin(rotation) + cos(rotation)))
        let resized = geometry.resizing(p, handleTo: pointer)
        #expect(isClose(resized.size, 70.0 / 300))
        #expect(geometry.isOnResizeHandle(pointer, of: resized))
    }
}

@Test func resizeStopsAtTwelvePoints() {
    #expect(EditorGeometry.minimumSide == 12)
    #expect(isClose(geometry.resizing(placement(), handleTo: point(2, -3)).size, 12.0 / 300))
    #expect(isClose(geometry.resizing(placement(rotation: 1), handleTo: center).size, 12.0 / 300))
}
