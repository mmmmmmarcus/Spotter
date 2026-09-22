import AppKit
import QuartzCore

@MainActor
final class QuickClipboardMenuView: NSView {
    let glassContainer = NSGlassEffectContainerView()
    private let glassContent = NSView()
    private let rowsView = NSView()
    private let shadowLayer = CALayer()
    private var shadowImages: [CGImage]
    private var shadowPreparation: Task<Void, Never>?
    private var rowWidths: [CGFloat]
    private let backingScale: CGFloat
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

    init(items: [ClipboardItem], shadowImages: [CGImage], scale: CGFloat = 2, now: @escaping () -> CFTimeInterval = CACurrentMediaTime) {
        self.now = now
        self.shadowImages = shadowImages
        self.backingScale = scale
        self.rowWidths = Self.widths(for: items)
        let size = QuickClipboardPresentation.size(count: items.count)
        let margin = QuickClipboardPresentation.shadowMargin
        super.init(frame: CGRect(origin: .zero, size: CGSize(width: size.width + margin * 2, height: size.height + margin * 2)))
        wantsLayer = true
        glassContainer.frame = CGRect(origin: CGPoint(x: margin, y: margin), size: size)
        glassContent.frame = CGRect(origin: .zero, size: size)
        glassContainer.spacing = 0
        glassContainer.contentView = glassContent
        glassContainer.wantsLayer = true
        glassContainer.layer?.masksToBounds = true
        let rowCount = max(1, items.count)
        rowsView.frame = glassContent.bounds
        rowsView.wantsLayer = true
        rowsView.clipsToBounds = true
        glassContent.addSubview(rowsView)
        addSubview(glassContainer)
        let frames = QuickClipboardPresentation.rowFrames(widths: rowWidths)
        for index in 0..<rowCount {
            let rect = frames[index]
            let content = NSView(frame: CGRect(origin: .zero, size: rect.size))
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
        shadowLayer.zPosition = 100
        shadowLayer.frame = bounds
        shadowLayer.contents = shadowImages.first
        shadowLayer.contentsGravity = .resize
        // The hollow shadow sits above the glass without entering any glass sampling region.
        layer?.addSublayer(shadowLayer)
        renderRows(offset: 0, viewportWidth: QuickClipboardPresentation.visibleWidth(first: 0, widths: rowWidths))
        update(items, selection: 0)
    }

    required init?(coder: NSCoder) { nil }

    isolated deinit {
        scrollTask?.cancel()
        shadowPreparation?.cancel()
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
        if widths != rowWidths || shadowImages.isEmpty {
            rowWidths = widths
            shadowImages = []
            shadowLayer.contents = nil
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
            shadowLayer.opacity = 1
            shadowPreparation?.cancel()
            let scale = backingScale
            shadowPreparation = Task { [weak self] in
                let images = await Task.detached(priority: .userInitiated) {
                    QuickClipboardShadow.renderWindows(widths: widths, scale: scale)
                }.value
                guard !Task.isCancelled, let self, rowWidths == widths else { return }
                shadowImages = images
                updateShadow()
            }
        }
        select(selection)
    }

    func select(_ index: Int, animated: Bool = false) {
        selectedIndex = index
        for (offset, glass) in rowGlass.enumerated() {
            glass.tintColor = offset == index ? .selectedContentBackgroundColor.withAlphaComponent(0.12) : nil
            let button = rowButtons[offset]
            if !button.title.isEmpty {
                let title = NSMutableAttributedString(attributedString: button.attributedTitle)
                title.addAttribute(.foregroundColor, value: NSColor.labelColor.withAlphaComponent(offset == index ? 1 : 0.5),
                    range: NSRange(location: 0, length: title.length))
                button.attributedTitle = title
            }
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
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for glass in rowGlass { glass.isHidden = false }
        shadowLayer.removeAnimation(forKey: "clipboard.shadow")
        // The resting bitmap's hollow regions must never overlap glass moving between rows.
        shadowLayer.opacity = shouldAnimate ? 0 : 1
        CATransaction.commit()
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
            glass.setFrameOrigin(CGPoint(x: frames[index].minX - offset, y: 0))
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
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shadowLayer.opacity = 1
        CATransaction.commit()
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.1
        shadowLayer.add(fade, forKey: "clipboard.shadow")
    }

    private func updateShadow() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shadowLayer.contents = shadowImages.indices.contains(firstVisibleIndex) ? shadowImages[firstVisibleIndex] : nil
        CATransaction.commit()
    }

    private func hideOffscreenRows() {
        updateShadow()
        for (index, glass) in rowGlass.enumerated() {
            glass.isHidden = index < firstVisibleIndex || index >= firstVisibleIndex + QuickClipboardPresentation.visibleLimit
        }
    }

    func containsGlass(_ point: CGPoint) -> Bool {
        let margin = QuickClipboardPresentation.shadowMargin
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
        button.imageScaling = .scaleProportionallyDown
        if item.kind == .image {
            button.title = ""
            button.imagePosition = .imageOnly
            button.contentTintColor = nil
            if let path = item.imagePath,
               let cached = ImageThumbnail.cached(URL(fileURLWithPath: path), maxPixel: 128),
               let preview = cached.copy() as? NSImage {
                let ratio = min(218 / max(1, preview.size.width), 24 / max(1, preview.size.height))
                preview.size = CGSize(width: preview.size.width * ratio, height: preview.size.height * ratio)
                button.image = preview
            } else {
                button.image = symbol("photo")
            }
        } else {
            button.title = "  " + QuickClipboardPresentation.title(for: item)
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
private final class QuickClipboardButton: NSButton {
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
    override func draw(_ dirtyRect: NSRect) {
        guard imagePosition == .imageOnly, let image, !image.isTemplate else {
            super.draw(dirtyRect)
            return
        }
        let available = bounds.insetBy(dx: 0, dy: 8)
        let ratio = min(available.width / max(1, image.size.width), available.height / max(1, image.size.height))
        let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        let rect = CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).addClip()
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
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
