import Foundation
import CoreGraphics

enum QuickClipboardPresentation {
    static let limit = 5
    static let width: CGFloat = 120
    static let rowHeight: CGFloat = 32
    static let cornerRadius: CGFloat = rowHeight / 2
    static let spacing: CGFloat = 8
    static let safety: CGFloat = 8
    static let canvasMargin: CGFloat = 64
    static let initialScale: CGFloat = 0.20
    static let openingDuration = 0.455
    static let closingDuration = 0.20

    static func recentItems(_ items: [ClipboardItem]) -> [ClipboardItem] {
        Array(items.prefix(limit))
    }

    static func title(for item: ClipboardItem) -> String {
        guard let text = item.text else { return item.isScreenshot ? "Screenshot" : "Image" }
        let prefix = text.prefix(161)
        let preview = prefix.prefix(160).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return (preview.isEmpty ? "Text" : preview) + (prefix.count > 160 ? "…" : "")
    }

    static func symbol(for item: ClipboardItem) -> String {
        item.textForm?.systemImage ?? (item.isScreenshot ? "camera.viewfinder" : "photo")
    }

    static func size(count: Int) -> CGSize {
        let columns = CGFloat(max(0, min(limit, count)))
        return CGSize(width: columns * (width + spacing) + rowHeight, height: rowHeight)
    }

    static func rowFrames(count: Int) -> [CGRect] {
        rowFrames(widths: Array(repeating: width, count: max(0, min(limit, count))) + [rowHeight])
    }

    static func rowFrames(widths: [CGFloat]) -> [CGRect] {
        var x: CGFloat = 0
        return widths.map { width in
            defer { x += width + spacing }
            return CGRect(x: x, y: 0, width: width, height: rowHeight)
        }
    }

    static func totalWidth(_ widths: [CGFloat]) -> CGFloat {
        widths.reduce(0, +) + CGFloat(max(0, widths.count - 1)) * spacing
    }

    static func frame(anchor: CGRect, screen: CGRect, count: Int, contentWidth: CGFloat? = nil) -> CGRect {
        let safe = screen.insetBy(dx: safety, dy: safety)
        var size = size(count: count)
        if let contentWidth { size.width = min(size.width, contentWidth) }
        let preferredX = anchor.height > 0 ? anchor.minX : anchor.maxX + 12
        let x = preferredX + size.width <= safe.maxX ? preferredX : anchor.maxX - (anchor.height > 0 ? 0 : 12) - size.width
        let y = anchor.maxY + 12 + size.height <= safe.maxY ? anchor.maxY + 12 : anchor.minY - 12 - size.height
        return CGRect(x: max(safe.minX, min(x, safe.maxX - size.width)),
            y: max(safe.minY, min(y, safe.maxY - size.height)), width: size.width, height: size.height)
    }

    static func fadeProgress(elapsed: Double, duration: Double, easeIn: Bool) -> Float {
        let progress = max(0, min(1, elapsed / duration))
        guard progress > 0 && progress < 1 else { return Float(progress) }
        let x1 = easeIn ? 0.42 : 0
        let x2 = easeIn ? 1 : 0.58
        var low = 0.0
        var high = 1.0
        for _ in 0..<16 {
            let t = (low + high) / 2
            let x = 3 * (1 - t) * (1 - t) * t * x1 + 3 * (1 - t) * t * t * x2 + t * t * t
            if x < progress { low = t } else { high = t }
        }
        let t = (low + high) / 2
        return Float(3 * (1 - t) * t * t + t * t * t)
    }

    static func springProgress(elapsed: Double) -> CGFloat {
        guard elapsed > 0 else { return 0 }
        guard elapsed < openingDuration else { return 1 }
        let frequency = sqrt(500.0)
        let damped = frequency * 0.6
        return CGFloat(1 - exp(-0.8 * frequency * elapsed) * (cos(damped * elapsed) + 0.8 / 0.6 * sin(damped * elapsed)))
    }

    static func collapsedCenter(center: CGPoint, anchor: CGPoint) -> CGPoint {
        CGPoint(x: anchor.x + initialScale * (center.x - anchor.x),
            y: anchor.y + initialScale * (center.y - anchor.y))
    }

    static func signedDistance(_ point: CGPoint, to rect: CGRect, radius: CGFloat = QuickClipboardPresentation.cornerRadius) -> CGFloat {
        let r = min(radius, min(rect.width, rect.height) / 2)
        let x = abs(point.x - rect.midX) - rect.width / 2 + r
        let y = abs(point.y - rect.midY) - rect.height / 2 + r
        return hypot(max(x, 0), max(y, 0)) + min(max(x, y), 0) - r
    }
}
