import AppKit
import QuartzCore

@MainActor
final class QuickClipboardMenuView: NSView {
    let glassContainer = NSGlassEffectContainerView()
    private let glassContent = NSView()
    private let rowsView = NSView()
    private var rowWidths: [CGFloat]
    private var thumbnailPreparation: Task<Void, Never>?
    private var requestedImagePaths: [String] = []
    private var displayedItems: [ClipboardItem] = []
    private var selectedIndex = 0
    private var rowButtons: [QuickClipboardButton] = []
    private var rowGlass: [NSGlassEffectView] = []
    var onSelect: ((Int) -> Void)?
    var onHighlight: ((Int) -> Void)?
    private var scrollTask: Task<Void, Never>?
    private var scrollDisplayLink: CADisplayLink?
    private let now: () -> CFTimeInterval
    private var scrollStartedAt: CFTimeInterval = 0
    private var scrollSource: CGFloat = 0
    private var scrollTarget: CGFloat = 0
    private var scrollOffset: CGFloat = 0
    private var sourceViewportWidth: CGFloat = 0
    private var targetViewportWidth: CGFloat = 0
    private(set) var firstVisibleIndex = 0
    private(set) var isScrolling = false

    init(items: [ClipboardItem], now: @escaping () -> CFTimeInterval = CACurrentMediaTime) {
        self.now = now
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
        let rowCount = max(1, items.count)
        rowsView.frame = glassContent.bounds
        rowsView.wantsLayer = true
        rowsView.clipsToBounds = false
        glassContent.addSubview(rowsView)
        addSubview(glassContainer)
        let frames = QuickClipboardPresentation.rowFrames(widths: rowWidths)
        for index in 0..<rowCount {
            let rect = frames[index]
            let content = NSView(frame: CGRect(origin: .zero, size: rect.size))
            content.clipsToBounds = true
            let button = Self.makeButton()
            button.frame = content.bounds.insetBy(dx: 11, dy: 0)
            if items.indices.contains(index) {
                Self.configure(button, for: items[index])
                button.actionHandler = { [weak self] in
                    guard let self, !isScrolling else { return }
                    onSelect?(index)
                }
                button.hoverHandler = { [weak self] in
                    guard let self, !isScrolling else { return }
                    onHighlight?(index)
                }
            } else {
                button.title = "Clipboard history is empty"
                button.image = Self.symbol("doc.on.clipboard")
                button.isEnabled = false
            }
            content.addSubview(button)
            rowButtons.append(button)
            rowGlass.append(addGlass(rect: rect, content: content))
        }
        renderRows(offset: 0, viewportWidth: QuickClipboardPresentation.visibleWidth(first: 0, widths: rowWidths))
        update(items, selection: 0)
    }

    required init?(coder: NSCoder) { nil }

    isolated deinit {
        scrollTask?.cancel()
        thumbnailPreparation?.cancel()
        scrollDisplayLink?.invalidate()
    }

    func update(_ items: [ClipboardItem], selection: Int) {
        guard items.count == rowButtons.count else { return }
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
            for (index, glass) in rowGlass.enumerated() {
                glass.setFrameSize(CGSize(width: widths[index], height: QuickClipboardPresentation.rowHeight))
                glass.contentView?.frame = glass.bounds
                rowButtons[index].frame = glass.bounds.insetBy(dx: 11, dy: 0)
            }
            scrollTask?.cancel()
            scrollDisplayLink?.invalidate()
            scrollDisplayLink = nil
            isScrolling = false
            renderRows(offset: QuickClipboardPresentation.scrollOffset(first: firstVisibleIndex, widths: widths),
                viewportWidth: QuickClipboardPresentation.visibleWidth(first: firstVisibleIndex, widths: widths))
        }
        select(selection)
    }

    func select(_ index: Int, animated: Bool = false) {
        selectedIndex = index
        for offset in rowButtons.indices {
            let button = rowButtons[offset]
            button.isSelected = offset == index
            button.setAccessibilityValue(offset == index ? "Selected" : "")
        }
        scroll(to: index, animated: animated)
    }

    private func scroll(to selection: Int, animated: Bool) {
        let next = QuickClipboardPresentation.firstVisibleIndex(
            selection: selection, current: firstVisibleIndex, count: rowButtons.count)
        guard next != firstVisibleIndex else {
            if !isScrolling { hideOffscreenRows() }
            return
        }
        firstVisibleIndex = next
        scrollTask?.cancel()
        scrollSource = scrollOffset
        scrollTarget = QuickClipboardPresentation.scrollOffset(first: next, widths: rowWidths)
        sourceViewportWidth = rowsView.frame.width
        targetViewportWidth = QuickClipboardPresentation.visibleWidth(first: next, widths: rowWidths)
        scrollStartedAt = now()
        let shouldAnimate = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        isScrolling = shouldAnimate
        guard shouldAnimate else {
            scrollDisplayLink?.invalidate()
            scrollDisplayLink = nil
            renderRows(offset: scrollTarget, viewportWidth: targetViewportWidth)
            hideOffscreenRows()
            return
        }
        if scrollDisplayLink == nil {
            let link = displayLink(target: self, selector: #selector(advanceScroll))
            scrollDisplayLink = link
            link.add(to: .main, forMode: .common)
        }
        scrollTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(QuickClipboardPresentation.scrollDuration)) }
            catch { return }
            self?.finishScroll()
        }
    }

    @objc func advanceScroll() {
        guard isScrolling else { return }
        let progress = QuickClipboardPresentation.scrollProgress(elapsed: now() - scrollStartedAt)
        if progress >= 1 || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            finishScroll()
        } else {
            renderRows(offset: scrollSource + (scrollTarget - scrollSource) * progress,
                viewportWidth: sourceViewportWidth + (targetViewportWidth - sourceViewportWidth) * progress)
        }
    }

    private func renderRows(offset: CGFloat, viewportWidth: CGFloat) {
        scrollOffset = offset
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Native glass is batched separately from text; move each effect view's real frame, not an ancestor layer.
        let size = CGSize(width: viewportWidth, height: QuickClipboardPresentation.rowHeight)
        glassContainer.setFrameSize(size)
        glassContent.setFrameSize(size)
        rowsView.setFrameSize(size)
        let frames = QuickClipboardPresentation.rowFrames(widths: rowWidths)
        for (index, glass) in rowGlass.enumerated() {
            let full = frames[index].offsetBy(dx: -offset, dy: 0)
            let visible = full.intersection(CGRect(origin: .zero, size: size))
            // Grow the native glass outline at the edge; keep glyphs at their original size.
            let rect = visible.isNull ? full : visible
            glass.frame = rect
            glass.cornerRadius = min(QuickClipboardPresentation.cornerRadius, rect.width / 2)
            glass.contentView?.frame = glass.bounds
            rowButtons[index].frame = CGRect(x: full.minX - rect.minX + 11, y: 0,
                width: full.width - 22, height: full.height)
            rowButtons[index].revealOpacity = visible.isNull ? 0 : min(1, visible.width / min(24, full.width))
            glass.isHidden = visible.isNull
        }
        glassContainer.layoutSubtreeIfNeeded()
        CATransaction.commit()
    }

    private func finishScroll() {
        guard isScrolling else { return }
        scrollTask?.cancel()
        scrollTask = nil
        scrollDisplayLink?.invalidate()
        scrollDisplayLink = nil
        renderRows(offset: scrollTarget, viewportWidth: targetViewportWidth)
        isScrolling = false
        hideOffscreenRows()
    }

    private func hideOffscreenRows() {
        for (index, glass) in rowGlass.enumerated() {
            glass.isHidden = index < firstVisibleIndex || index >= firstVisibleIndex + QuickClipboardPresentation.visibleLimit
        }
    }

    func refreshGlyphs() {
        for button in rowButtons { button.needsDisplay = true }
    }

    func containsGlass(_ point: CGPoint) -> Bool {
        let margin = QuickClipboardPresentation.canvasMargin
        let local = CGPoint(x: point.x - margin, y: point.y - margin)
        return rowsView.bounds.contains(local) && rowGlass.contains {
            !$0.isHidden && QuickClipboardPresentation.signedDistance(local, to: $0.frame) <= 0
        }
    }

    private func addGlass(rect: CGRect, content: NSView) -> NSGlassEffectView {
        let glass = NSGlassEffectView(frame: rect)
        glass.style = .regular
        glass.cornerRadius = QuickClipboardPresentation.cornerRadius
        #if compiler(>=6.4)
        if #available(macOS 27.0, *) { glass.effectIsInteractive = true }
        #endif
        glass.contentView = content
        rowsView.addSubview(glass)
        return glass
    }

    static func widths(for items: [ClipboardItem]) -> [CGFloat] {
        let button = makeButton()
        return (0..<max(1, items.count)).map { index in
            if items.indices.contains(index) {
                configure(button, for: items[index])
                if items[index].kind == .image {
                    return min(QuickClipboardPresentation.width, max(QuickClipboardPresentation.rowHeight, ceil((button.image?.size.width ?? 14) + 22)))
                }
            } else {
                button.title = "Clipboard history is empty"
                button.image = symbol("doc.on.clipboard")
            }
            return min(QuickClipboardPresentation.width, max(QuickClipboardPresentation.rowHeight, ceil(button.intrinsicContentSize.width + 22)))
        }
    }

    static func prepareThumbnails(for items: [ClipboardItem]) async {
        for path in Set(items.compactMap(\.imagePath)) {
            guard !Task.isCancelled else { return }
            _ = await ImageThumbnail.loadAsync(URL(fileURLWithPath: path), maxPixel: 128)
        }
    }

    private static func configure(_ button: QuickClipboardButton, for item: ClipboardItem) {
        button.setAccessibilityLabel("Paste \(QuickClipboardPresentation.title(for: item))")
        button.imageScaling = .scaleNone
        if item.kind == .image {
            button.title = ""
            button.imagePosition = .imageOnly
            button.contentTintColor = nil
            if let path = item.imagePath,
               let cached = ImageThumbnail.cached(URL(fileURLWithPath: path), maxPixel: 128),
               let preview = cached.copy() as? NSImage {
                let ratio = min((QuickClipboardPresentation.width - 22) / max(1, preview.size.width), 24 / max(1, preview.size.height))
                preview.size = CGSize(width: preview.size.width * ratio, height: preview.size.height * ratio)
                button.image = preview
            } else {
                button.image = symbol("photo")
            }
        } else {
            button.title = QuickClipboardPresentation.title(for: item)
            button.imagePosition = .imageLeading
            button.contentTintColor = .labelColor
            button.image = symbol(QuickClipboardPresentation.symbol(for: item))
        }
    }

    private static func makeButton() -> QuickClipboardButton {
        let button = QuickClipboardButton(frame: .zero)
        button.font = .systemFont(ofSize: 12)
        button.alignment = .left
        button.cell?.lineBreakMode = .byTruncatingTail
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        return button
    }

    private static func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
    }
}

@MainActor
final class QuickClipboardButton: NSButton {
    var isSelected = false { didSet { needsDisplay = true } }
    var revealOpacity: CGFloat = 1 { didSet { needsDisplay = true } }
    var textColor: NSColor { .labelColor.withAlphaComponent(isSelected ? 1 : 0.35) }
    var symbolColor: NSColor { .labelColor.withAlphaComponent(isSelected ? 1 : 0.5) }
    var actionHandler: (() -> Void)?
    var hoverHandler: (() -> Void)?
    private var hoverTracking: NSTrackingArea?
    override var acceptsFirstResponder: Bool { false }
    override var needsPanelToBecomeKey: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        isBordered = false
        focusRingType = .none
        contentTintColor = .labelColor
        target = self
        action = #selector(performAction)
    }

    required init?(coder: NSCoder) { nil }
    override var intrinsicContentSize: NSSize {
        guard imagePosition != .imageOnly else { return super.intrinsicContentSize }
        let width = (title as NSString).size(withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 12)]).width
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
        effectiveAppearance.performAsCurrentDrawingAppearance { drawContents() }
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
                colored.draw(in: rect, from: .zero, operation: .sourceOver, fraction: revealOpacity, respectFlipped: true, hints: nil)
            }
            if !title.isEmpty {
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineBreakMode = .byTruncatingTail
                let font = font ?? NSFont.systemFont(ofSize: 12)
                let height = ceil(font.ascender - font.descender)
                let rect = pixelAligned(CGRect(x: 22, y: bounds.midY - height / 2,
                    width: max(0, bounds.width - 22), height: height))
                (title as NSString).draw(in: rect, withAttributes: [.font: font,
                    .foregroundColor: textColor.withAlphaComponent(textColor.alphaComponent * revealOpacity), .paragraphStyle: paragraph])
            }
            return
        }
        let available = bounds.insetBy(dx: 0, dy: 8)
        let ratio = min(available.width / max(1, image.size.width), available.height / max(1, image.size.height))
        let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        let rect = CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).addClip()
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: revealOpacity, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let tracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(tracking)
        hoverTracking = tracking
    }

    override func mouseEntered(with event: NSEvent) { hoverHandler?() }
    @objc private func performAction() { actionHandler?() }
}

final class QuickClipboardPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
