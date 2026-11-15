import AppKit
import Carbon.HIToolbox
import Combine
import QuartzCore
import NaturalLanguage

@MainActor
final class QuickTranslateController: NSObject {
    private let manager: TranslateManager
    private let hotKeys: HotKeyManager
    private let align: @MainActor ([TranslationWord], [TranslationWord]) async throws -> [TranslationWordLink]
    /// Injected by `AppCore`, which owns both this bubble and the replacement machinery, so
    /// Translate carries only the plain selection data and never reaches into AI Chat.
    private let replaceSelection: @MainActor (String, pid_t, String) -> Void
    private var replacementSource: (text: String, pid: pid_t)?
    private var heldKeys: Set<QuickTranslateKeyAction> = []
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
        align: @escaping @MainActor ([TranslationWord], [TranslationWord]) async throws -> [TranslationWordLink],
        replaceSelection: @escaping @MainActor (String, pid_t, String) -> Void) {
        self.align = align
        self.replaceSelection = replaceSelection
        self.manager = manager
        self.hotKeys = hotKeys
        super.init()
    }

    isolated deinit {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        releaseKeys()
    }

    func show(at point: CGPoint, original: String? = nil, pid: pid_t? = nil) {
        dismiss()
        anchor = point
        if let original, let pid { replacementSource = (original, pid) }
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
        syncKeys()
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
        replacementSource = nil
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
        releaseKeys()
        if cancelWork, wasVisible { manager.reset() }
    }

    /// Claims exactly the keys whose action is live right now, and gives back the rest. Carbon
    /// consumes a held key from the frontmost app, so an outlived claim would eat the user's own
    /// Return or arrows — every entry and exit of the bubble's states runs through here.
    private func syncKeys() {
        let wanted = QuickTranslateKeyAction.active(hasResult: result != nil,
            canReplace: replacementSource != nil, showsOriginal: showsOriginal)
        for action in heldKeys.subtracting(wanted) {
            hotKeys.releaseTransientKey(id: Self.keyID(action))
        }
        for action in wanted.subtracting(heldKeys) {
            hotKeys.holdTransientKey(id: Self.keyID(action), shortcut: Self.shortcut(for: action)) { [weak self] in
                self?.perform(action)
            }
        }
        heldKeys = wanted
    }

    private func releaseKeys() {
        for action in heldKeys { hotKeys.releaseTransientKey(id: Self.keyID(action)) }
        heldKeys = []
    }

    private static func keyID(_ action: QuickTranslateKeyAction) -> String {
        "quick-translate." + action.rawValue
    }

    private static func shortcut(for action: QuickTranslateKeyAction) -> KeyShortcut {
        switch action {
        case .dismiss: KeyShortcut(carbonKeyCode: kVK_Escape, carbonModifiers: 0)
        case .copy: KeyShortcut(carbonKeyCode: kVK_Return, carbonModifiers: 0)
        case .replaceSelection: KeyShortcut(carbonKeyCode: kVK_Return, carbonModifiers: Int(cmdKey))
        case .openComparison: KeyShortcut(carbonKeyCode: kVK_DownArrow, carbonModifiers: 0)
        case .closeComparison: KeyShortcut(carbonKeyCode: kVK_UpArrow, carbonModifiers: 0)
        }
    }

    /// The footer's symbol, label, keycap and click target for one action. `text.insert` is already
    /// Spotter's icon for Paste Snippet, the nearest action of the same kind.
    private static func footerButton(for action: QuickTranslateKeyAction)
        -> (symbol: String, title: String, keycap: String, selector: Selector)?
    {
        switch action {
        case .dismiss: nil
        case .copy: ("doc.on.doc", "Copy Translation", "↵", #selector(copyResult))
        case .replaceSelection: ("text.insert", "Replace Selection", "⌘↵", #selector(replaceOriginalSelection))
        case .openComparison: ("rectangle.split.1x2", "Show Original", "↓", #selector(toggleOriginal))
        case .closeComparison: ("rectangle.split.1x2", "Hide Original", "↑", #selector(toggleOriginal))
        }
    }

    private func perform(_ action: QuickTranslateKeyAction) {
        switch action {
        case .dismiss: dismiss(cancelWork: true)
        case .copy:
            copyResult()
            dismiss(cancelWork: true)
        case .replaceSelection: replaceOriginalSelection()
        case .openComparison: if !showsOriginal { toggleOriginal() }
        case .closeComparison: if showsOriginal { toggleOriginal() }
        }
    }

    /// The target is built inside `replaceSelection`, synchronously on this keypress rather than
    /// when the bubble opened: the paste-only path watches for any key or click and would have
    /// invalidated itself on this very ⌘↵.
    @objc private func replaceOriginalSelection() {
        guard let result, let source = replacementSource else { return }
        let translation = result.rows.map(\.text).joined(separator: "\n\n")
        dismiss(cancelWork: true)
        replaceSelection(source.text, source.pid, translation)
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
        syncKeys()
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
        syncKeys()
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
        // Same availability rule as `syncKeys`, so a button and a held key can never disagree.
        let footerActions = QuickTranslateKeyAction.footerActions(hasResult: result != nil,
            canReplace: replacementSource != nil, showsOriginal: showsOriginal)
        let footer: CGFloat = footerActions.isEmpty ? 0 : 30
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
        for (index, action) in footerActions.enumerated() {
            guard let item = Self.footerButton(for: action) else { continue }
            let button = NSButton(image: NSImage(systemSymbolName: item.symbol, accessibilityDescription: item.title)!, target: self, action: item.selector)
            button.frame = NSRect(x: inset + CGFloat(index) * 32, y: inset - 4, width: 26, height: 26)
            button.isBordered = false
            button.toolTip = "\(item.title) · \(item.keycap)"
                + (action == .openComparison ? " · AI word matching via OpenRouter / Gemini 2.5 Flash-Lite" : "")
            button.setAccessibilityLabel(item.title)
            content.addSubview(button)
        }
        alignmentLabel = nil
        if showsOriginal {
            let label = NSTextField(labelWithString: alignmentReady ? (wordLinks.isEmpty ? "No word matches" : "") : "Matching words…")
            label.isHidden = alignmentReady && !wordLinks.isEmpty
            label.font = .systemFont(ofSize: 10)
            label.textColor = .secondaryLabelColor
            // Starts past the last occupied slot, so a new footer button never lands under the status.
            let leading = CGFloat(footerActions.count) * 32 + 4
            label.frame = NSRect(x: inset + leading, y: inset + 2, width: max(1, contentWidth - leading), height: 18)
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
