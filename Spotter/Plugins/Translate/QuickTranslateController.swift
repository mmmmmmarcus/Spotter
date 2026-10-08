import AppKit
import Combine

@MainActor
final class QuickTranslateController {
    private let manager: TranslateManager
    private let hotKeys: HotKeyManager
    private var panel: QuickTranslatePanel?
    private var observation: AnyCancellable?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var anchor = CGPoint.zero

    init(manager: TranslateManager, hotKeys: HotKeyManager) {
        self.manager = manager
        self.hotKeys = hotKeys
    }

    isolated deinit {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        hotKeys.releaseTransientKey(id: "quick-translate.escape")
    }

    func show(at point: CGPoint) {
        dismiss()
        anchor = point
        let panel = QuickTranslatePanel(contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.panel = panel
        observation = manager.$state.sink { [weak self] state in self?.render(state) }
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
        guard let panel else { return }
        let text: String
        switch state {
        case .idle:
            dismiss()
            return
        case .loading: text = "Translating…"
        case .failed(let message): text = message
        case .translated(let result): text = result.rows.map(\.text).joined(separator: "\n\n")
        }
        let screen = (NSScreen.screens.first { $0.frame.contains(anchor) } ?? NSScreen.main)?.visibleFrame ?? .zero
        let inset = Theme.Spacing.xl
        let width = min(Theme.QuickTranslate.width, screen.width - inset * 2)
        let contentWidth = max(1, width - inset * 2)
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: 1))
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.containerSize = CGSize(width: contentWidth, height: .greatestFiniteMagnitude)
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = true
        view.font = .systemFont(ofSize: Theme.QuickTranslate.fontSize)
        view.textColor = .labelColor
        view.string = text
        if let container = view.textContainer { view.layoutManager?.ensureLayout(for: container) }
        let measured = view.textContainer.flatMap { view.layoutManager?.usedRect(for: $0).height } ?? 1
        let textHeight = ceil(measured)
        view.setFrameSize(CGSize(width: contentWidth, height: textHeight))
        let height = min(textHeight + inset * 2, min(Theme.QuickTranslate.maxHeight, screen.height - inset * 2))
        let scroll = NSScrollView(frame: NSRect(x: inset, y: inset, width: contentWidth, height: height - inset * 2))
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = view
        let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        content.addSubview(scroll)
        let glass = NSGlassEffectView(frame: content.bounds)
        glass.style = .clear
        glass.cornerRadius = Theme.Radius.menuPanel
        glass.contentView = content
        panel.contentView = glass
        let gap = Theme.Spacing.md
        let below = anchor.y - gap - height
        let y = below >= screen.minY + gap ? below : anchor.y + gap
        let frame = NSRect(x: min(max(anchor.x, screen.minX + gap), screen.maxX - width - gap),
            y: min(max(y, screen.minY + gap), screen.maxY - height - gap), width: width, height: height)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        panel.invalidateShadow()
    }
}

private final class QuickTranslatePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
