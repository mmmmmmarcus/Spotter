import CoreGraphics
import Foundation

/// One on-screen window as the window server reports it, in top-origin display space.
struct ScreenshotWindowCandidate: Equatable {
    let id: CGWindowID
    let ownerPID: Int32
    let layer: Int
    let alpha: CGFloat
    let bounds: CGRect
}

/// Pure hit testing and coordinate flips for window capture mode.
enum ScreenshotWindowPicker {
    static let minimumSide: CGFloat = 24
    static let minimumAlpha: CGFloat = 0.05

    /// `candidates` must keep the window server's front-to-back order, so the first hit is the topmost window.
    static func target(
        at point: CGPoint, in candidates: [ScreenshotWindowCandidate], excluding pid: Int32
    ) -> ScreenshotWindowCandidate? {
        candidates.first { candidate in
            candidate.ownerPID != pid
                && candidate.layer == 0
                && candidate.alpha >= minimumAlpha
                && candidate.bounds.width >= minimumSide
                && candidate.bounds.height >= minimumSide
                && candidate.bounds.contains(point)
        }
    }

    /// Window-server rectangles are top-origin; AppKit's global space grows upward from the primary display.
    static func appKitRect(fromDisplaySpace rect: CGRect, primaryScreenMaxY: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX,
            y: primaryScreenMaxY - rect.maxY,
            width: rect.width,
            height: rect.height)
    }

    static func displaySpacePoint(fromAppKit point: CGPoint, primaryScreenMaxY: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenMaxY - point.y)
    }
}
