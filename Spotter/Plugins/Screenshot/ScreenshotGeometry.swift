import CoreGraphics

/// Pure selection geometry shared by the AppKit overlay and its standalone harness.
enum ScreenshotGeometry {
    static let cornerRadiusPixels: CGFloat = 4

    static func selectionRect(from start: CGPoint, to end: CGPoint, within bounds: CGRect) -> CGRect {
        let start = clamped(start, to: bounds)
        let end = clamped(end, to: bounds)
        return CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y))
    }

    /// AppKit display-local coordinates grow upward; ScreenCaptureKit display-local coordinates grow downward.
    static func captureRect(fromScreenLocal rect: CGRect, screenHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX,
            y: screenHeight - rect.maxY,
            width: rect.width,
            height: rect.height)
    }

    static func clampedPoint(_ point: CGPoint, to bounds: CGRect) -> CGPoint {
        clamped(point, to: bounds)
    }

    static func isCapturable(_ rect: CGRect) -> Bool {
        rect.width >= 1 && rect.height >= 1
    }

    static func roundedCornerRadius(forPixelSize size: CGSize) -> CGFloat {
        min(cornerRadiusPixels, min(size.width / 2, size.height / 2))
    }

    private static func clamped(_ point: CGPoint, to bounds: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY))
    }
}
