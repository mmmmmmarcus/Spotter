import AppKit
import Combine

@MainActor
final class QuickAIChatController: NSObject, ObservableObject, NSWindowDelegate {
    @Published var draft = ""
    @Published private(set) var sessionID: UUID?
    @Published private(set) var notice: String?
    @Published private(set) var focusToken = UUID()
    private let chat: AIChatStore
    private let tools: AIToolStore
    private let router: OpenRouterStore
    private let showSettings: () -> Void
    private var panel: QuickAIChatPanel?
    private var previousApp: NSRunningApplication?
    private weak var previousWindow: NSWindow?
    private var sessionsObservation: AnyCancellable?
    private var transcriptHeight: CGFloat = 0
    private var resizeTask: Task<Void, Never>?

    init(chat: AIChatStore, tools: AIToolStore, router: OpenRouterStore, showSettings: @escaping () -> Void) {
        self.chat = chat
        self.tools = tools
        self.router = router
        self.showSettings = showSettings
        super.init()
        sessionsObservation = chat.$sessions.sink { [weak self] sessions in
            guard let self, let sessionID, !sessions.contains(where: { $0.id == sessionID }) else { return }
            self.sessionID = nil
            resetTranscriptHeight()
            resize()
        }
    }

    var isVisible: Bool { panel?.isVisible == true }
    var isKeyWindow: Bool { panel?.isKeyWindow == true }
    var isExpanded: Bool { sessionID != nil }
    func owns(_ id: UUID) -> Bool { sessionID == id }

    private var bodyWidth: CGFloat { Theme.Size.quickAIWidth * (isExpanded ? 2 : 1) }

    var bodyHeight: CGFloat {
        let noticeHeight = notice == nil ? 0 : Theme.Size.headerHeight
        guard isExpanded else { return Theme.Size.quickAIComposerHeight + noticeHeight }
        let chrome = Theme.Size.headerHeight + Theme.Size.quickAIComposerHeight + Theme.Spacing.md * 2
        return min(Theme.Size.panelHeight, chrome + max(48, transcriptHeight) + noticeHeight)
    }

    func updateTranscriptSize(_ size: CGSize, sessionID: UUID) {
        let availableWidth = panel?.screen?.visibleFrame.insetBy(dx: Theme.Spacing.md, dy: Theme.Spacing.md).width ?? bodyWidth
        // Ignore measurements made at an intermediate width during the compact-to-chat animation.
        guard self.sessionID == sessionID, abs(size.width - min(bodyWidth, availableWidth)) < 1,
              size.height.isFinite, size.height > transcriptHeight, bodyHeight < Theme.Size.panelHeight else { return }
        // A reply can lose its status row at completion; keep the attained height until New Chat.
        transcriptHeight = min(ceil(size.height), Theme.Size.panelHeight)
        guard resizeTask == nil else { return }
        resizeTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(80)) }
            catch { return }
            guard let self, self.sessionID == sessionID else { return }
            resizeTask = nil
            resize()
        }
    }

    private func resetTranscriptHeight() {
        resizeTask?.cancel()
        resizeTask = nil
        transcriptHeight = 0
    }

    func show(previousApplication: NSRunningApplication?) {
        let wasVisible = isVisible
        if !wasVisible {
            previousApp = previousApplication
            previousWindow = NSApp.keyWindow
        }
        let panel = ensurePanel()
        if !wasVisible, let screen = targetScreen() {
            let frame = QuickAIChatLayout.initialFrame(
                size: CGSize(width: bodyWidth, height: bodyHeight + PaletteDragHandleView.stripHeight),
                visibleFrame: screen.visibleFrame, bottomGap: Theme.Spacing.xxl, margin: Theme.Spacing.md)
            panel.setFrame(frame, display: true)
        }
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        DispatchQueue.main.async { [weak self, weak panel] in
            guard let self, let panel, panel.isVisible else { return }
            panel.makeKeyAndOrderFront(nil)
            self.focusToken = UUID()
        }
    }

    func hide(restoreFocus: Bool = true) {
        let shouldRestore = restoreFocus && isKeyWindow
        panel?.orderOut(nil)
        if shouldRestore {
            if let previousWindow, previousWindow.isVisible { previousWindow.makeKeyAndOrderFront(nil) }
            else { previousApp?.activate() }
        }
    }

    func submit() {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard chat.isReady else {
            notice = "Add an OpenRouter API key in AI Chat Settings to send."
            resize()
            return
        }
        guard !chat.isWaiting else {
            notice = "A reply is still in progress. Your draft is kept here."
            resize()
            return
        }
        let id = sessionID ?? chat.createSession()
        guard chat.send(draft, sessionID: id) else { return }
        sessionID = id
        draft = ""
        notice = nil
        resize()
    }

    func newConversation() {
        resetTranscriptHeight()
        sessionID = nil
        draft = ""
        notice = nil
        resize()
        focusToken = UUID()
    }

    func openSettings() {
        hide(restoreFocus: false)
        showSettings()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.focusToken = UUID() }
    }

    private func resize() {
        guard let panel, let screen = panel.screen ?? targetScreen() else { return }
        let frame = QuickAIChatLayout.resizedFrame(panel.frame, width: bodyWidth,
            height: bodyHeight + PaletteDragHandleView.stripHeight,
            visibleFrame: screen.visibleFrame, margin: Theme.Spacing.md)
        guard panel.frame != frame else { return }
        panel.setFrame(frame, display: true,
            animate: panel.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    private func ensurePanel() -> QuickAIChatPanel {
        if let panel { return panel }
        let view = QuickAIChatView(controller: self, chat: chat, tools: tools, router: router)
        let panel = QuickAIChatPanel(rootView: view,
            size: CGSize(width: bodyWidth, height: bodyHeight + PaletteDragHandleView.stripHeight),
            cornerRadius: Theme.Radius.panel)
        panel.delegate = self
        panel.onDismiss = { [weak self] in self?.hide() }
        self.panel = panel
        return panel
    }

    private func targetScreen() -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
    }
}
