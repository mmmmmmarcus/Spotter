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

/// The cross-fade schedule for the Space-driven pointer swap. A hardware cursor cannot animate
/// itself, so the overlay replays these frames; the curve is pure so the harness can pin it.
enum ScreenshotCursorTransition {
    /// Frames including the resting destination, which the animator supplies rather than composing.
    static let frameCount = 8
    /// How far the outgoing symbol shrinks away, and where the incoming one starts.
    static let minimumScale: CGFloat = 0.6
    /// The outgoing symbol is gone at 60% and the incoming one starts at 40%, so they overlap by a fifth of the swap.
    static let outgoingFadeEnd: CGFloat = 0.6
    static let incomingFadeStart: CGFloat = 0.4

    struct Frame: Equatable {
        var outgoingAlpha: CGFloat
        var outgoingScale: CGFloat
        var incomingAlpha: CGFloat
        var incomingScale: CGFloat
    }

    static func frame(at step: Int, of count: Int = frameCount) -> Frame {
        let progress = eased(CGFloat(min(max(step, 0), count)) / CGFloat(count))
        return Frame(
            outgoingAlpha: max(0, 1 - progress / outgoingFadeEnd),
            outgoingScale: 1 - (1 - minimumScale) * progress,
            incomingAlpha: max(0, (progress - incomingFadeStart) / (1 - incomingFadeStart)),
            incomingScale: minimumScale + (1 - minimumScale) * progress)
    }

    /// Smoothstep: the swap leaves and lands without a visible velocity step.
    static func eased(_ progress: CGFloat) -> CGFloat {
        let clamped = min(max(progress, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }
}
