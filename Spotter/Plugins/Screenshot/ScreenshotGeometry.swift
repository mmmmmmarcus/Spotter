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

    /// The one-point source rectangle a colour sample reads, aligned to the point grid and kept on
    /// the display so a click on the very edge still captures a real pixel.
    static func colorSampleRect(around point: CGPoint, within bounds: CGRect) -> CGRect {
        CGRect(
            x: min(max(point.x.rounded(.down), bounds.minX), bounds.maxX - 1),
            y: min(max(point.y.rounded(.down), bounds.minY), bounds.maxY - 1),
            width: 1,
            height: 1)
    }

    private static func clamped(_ point: CGPoint, to bounds: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY))
    }
}

/// The post-capture thumbnail's outer size: the capture aspect-fitted inside the design's box, plus
/// the frame that surrounds it. Pure so the harness can pin it against odd capture shapes.
enum ScreenshotThumbnail {
    static func outerSize(
        forPixelSize size: CGSize, maximum: CGSize, border: CGFloat
    ) -> CGSize {
        let inner = CGSize(
            width: max(maximum.width - border * 2, 1),
            height: max(maximum.height - border * 2, 1))
        guard size.width > 0, size.height > 0 else {
            return CGSize(width: inner.width + border * 2, height: inner.height + border * 2)
        }
        let scale = min(inner.width / size.width, inner.height / size.height)
        return CGSize(
            width: max((size.width * scale).rounded(), 1) + border * 2,
            height: max((size.height * scale).rounded(), 1) + border * 2)
    }
}

/// The pixel density a capture is rendered at. Retina is the display's own backing scale; 1x
/// produces one pixel per point, which is what a screenshot destined for the web usually wants.
enum ScreenshotCaptureScale: String, CaseIterable, Identifiable, Sendable {
    case retina
    case oneX

    var id: String { rawValue }
    var title: String { self == .retina ? "Retina" : "1x" }

    func pixelScale(nativeScale: CGFloat) -> CGFloat {
        switch self {
        case .retina: max(nativeScale, 1)
        case .oneX: 1
        }
    }

    /// The pixel dimensions a point-space rectangle captures to, never smaller than one pixel.
    func pixelSize(forPointSize size: CGSize, nativeScale: CGFloat) -> (width: Int, height: Int) {
        let scale = pixelScale(nativeScale: nativeScale)
        return (
            max(Int((size.width * scale).rounded()), 1),
            max(Int((size.height * scale).rounded()), 1))
    }
}
