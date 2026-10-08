import Foundation
import CoreGraphics

enum QuickClipboardPresentation {
    static let visibleRows = 5
    static let gridColumns = 3
    static let visibleGridRows = 3
    static let gridGap: CGFloat = 6
    static let filterGap: CGFloat = 12
    static let navigationKeys: [UInt16] = [48, 53, 125, 126, 36, 76]
    static let imageNavigationKeys: [UInt16] = [123, 124]
    static var gridSide: CGFloat { (width - inset * 2 - gridGap * CGFloat(gridColumns - 1)) / CGFloat(gridColumns) }
    static let pageSize = 50
    static let width: CGFloat = 276
    static let rowHeight: CGFloat = 32
    static let imageRowHeight: CGFloat = 64
    static let emptyHeight: CGFloat = 44
    static let filterSize: CGFloat = 24
    static let historySize: CGFloat = 28
    static let cornerRadius: CGFloat = 16
    static let rowCornerRadius: CGFloat = 10
    static let inset: CGFloat = 6
    static let footerGap: CGFloat = 8
    static let safety: CGFloat = 8
    static let canvasMargin: CGFloat = 64
    static let initialScale: CGFloat = 0.50
    static let closingScale: CGFloat = 0.20
    static let openingDuration = 0.15
    static let closingDuration = 0.08
    // Retime the original spring without changing its damping ratio or overshoot.
    static let springStiffness = 500 * pow(0.455 / openingDuration, 2)
    static let springDamping = 1.6 * sqrt(springStiffness)

    static func title(for item: ClipboardItem) -> String {
        if item.kind == .files { return String(item.fileTitle.prefix(160)) }
        guard let text = item.text else { return item.isScreenshot ? "Screenshot" : "Image" }
        let prefix = text.prefix(161)
        let preview = prefix.prefix(160).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return (preview.isEmpty ? "Text" : preview) + (prefix.count > 160 ? "…" : "")
    }

    static func symbol(for item: ClipboardItem) -> String {
        if item.kind == .files { return item.fileSymbol }
        return item.textForm?.systemImage ?? (item.isScreenshot ? "camera.viewfinder" : "photo")
    }

    static func height(for item: ClipboardItem) -> CGFloat {
        item.kind == .image ? imageRowHeight : rowHeight
    }

    static func size(items: [ClipboardItem], filter: QuickClipboardFilter = .all) -> CGSize {
        let contentHeight: CGFloat
        if items.isEmpty { contentHeight = emptyHeight }
        else if filter == .image {
            let rows = min(visibleGridRows, (items.count + gridColumns - 1) / gridColumns)
            contentHeight = CGFloat(rows) * gridSide + CGFloat(rows - 1) * gridGap
        } else { contentHeight = items.prefix(visibleRows).reduce(0) { $0 + height(for: $1) } }
        return CGSize(width: width, height: inset * 2 + contentHeight + footerGap + rowHeight)
    }

    static func rowFrames(items: [ClipboardItem], filter: QuickClipboardFilter = .all) -> [CGRect] {
        if filter == .image {
            let rows = (items.count + gridColumns - 1) / gridColumns
            return items.indices.map { index in
                CGRect(x: CGFloat(index % gridColumns) * (gridSide + gridGap),
                    y: CGFloat(rows - 1 - index / gridColumns) * (gridSide + gridGap),
                    width: gridSide, height: gridSide)
            }
        }
        var top = items.reduce(CGFloat.zero) { $0 + height(for: $1) }
        return items.map { item in
            let height = height(for: item)
            top -= height
            return CGRect(x: 0, y: top, width: width - inset * 2, height: height)
        }
    }

    static func gridSelection(from selection: Int, moving direction: QuickClipboardGridDirection, itemCount: Int) -> Int {
        guard itemCount > 0 else { return 0 }
        let current = min(max(0, selection), itemCount)
        if current == itemCount {
            return direction == .up ? itemCount - 1 : itemCount
        }
        switch direction {
        case .left:
            return current % gridColumns > 0 ? current - 1 : current
        case .right:
            return current % gridColumns < gridColumns - 1 && current + 1 < itemCount ? current + 1 : current
        case .up:
            return current >= gridColumns ? current - gridColumns : current
        case .down:
            let target = current + gridColumns
            if target < itemCount { return target }
            let lastRow = (itemCount - 1) / gridColumns
            return current / gridColumns < lastRow ? itemCount - 1 : itemCount
        }
    }

    static func listFrame(items: [ClipboardItem], filter: QuickClipboardFilter = .all) -> CGRect {
        CGRect(x: inset, y: footerFrame.maxY + footerGap, width: width - inset * 2,
            height: size(items: items, filter: filter).height - inset * 2 - footerGap - rowHeight)
    }

    static var footerFrame: CGRect { CGRect(x: inset, y: inset, width: width - inset * 2, height: rowHeight) }
    static var emptyFrame: CGRect { CGRect(x: inset, y: footerFrame.maxY + footerGap, width: width - inset * 2, height: emptyHeight) }
    static var historyFrame: CGRect {
        CGRect(x: width - inset - historySize, y: footerFrame.midY - historySize / 2, width: historySize, height: historySize)
    }
    static var filterFrames: [CGRect] {
        let groupWidth = CGFloat(QuickClipboardFilter.allCases.count) * filterSize
            + CGFloat(QuickClipboardFilter.allCases.count - 1) * filterGap
        return QuickClipboardFilter.allCases.indices.map { index in
            CGRect(x: (width - groupWidth) / 2 + CGFloat(index) * (filterSize + filterGap),
                y: footerFrame.midY - filterSize / 2, width: filterSize, height: filterSize)
        }
    }

    static func frame(anchor: CGRect, screen: CGRect, items: [ClipboardItem], filter: QuickClipboardFilter = .all) -> CGRect {
        let safe = screen.insetBy(dx: safety, dy: safety)
        let size = size(items: items, filter: filter)
        let preferredX = anchor.height > 0 ? anchor.minX : anchor.maxX + 12
        let x = preferredX + size.width <= safe.maxX ? preferredX : anchor.maxX - (anchor.height > 0 ? 0 : 12) - size.width
        let below = anchor.minY - 12 - size.height
        let y = below >= safe.minY ? below : anchor.maxY + 12
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
        let frequency = sqrt(springStiffness)
        let damped = frequency * 0.6
        return CGFloat(1 - exp(-0.8 * frequency * elapsed) * (cos(damped * elapsed) + 0.8 / 0.6 * sin(damped * elapsed)))
    }

    static func collapsedCenter(center: CGPoint, anchor: CGPoint, scale: CGFloat = initialScale) -> CGPoint {
        CGPoint(x: anchor.x + scale * (center.x - anchor.x),
            y: anchor.y + scale * (center.y - anchor.y))
    }

    static func signedDistance(_ point: CGPoint, to rect: CGRect, radius: CGFloat = QuickClipboardPresentation.cornerRadius) -> CGFloat {
        let r = min(radius, min(rect.width, rect.height) / 2)
        let x = abs(point.x - rect.midX) - rect.width / 2 + r
        let y = abs(point.y - rect.midY) - rect.height / 2 + r
        return hypot(max(x, 0), max(y, 0)) + min(max(x, y), 0) - r
    }
}

enum QuickClipboardGridDirection: Equatable, Sendable {
    case left, right, up, down
}

enum QuickClipboardFilter: CaseIterable, Sendable {
    case all, text, image, files

    var kind: ClipboardItem.Kind? {
        switch self {
        case .all: nil
        case .text: .text
        case .image: .image
        case .files: .files
        }
    }

    var title: String {
        switch self {
        case .all: "All"
        case .text: "Text"
        case .image: "Images"
        case .files: "Files"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "square.stack"
        case .text: "textformat.alt"
        case .image: "photo"
        case .files: "doc"
        }
    }

    var emptyMessage: String { self == .all ? "Clipboard history is empty" : "No \(title.lowercased()) in clipboard history" }

    func moved(by offset: Int) -> Self {
        let cases = Self.allCases
        let index = cases.firstIndex(of: self)!
        return cases[((index + offset) % cases.count + cases.count) % cases.count]
    }
}
