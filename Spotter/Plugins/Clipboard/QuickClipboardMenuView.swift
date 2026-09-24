import AppKit
import QuartzCore

@MainActor
final class QuickClipboardMenuView: NSView {
    let glassView = NSGlassEffectView()
    private let rowsView = NSView()
    private let groupShadow = CALayer()
    private let shadowMask = CAShapeLayer()
    private var thumbnailPreparation: Task<Void, Never>?
    private var requestedImagePaths: [String] = []
    private var displayedItems: [ClipboardItem] = []
    private var selectedIndex = 0
    private var rowButtons: [QuickClipboardButton] = []
    var onSelect: ((Int) -> Void)?
    var onHighlight: ((Int) -> Void)?
    init(items: [ClipboardItem]) {
        let size = QuickClipboardPresentation.size(count: items.count)
        let margin = QuickClipboardPresentation.canvasMargin
        super.init(frame: CGRect(origin: .zero, size: CGSize(width: size.width + margin * 2, height: size.height + margin * 2)))
        wantsLayer = true
        glassView.frame = CGRect(origin: CGPoint(x: margin, y: margin), size: size)
        glassView.style = .clear
        glassView.cornerRadius = QuickClipboardPresentation.cornerRadius
        glassView.wantsLayer = true
        glassView.clipsToBounds = false
        rowsView.frame = CGRect(origin: .zero, size: size)
        rowsView.wantsLayer = true
        glassView.contentView = rowsView
        addSubview(glassView)
        groupShadow.shadowOpacity = 0.18
        groupShadow.shadowRadius = 24
        groupShadow.shadowOffset = CGSize(width: 0, height: -4)
        groupShadow.zPosition = 100
        groupShadow.mask = shadowMask
        shadowMask.fillRule = .evenOdd
        shadowMask.fillColor = NSColor.labelColor.withAlphaComponent(1).cgColor
        layer?.addSublayer(groupShadow)
        updateShadowAppearance()
        let frames = QuickClipboardPresentation.rowFrames(count: items.count)
        for (index, rect) in frames.enumerated() {
            let button = QuickClipboardButton(frame: rect)
            button.content.frame = button.bounds.insetBy(dx: 11, dy: 0)
            if items.indices.contains(index) {
                Self.configure(button, for: items[index])
            } else {
                button.content.title = "Open Clipboard History"
                button.content.image = Self.symbol("clock.arrow.circlepath")
                button.setAccessibilityLabel("Open Clipboard History")
            }
            button.actionHandler = { [weak self] in self?.onSelect?(index) }
            button.hoverHandler = { [weak self] in self?.onHighlight?(index) }
            rowButtons.append(button)
            rowsView.addSubview(button)
        }
        glassView.layoutSubtreeIfNeeded()
        updateShadowGeometry()
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
        select(selection)
    }

    func select(_ index: Int) {
        selectedIndex = index
        for offset in rowButtons.indices {
            let button = rowButtons[offset]
            button.isSelected = offset == index
            button.setAccessibilityValue(offset == index ? "Selected" : "")
        }
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
        let region = glassView.frame
        let radius = QuickClipboardPresentation.cornerRadius
        groupShadow.shadowPath = CGPath(roundedRect: region, cornerWidth: radius, cornerHeight: radius, transform: nil)
        let cutout = CGMutablePath()
        cutout.addRect(bounds)
        // Exclude the entire menu so the shadow never darkens the glass backdrop.
        cutout.addRoundedRect(in: region, cornerWidth: radius, cornerHeight: radius)
        shadowMask.path = cutout
    }

    func refreshGlyphs() {
        for button in rowButtons { button.content.needsDisplay = true }
    }

    func containsGlass(_ point: CGPoint) -> Bool {
        QuickClipboardPresentation.signedDistance(point, to: glassView.frame) <= 0
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
    var isSelected = false {
        didSet {
            content.isSelected = isSelected
            needsDisplay = true
        }
    }
    override var acceptsFirstResponder: Bool { false }
    override var needsPanelToBecomeKey: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        title = ""
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

    override func draw(_ dirtyRect: NSRect) {
        guard isSelected || isHighlighted else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            NSColor.labelColor.withAlphaComponent(0.1).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: QuickClipboardPresentation.rowCornerRadius,
                yRadius: QuickClipboardPresentation.rowCornerRadius).fill()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

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
        NSBezierPath(rect: bounds).addClip()
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
                let origin = CGPoint(x: 8 - size.width / 2,
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
        let rect = CGRect(x: 0, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
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
