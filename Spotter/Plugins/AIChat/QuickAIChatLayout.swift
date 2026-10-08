import Foundation
import CoreGraphics

enum QuickAIChatLayout {
    static func initialFrame(size: CGSize, visibleFrame: CGRect, bottomGap: CGFloat, margin: CGFloat) -> CGRect {
        let safe = visibleFrame.insetBy(dx: margin, dy: margin)
        let width = min(size.width, safe.width)
        let height = min(size.height, safe.height)
        return CGRect(x: safe.midX - width / 2,
            y: min(visibleFrame.minY + bottomGap, safe.maxY - height), width: width, height: height)
    }

    static func resizedFrame(_ frame: CGRect, width: CGFloat, height: CGFloat, visibleFrame: CGRect, margin: CGFloat, anchorTrailing: Bool = false) -> CGRect {
        let safe = visibleFrame.insetBy(dx: margin, dy: margin)
        let size = CGSize(width: min(width, safe.width), height: min(height, safe.height))
        let proposedX = anchorTrailing ? frame.maxX - size.width : frame.midX - size.width / 2
        return CGRect(x: max(safe.minX, min(proposedX, safe.maxX - size.width)),
            y: max(safe.minY, min(frame.minY, safe.maxY - size.height)), width: size.width, height: size.height)
    }
}
