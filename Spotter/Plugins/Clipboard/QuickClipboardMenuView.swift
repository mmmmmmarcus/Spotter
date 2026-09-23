import AppKit
import QuartzCore

@MainActor
final class QuickClipboardMenuView: NSView {
    let glassContainer = NSGlassEffectContainerView()
    private let glassContent = NSView()
    private let rowsView = NSView()
    private let groupShadow = CALayer()
    private let shadowMask = CAShapeLayer()
    private var rowWidths: [CGFloat]
    private var thumbnailPreparation: Task<Void, Never>?
    private var requestedImagePaths: [String] = []
    private var displayedItems: [ClipboardItem] = []
    private var selectedIndex = 0
    private var rowButtons: [QuickClipboardButton] = []
    private var rowGlass: [NSGlassEffectView] = []
    var onSelect: ((Int) -> Void)?
    var onHighlight: ((Int) -> Void)?
    init(items: [ClipboardItem]) {
        self.rowWidths = Self.widths(for: items)
        let size = QuickClipboardPresentation.size(count: items.count)
        let margin = QuickClipboardPresentation.canvasMargin
        super.init(frame: CGRect(origin: .zero, size: CGSize(width: size.width + margin * 2, height: size.height + margin * 2)))
        wantsLayer = true
        glassContainer.frame = CGRect(origin: CGPoint(x: margin, y: margin), size: size)
        glassContent.frame = CGRect(origin: .zero, size: size)
        glassContainer.spacing = 0
        glassContainer.contentView = glassContent
        glassContainer.wantsLayer = true
        glassContainer.clipsToBounds = false
        let rowCount = items.count + 1
        rowsView.frame = glassContent.bounds
        rowsView.wantsLayer = true
        rowsView.clipsToBounds = false
        glassContent.addSubview(rowsView)
        addSubview(glassContainer)
        groupShadow.shadowOpacity = 0.18
        groupShadow.shadowRadius = 24
        groupShadow.shadowOffset = CGSize(width: 0, height: -4)
        groupShadow.zPosition = 100
        groupShadow.mask = shadowMask
        shadowMask.fillRule = .evenOdd
        shadowMask.fillColor = NSColor.labelColor.withAlphaComponent(1).cgColor
        layer?.addSublayer(groupShadow)
        updateShadowAppearance()
        let frames = QuickClipboardPresentation.rowFrames(widths: rowWidths)
        for index in 0..<rowCount {
            let rect = frames[index]
            let glass = NSGlassEffectView(frame: rect)
            glass.style = .clear
            glass.cornerRadius = rect.height / 2
            let button = QuickClipboardButton(frame: glass.bounds)
            button.content.frame = button.bounds.insetBy(dx: 11, dy: 0)
            if items.indices.contains(index) {
                Self.configure(button, for: items[index])
                button.actionHandler = { [weak self] in
                    guard let self else { return }
                    onSelect?(index)
                }
                button.hoverHandler = { [weak self] in
                    guard let self else { return }
                    onHighlight?(index)
                }
            } else {
                button.borderShape = .circle
                button.content.imagePosition = .imageOnly
                button.content.image = Self.symbol("ellipsis")
                button.setAccessibilityLabel("Open Clipboard History")
                button.toolTip = "Open Clipboard History"
                button.actionHandler = { [weak self] in self?.onSelect?(index) }
                button.hoverHandler = { [weak self] in self?.onHighlight?(index) }
            }
            rowButtons.append(button)
            glass.contentView = button
            rowGlass.append(glass)
            rowsView.addSubview(glass)
        }
        renderRows()
        update(items, selection: 0)
    }

    required init?(coder: NSCoder) { nil }

    isolated deinit {
        thumbnailPreparation?.cancel()
    }

    func update(_ items: [ClipboardItem], selection: Int) {
        guard items.count + 1 == rowButtons.count else { return }
        displayedItems = items
        for (index, item) in items.enumerated() {
            Self.configure(rowButtons[index], for: item)
        }
        let paths = items.compactMap(\.imagePath)
        if paths != requestedImagePaths {
            requestedImagePaths = paths
            thumbnailPreparation?.cancel()
            thumbnailPreparation = Task { [weak self] in
                await Self.prepareThumbnails(for: items)
                guard !Task.isCancelled, let self, requestedImagePaths == paths else { return }
                update(displayedItems, selection: selectedIndex)
            }
        }
        let widths = Self.widths(for: items)
        if widths != rowWidths {
            rowWidths = widths
            renderRows()
        }
        select(selection)
    }

    func select(_ index: Int) {
        selectedIndex = index
        for offset in rowButtons.indices {
            let button = rowButtons[offset]
            button.content.isSelected = offset == index
            button.setAccessibilityValue(offset == index ? "Selected" : "")
        }
    }

    private func renderRows() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let size = CGSize(width: QuickClipboardPresentation.totalWidth(rowWidths), height: QuickClipboardPresentation.rowHeight)
        glassContainer.setFrameSize(size)
        glassContent.setFrameSize(size)
        rowsView.setFrameSize(size)
        let frames = QuickClipboardPresentation.rowFrames(widths: rowWidths)
        for (index, button) in rowButtons.enumerated() {
            let glass = rowGlass[index]
            glass.frame = frames[index]
            button.frame = glass.bounds
            button.content.frame = index == rowButtons.count - 1 ? button.bounds : button.bounds.insetBy(dx: 11, dy: 0)
        }
        glassContainer.layoutSubtreeIfNeeded()
        updateShadowGeometry()
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateShadowAppearance()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updateShadowGeometry()
        CATransaction.commit()
    }

    private func updateShadowAppearance() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            groupShadow.shadowColor = NSColor.shadowColor.cgColor
        }
        CATransaction.commit()
    }

    private func updateShadowGeometry() {
        groupShadow.frame = bounds
        shadowMask.frame = bounds
        shadowMask.contentsScale = window?.backingScaleFactor ?? 2
        let region = glassContainer.frame
        groupShadow.shadowPath = CGPath(roundedRect: region, cornerWidth: region.height / 2,
            cornerHeight: region.height / 2, transform: nil)
        let cutout = CGMutablePath()
        cutout.addRect(bounds)
        // A single area shadow sits above glass; holes keep its backdrop sampling unpolluted.
        for button in rowButtons where !button.isHidden && button.frame.width > 0 {
            let rect = button.convert(button.bounds, to: self)
            let radius = min(rect.width, rect.height) / 2
            cutout.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)
        }
        shadowMask.path = cutout
    }

    func refreshGlyphs() {
        for button in rowButtons { button.content.needsDisplay = true }
    }

    func containsGlass(_ point: CGPoint) -> Bool {
        let margin = QuickClipboardPresentation.canvasMargin
        let local = CGPoint(x: point.x - margin, y: point.y - margin)
        return rowsView.bounds.contains(local) && rowGlass.contains {
            !$0.isHidden && QuickClipboardPresentation.signedDistance(local, to: $0.frame) <= 0
        }
    }

    static func widths(for items: [ClipboardItem]) -> [CGFloat] {
        let button = QuickClipboardButton(frame: .zero)
        return items.prefix(QuickClipboardPresentation.limit).map { item in
            configure(button, for: item)
            let width = item.kind == .image ? (button.content.image?.size.width ?? 14) : button.content.intrinsicContentSize.width
            return min(QuickClipboardPresentation.width, max(QuickClipboardPresentation.rowHeight, ceil(width + 22)))
        } + [QuickClipboardPresentation.rowHeight]
    }

    static func prepareThumbnails(for items: [ClipboardItem]) async {
        for path in Set(items.compactMap(\.imagePath)) {
            guard !Task.isCancelled else { return }
            _ = await ImageThumbnail.loadAsync(URL(fileURLWithPath: path), maxPixel: 128)
        }
    }

    private static func configure(_ button: QuickClipboardButton, for item: ClipboardItem) {
        button.setAccessibilityLabel("Paste \(QuickClipboardPresentation.title(for: item))")
        let content = button.content
        if item.kind == .image {
            content.title = ""
            content.imagePosition = .imageOnly
            if let path = item.imagePath,
               let cached = ImageThumbnail.cached(URL(fileURLWithPath: path), maxPixel: 128),
               let preview = cached.copy() as? NSImage {
                let ratio = min((QuickClipboardPresentation.width - 22) / max(1, preview.size.width), (QuickClipboardPresentation.rowHeight - 16) / max(1, preview.size.height))
                preview.size = CGSize(width: preview.size.width * ratio, height: preview.size.height * ratio)
                content.image = preview
            } else {
                content.image = symbol("photo")
            }
        } else {
            content.title = QuickClipboardPresentation.title(for: item)
            content.imagePosition = .imageLeading
            content.image = symbol(QuickClipboardPresentation.symbol(for: item))
        }
    }

    private static func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
    }
}

@MainActor
final class QuickClipboardButton: NSButton {
    let content = QuickClipboardContentView(frame: .zero)
    var actionHandler: (() -> Void)?
    var hoverHandler: (() -> Void)?
    private var hoverTracking: NSTrackingArea?
    override var acceptsFirstResponder: Bool { false }
    override var needsPanelToBecomeKey: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        title = ""
        borderShape = .capsule
        controlSize = .large
        isBordered = false
        focusRingType = .none
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(performAction)
        addSubview(content)
        content.setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let tracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(tracking)
        hoverTracking = tracking
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        hoverHandler?()
    }
    @objc private func performAction() { actionHandler?() }
}

@MainActor
final class QuickClipboardContentView: NSView {
    var title = "" { didSet { needsDisplay = true } }
    var image: NSImage? { didSet { needsDisplay = true } }
    var imagePosition: NSControl.ImagePosition = .imageLeading
    var font = NSFont.systemFont(ofSize: 12)
    var isSelected = false { didSet { needsDisplay = true } }
    var textColor: NSColor { .labelColor.withAlphaComponent(isSelected ? 1 : 0.35) }
    var symbolColor: NSColor { .labelColor.withAlphaComponent(isSelected ? 1 : 0.5) }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override var intrinsicContentSize: NSSize {
        guard imagePosition != .imageOnly else { return image?.size ?? CGSize(width: 14, height: 14) }
        let width = (title as NSString).size(withAttributes: [.font: font]).width
        return CGSize(width: 16 + 6 + ceil(width), height: QuickClipboardPresentation.rowHeight)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        if let superview {
            let clip = convert(superview.bounds, from: superview)
            let radius = min(clip.width, clip.height) / 2
            NSBezierPath(roundedRect: clip, xRadius: radius, yRadius: radius).addClip()
        }
        effectiveAppearance.performAsCurrentDrawingAppearance { drawContents() }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func pixelAligned(_ rect: CGRect) -> CGRect {
        let origin = convertToBacking(rect.origin)
        return CGRect(origin: convertFromBacking(CGPoint(x: origin.x.rounded(), y: origin.y.rounded())), size: rect.size)
    }

    private func drawContents() {
        guard imagePosition == .imageOnly, let image, !image.isTemplate else {
            if let image {
                let size = image.size
                let origin = CGPoint(x: imagePosition == .imageOnly ? bounds.midX - size.width / 2 : 8 - size.width / 2,
                    y: bounds.midY - size.height / 2)
                let rect = pixelAligned(CGRect(origin: origin, size: size))
                let colored = image.withSymbolConfiguration(.init(paletteColors: [symbolColor])) ?? image
                colored.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
            if !title.isEmpty {
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineBreakMode = .byTruncatingTail
                let font = self.font
                let height = ceil(font.ascender - font.descender)
                let rect = pixelAligned(CGRect(x: 22, y: bounds.midY - height / 2,
                    width: max(0, bounds.width - 22), height: height))
                (title as NSString).draw(in: rect, withAttributes: [.font: font,
                    .foregroundColor: textColor, .paragraphStyle: paragraph])
            }
            return
        }
        let available = bounds.insetBy(dx: 0, dy: 8)
        let ratio = min(available.width / max(1, image.size.width), available.height / max(1, image.size.height))
        let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        let rect = CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).addClip()
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: isSelected ? 1 : 0.5, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
    }

}

final class QuickClipboardPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
