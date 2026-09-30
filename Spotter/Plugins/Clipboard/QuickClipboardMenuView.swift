import AppKit
import QuartzCore

@MainActor
final class QuickClipboardMenuView: NSView {
    let glassView = NSGlassEffectView()
    private let rowsView = NSView()
    let scrollView = NSScrollView()
    private let documentView = NSView()
    private var frames: [CGRect] = []
    private var visibleButtons: [Int: QuickClipboardButton] = [:]
    private var selection = 0
    private var filter: QuickClipboardFilter = .text
    private var updating = false
    private var pagingTask: Task<Void, Never>?
    private let groupShadow = CALayer()
    private let shadowMask = CAShapeLayer()
    private var thumbnailPreparation: Task<Void, Never>?
    private var requestedImagePaths: [String] = []
    private var displayedItems: [ClipboardItem] = []
    var rowButtons: [QuickClipboardButton] { visibleButtons.keys.sorted().compactMap { visibleButtons[$0] } }
    private(set) var filterButtons: [QuickClipboardButton] = []
    let historyButton = QuickClipboardButton(frame: QuickClipboardPresentation.historyFrame)
    private let emptyLabel = NSTextField(wrappingLabelWithString: "")
    var onSelect: ((Int) -> Void)?
    var onHighlight: ((Int) -> Void)?
    var onFilter: ((QuickClipboardFilter) -> Void)?
    var onLoadMore: (() -> Void)?
    init(items: [ClipboardItem]) {
        let size = QuickClipboardPresentation.size(items: items)
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
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .none
        scrollView.contentView.drawsBackground = false
        scrollView.documentView = documentView
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled),
            name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        rowsView.addSubview(scrollView)
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
        for (option, rect) in zip(QuickClipboardFilter.allCases, QuickClipboardPresentation.filterFrames) {
            let button = Self.iconButton(symbol: option.systemImage, title: option.title, frame: rect)
            button.actionHandler = { [weak self] in self?.onFilter?(option) }
            filterButtons.append(button)
            rowsView.addSubview(button)
        }
        historyButton.content.frame = historyButton.bounds
        historyButton.content.image = Self.symbol("arrow.up.right.square")
        historyButton.content.centersSymbol = true
        historyButton.toolTip = "Open Clipboard History"
        historyButton.setAccessibilityLabel("Open Clipboard History")
        historyButton.actionHandler = { [weak self] in
            guard let self else { return }
            onSelect?(displayedItems.count)
        }
        historyButton.hoverHandler = { [weak self] in
            guard let self else { return }
            onHighlight?(displayedItems.count)
        }
        rowsView.addSubview(historyButton)
        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.maximumNumberOfLines = 2
        rowsView.addSubview(emptyLabel)
        update(items, selection: 0)
    }

    required init?(coder: NSCoder) { nil }

    isolated deinit {
        thumbnailPreparation?.cancel()
        pagingTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    func update(_ items: [ClipboardItem], selection: Int, filter: QuickClipboardFilter = .text) {
        updating = true
        let topOffset = self.filter == filter ? documentView.bounds.height - scrollView.contentView.bounds.maxY : 0
        self.filter = filter
        self.selection = selection
        displayedItems = items
        frames = QuickClipboardPresentation.rowFrames(items: items)
        let size = QuickClipboardPresentation.size(items: items)
        let margin = QuickClipboardPresentation.canvasMargin
        if glassView.frame.size != size {
            setFrameSize(CGSize(width: size.width + margin * 2, height: size.height + margin * 2))
            bounds = CGRect(origin: .zero, size: frame.size)
            glassView.frame = CGRect(origin: CGPoint(x: margin, y: margin), size: size)
            rowsView.frame = CGRect(origin: .zero, size: size)
        }
        scrollView.frame = QuickClipboardPresentation.listFrame(items: items)
        documentView.frame = CGRect(x: 0, y: 0, width: scrollView.bounds.width,
            height: max(scrollView.contentSize.height, frames.first?.maxY ?? 0))
        let offset = max(0, documentView.bounds.height - scrollView.contentView.bounds.height - max(0, topOffset))
        scrollView.contentView.scroll(to: CGPoint(x: 0, y: offset))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        for (index, option) in QuickClipboardFilter.allCases.enumerated() {
            filterButtons[index].isSelected = option == filter
            filterButtons[index].setAccessibilityValue(option == filter ? "Selected" : "")
        }
        emptyLabel.isHidden = !items.isEmpty
        scrollView.isHidden = items.isEmpty
        emptyLabel.stringValue = filter.emptyMessage
        emptyLabel.frame = QuickClipboardPresentation.emptyFrame.insetBy(dx: 4, dy: 10)
        glassView.layoutSubtreeIfNeeded()
        updateShadowGeometry()
        updating = false
        refreshVisibleRows()
        select(selection, reveal: false)
    }

    @objc private func scrolled() {
        guard !updating else { return }
        refreshVisibleRows()
    }

    private func refreshVisibleRows() {
        let visible = scrollView.contentView.bounds
        let indices = frames.indices.filter { frames[$0].intersects(visible) }
        let wanted = Set(indices)
        for index in Array(visibleButtons.keys) where !wanted.contains(index) {
            visibleButtons.removeValue(forKey: index)?.removeFromSuperview()
        }
        for index in indices {
            let button = visibleButtons[index] ?? QuickClipboardButton(frame: .zero)
            if button.superview == nil { documentView.addSubview(button) }
            visibleButtons[index] = button
            button.actionHandler = { [weak self] in self?.onSelect?(index) }
            button.hoverHandler = { [weak self] in self?.onHighlight?(index) }
            button.frame = frames[index]
            button.content.frame = button.bounds.insetBy(dx: 11, dy: 0)
            Self.configure(button, for: displayedItems[index])
            button.isSelected = index == selection
            button.setAccessibilityValue(button.isSelected ? "Selected" : "")
        }
        let visibleItems = indices.map { displayedItems[$0] }
        let paths = visibleItems.compactMap(\.imagePath)
        if paths != requestedImagePaths {
            requestedImagePaths = paths
            thumbnailPreparation?.cancel()
            thumbnailPreparation = Task { [weak self] in
                await Self.prepareThumbnails(for: visibleItems)
                guard !Task.isCancelled, let self, requestedImagePaths == paths else { return }
                for (index, button) in visibleButtons { Self.configure(button, for: displayedItems[index]) }
            }
        }
        if !displayedItems.isEmpty, visible.minY <= QuickClipboardPresentation.imageRowHeight, pagingTask == nil {
            let count = displayedItems.count
            pagingTask = Task { [weak self] in
                await Task.yield()
                guard !Task.isCancelled, let self else { return }
                pagingTask = nil
                if displayedItems.count == count { onLoadMore?() }
            }
        }
    }

    func select(_ index: Int, reveal: Bool = true) {
        selection = index
        if reveal, frames.indices.contains(index) {
            documentView.scrollToVisible(frames[index])
            refreshVisibleRows()
        }
        for (offset, button) in visibleButtons {
            button.isSelected = offset == index
            button.setAccessibilityValue(offset == index ? "Selected" : "")
        }
        historyButton.isSelected = index == displayedItems.count
        historyButton.setAccessibilityValue(historyButton.isSelected ? "Selected" : "")
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
        for button in filterButtons { button.content.needsDisplay = true }
        historyButton.content.needsDisplay = true
    }

    func containsGlass(_ point: CGPoint) -> Bool {
        QuickClipboardPresentation.signedDistance(point, to: glassView.frame) <= 0
    }

    static func prepareThumbnails(for items: [ClipboardItem]) async {
        for path in Set(items.compactMap(\.imagePath)) {
            guard !Task.isCancelled else { return }
            _ = await ImageThumbnail.loadAsync(URL(fileURLWithPath: path), maxPixel: 512)
        }
    }

    private static func configure(_ button: QuickClipboardButton, for item: ClipboardItem) {
        button.setAccessibilityLabel("Paste \(QuickClipboardPresentation.title(for: item))")
        let content = button.content
        if item.kind == .image {
            content.title = ""
            content.imagePosition = .imageOnly
            if let path = item.imagePath,
               let cached = ImageThumbnail.cached(URL(fileURLWithPath: path), maxPixel: 512),
               let preview = cached.copy() as? NSImage {
                let ratio = min(content.bounds.width / max(1, preview.size.width), (QuickClipboardPresentation.imageRowHeight - 16) / max(1, preview.size.height))
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

    private static func iconButton(symbol name: String, title: String, frame: CGRect) -> QuickClipboardButton {
        let button = QuickClipboardButton(frame: frame)
        button.content.frame = button.bounds
        button.content.image = symbol(name)
        button.content.centersSymbol = true
        button.toolTip = title
        button.setAccessibilityLabel(title)
        return button
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
    var centersSymbol = false
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
                let origin = CGPoint(x: (centersSymbol ? bounds.midX : 8) - size.width / 2,
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
