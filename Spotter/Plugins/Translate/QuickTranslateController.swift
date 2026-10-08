import AppKit
import Combine
import QuartzCore
import NaturalLanguage

@MainActor
final class QuickTranslateController: NSObject {
    private let manager: TranslateManager
    private let hotKeys: HotKeyManager
    private let align: @MainActor ([TranslationWord], [TranslationWord]) async throws -> [TranslationWordLink]
    private var alignmentTask: Task<Void, Never>?
    private var alignmentReady = false
    private var alignmentLabel: NSTextField?
    private var panel: QuickTranslatePanel?
    private var observation: AnyCancellable?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var anchor = CGPoint.zero
    private var revealTask: Task<Void, Never>?
    private var pendingState: TranslateState?
    private var displayedText: String?
    private var result: TranslationResult?
    private var showsOriginal = false
    private var textViews: [TranslationHoverTextView] = []
    private var sourceTokens: [TranslationWord] = []
    private var targetTokens: [TranslationWord] = []
    private var wordLinks: [TranslationWordLink] = []

    init(manager: TranslateManager, hotKeys: HotKeyManager,
        align: @escaping @MainActor ([TranslationWord], [TranslationWord]) async throws -> [TranslationWordLink]) {
        self.align = align
        self.manager = manager
        self.hotKeys = hotKeys
        super.init()
    }

    isolated deinit {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        hotKeys.releaseTransientKey(id: "quick-translate.escape")
    }

    func show(at point: CGPoint, original: String? = nil) {
        dismiss()
        anchor = point
        let panel = QuickTranslatePanel(contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.acceptsMouseMovedEvents = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.panel = panel
        if let original {
            renderText(original, loading: true)
            revealTask = Task { [weak self, weak panel] in
                try? await Task.sleep(for: .seconds(Theme.QuickTranslate.revealDuration))
                guard !Task.isCancelled, let self, let panel, self.panel === panel else { return }
                self.revealTask = nil
                if let state = self.pendingState {
                    self.pendingState = nil
                    self.render(state)
                }
            }
        }
        observation = manager.$state.sink { [weak self] state in
            guard let self else { return }
            if self.revealTask != nil { self.pendingState = state }
            else { self.render(state) }
        }
        hotKeys.holdTransientKey(id: "quick-translate.escape", shortcut: KeyShortcut(carbonKeyCode: 53, carbonModifiers: 0)) { [weak self] in
            self?.dismiss(cancelWork: true)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                if event.window !== self?.panel { self?.dismiss(cancelWork: true) }
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss(cancelWork: true) }
        }
    }

    func dismiss(cancelWork: Bool = false) {
        let wasVisible = panel != nil
        observation = nil
        revealTask?.cancel()
        revealTask = nil
        pendingState = nil
        displayedText = nil
        result = nil
        showsOriginal = false
        textViews = []
        wordLinks = []
        alignmentTask?.cancel()
        alignmentTask = nil
        alignmentReady = false
        alignmentLabel = nil
        panel?.orderOut(nil)
        panel = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
        hotKeys.releaseTransientKey(id: "quick-translate.escape")
        if cancelWork, wasVisible { manager.reset() }
    }

    private func render(_ state: TranslateState) {
        guard let text = state.quickPanelText else {
            dismiss()
            return
        }
        let updated: TranslationResult?
        if case .translated(let translation) = state { updated = translation } else { updated = nil }
        if result != updated {
            alignmentTask?.cancel()
            alignmentTask = nil
            alignmentReady = false
            wordLinks = []
            result = updated
            if updated == nil { showsOriginal = false }
        }
        let loading: Bool
        if case .loading = state { loading = true } else { loading = false }
        renderText(text, loading: loading)
        if showsOriginal { startAlignment() }
    }

    @objc private func copyResult() {
        guard let result else { return }
        Paster.copyPlainText(result.rows.map(\.text).joined(separator: "\n\n"))
    }

    @objc private func toggleOriginal() {
        guard let result else { return }
        showsOriginal.toggle()
        renderText(result.rows.map(\.text).joined(separator: "\n\n"), loading: false)
        if showsOriginal { startAlignment() }
    }

    private func startAlignment() {
        guard !alignmentReady, alignmentTask == nil else { return }
        alignmentLabel?.stringValue = "Matching words…"
        let source = sourceTokens
        let target = targetTokens
        alignmentTask = Task { [weak self] in
            guard let self else { return }
            do {
                let links = try await align(source, target)
                try Task.checkCancellation()
                wordLinks = links
                alignmentReady = true
                alignmentLabel?.stringValue = links.isEmpty ? "No word matches" : ""
                alignmentLabel?.isHidden = !links.isEmpty
                alignmentLabel?.toolTip = nil
            } catch {
                guard !Task.isCancelled else { return }
                alignmentLabel?.stringValue = "Word matching unavailable"
                alignmentLabel?.toolTip = error.localizedDescription
            }
            alignmentTask = nil
        }
    }

    private func highlight(_ index: Int?, source: Bool) {
        guard showsOriginal else { return }
        let ranges = TranslationWordAlignment.ranges(hovered: index, source: source,
            sourceWords: sourceTokens, targetWords: targetTokens, links: wordLinks)
        for view in textViews {
            view.highlight(view.isSource ? ranges.source : ranges.target, active: index != nil)
        }
    }

    private func renderText(_ text: String, loading: Bool) {
        let identity = "\(loading)-\(showsOriginal)-\(result != nil)-" + text
        guard let panel, displayedText != identity else { return }
        displayedText = identity
        let wasVisible = panel.isVisible
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let screen = (NSScreen.screens.first { $0.frame.contains(anchor) } ?? NSScreen.main)?.visibleFrame ?? .zero
        let inset = Theme.Spacing.xl
        let width = min(Theme.QuickTranslate.width, screen.width - inset * 2)
        let contentWidth = max(1, width - inset * 2)
        let document = TranslationDocumentView()
        textViews = []
        var offset: CGFloat = 0
        func appendText(_ value: String, source: Bool, muted: Bool) {
            let view = TranslationHoverTextView(frame: NSRect(x: 0, y: offset, width: contentWidth, height: 1))
            view.isSource = source
            view.words = showsOriginal ? TranslationWordAlignment.tokenize(value) : []
            if source { sourceTokens = view.words } else { targetTokens = view.words }
            view.onHover = { [weak self] index in self?.highlight(index, source: source) }
            view.isEditable = false
            view.isSelectable = true
            view.drawsBackground = false
            view.textContainerInset = .zero
            view.textContainer?.lineFragmentPadding = 0
            view.textContainer?.containerSize = CGSize(width: contentWidth, height: .greatestFiniteMagnitude)
            view.isHorizontallyResizable = false
            view.isVerticallyResizable = true
            view.font = .systemFont(ofSize: Theme.QuickTranslate.fontSize)
            view.textColor = muted ? .secondaryLabelColor : .labelColor
            view.string = value
            if let container = view.textContainer { view.layoutManager?.ensureLayout(for: container) }
            let measured = ceil(view.textContainer.flatMap { view.layoutManager?.usedRect(for: $0).height } ?? 1)
            view.setFrameSize(CGSize(width: contentWidth, height: measured))
            document.addSubview(view)
            textViews.append(view)
            offset += measured
        }
        if showsOriginal, let result {
            appendText(result.original, source: true, muted: false)
            offset += inset
            let divider = NSBox(frame: NSRect(x: 0, y: offset, width: contentWidth, height: 1))
            divider.boxType = .separator
            document.addSubview(divider)
            offset += inset
        }
        appendText(text, source: false, muted: loading)
        document.frame = NSRect(x: 0, y: 0, width: contentWidth, height: offset)
        let footer: CGFloat = result == nil ? 0 : 30
        let height = min(offset + inset * 2 + footer, min(Theme.QuickTranslate.maxHeight, screen.height - inset * 2))
        let scroll = NSScrollView(frame: NSRect(x: inset, y: inset + footer, width: contentWidth, height: max(1, height - inset * 2 - footer)))
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = document
        let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        content.wantsLayer = true
        content.addSubview(scroll)
        if result != nil {
            for (index, item) in [("doc.on.doc", "Copy Translation", #selector(copyResult)),
                ("rectangle.split.1x2", showsOriginal ? "Hide Original" : "Show Original", #selector(toggleOriginal))].enumerated() {
                let button = NSButton(image: NSImage(systemSymbolName: item.0, accessibilityDescription: item.1)!, target: self, action: item.2)
                button.frame = NSRect(x: inset + CGFloat(index) * 32, y: inset - 4, width: 26, height: 26)
                button.isBordered = false
                button.toolTip = index == 1 && !showsOriginal ? "Show Original · AI word matching via OpenRouter / Gemini 2.5 Flash-Lite" : item.1
                button.setAccessibilityLabel(item.1)
                content.addSubview(button)
            }
        }
        alignmentLabel = nil
        if showsOriginal {
            let label = NSTextField(labelWithString: alignmentReady ? (wordLinks.isEmpty ? "No word matches" : "") : "Matching words…")
            label.isHidden = alignmentReady && !wordLinks.isEmpty
            label.font = .systemFont(ofSize: 10)
            label.textColor = .secondaryLabelColor
            label.frame = NSRect(x: inset + 68, y: inset + 2, width: max(1, contentWidth - 68), height: 18)
            label.lineBreakMode = .byTruncatingTail
            content.addSubview(label)
            alignmentLabel = label
        }
        let glass = (panel.contentView as? NSGlassEffectView) ?? NSGlassEffectView(frame: content.bounds)
        let host = glass.contentView ?? NSView(frame: content.bounds)
        let outgoing = host.subviews
        host.frame = content.bounds
        host.addSubview(content)
        glass.style = .clear
        glass.cornerRadius = Theme.Radius.menuPanel
        glass.contentView = host
        panel.contentView = glass
        let gap = Theme.Spacing.md
        let below = anchor.y - gap - height
        let y = below >= screen.minY + gap ? below : anchor.y + gap
        let frame = NSRect(x: min(max(anchor.x, screen.minX + gap), screen.maxX - width - gap),
            y: min(max(y, screen.minY + gap), screen.maxY - height - gap), width: width, height: height)
        if !wasVisible {
            panel.alphaValue = 0
            panel.setFrame(reduceMotion ? frame : frame.offsetBy(dx: 0, dy: -Theme.QuickTranslate.revealOffset), display: true)
            panel.orderFrontRegardless()
        } else {
            content.alphaValue = 0
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = wasVisible ? Theme.QuickTranslate.replaceDuration : Theme.QuickTranslate.revealDuration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
            if reduceMotion { panel.setFrame(frame, display: true) }
            else { panel.animator().setFrame(frame, display: true) }
            panel.animator().alphaValue = 1
            content.animator().alphaValue = 1
            for previous in outgoing { previous.animator().alphaValue = 0 }
        } completionHandler: { [weak panel] in
            MainActor.assumeIsolated {
                outgoing.forEach { $0.removeFromSuperview() }
                panel?.invalidateShadow()
            }
        }
        panel.invalidateShadow()
    }
}

private final class QuickTranslatePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}


private final class TranslationDocumentView: NSView {
    override var isFlipped: Bool { true }
}

private final class TranslationHoverTextView: NSTextView {
    var isSource = false
    var words: [TranslationWord] = []
    var onHover: ((Int?) -> Void)?
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        guard let layoutManager, let textContainer else { return }
        var point = convert(event.locationInWindow, from: nil)
        point.x -= textContainerOrigin.x
        point.y -= textContainerOrigin.y
        let glyph = layoutManager.glyphIndex(for: point, in: textContainer)
        guard glyph < layoutManager.numberOfGlyphs,
            layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer).contains(point) else {
            onHover?(nil)
            return
        }
        let character = layoutManager.characterIndexForGlyph(at: glyph)
        onHover?(words.firstIndex { NSLocationInRange(character, $0.range) })
    }

    override func mouseExited(with event: NSEvent) { onHover?(nil) }

    func highlight(_ ranges: [NSRange], active: Bool) {
        let entire = NSRange(location: 0, length: (string as NSString).length)
        layoutManager?.removeTemporaryAttribute(.foregroundColor, forCharacterRange: entire)
        guard active else { return }
        layoutManager?.addTemporaryAttribute(.foregroundColor,
            value: Theme.QuickTranslate.unfocusedWord, forCharacterRange: entire)
        for range in ranges {
            layoutManager?.addTemporaryAttribute(.foregroundColor,
                value: Theme.QuickTranslate.focusedWord, forCharacterRange: range)
        }
    }
}
