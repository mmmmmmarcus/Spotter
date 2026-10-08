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
    private var motion: Task<Void, Never>?
    private var isClosing = false
    private var motionTarget: CGRect?
    private var previousApp: NSRunningApplication?
    private weak var previousWindow: NSWindow?
    private var sessionsObservation: AnyCancellable?
    private var replyObservation: AnyCancellable?
    @Published private(set) var hasReceivedReply = false

    init(chat: AIChatStore, tools: AIToolStore, router: OpenRouterStore, showSettings: @escaping () -> Void) {
        self.chat = chat
        self.tools = tools
        self.router = router
        self.showSettings = showSettings
        super.init()
        sessionsObservation = chat.$sessions.sink { [weak self] sessions in
            guard let self, let sessionID else { return }
            guard let session = sessions.first(where: { $0.id == sessionID }) else {
                self.sessionID = nil
                hasReceivedReply = false
                resize()
                return
            }
            if session.messages.contains(where: { $0.role == .assistant && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                expandForReply(in: sessionID)
            }
        }
        replyObservation = chat.$streamingReply.sink { [weak self] reply in
            guard let self, let reply, !reply.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                let replyingSession = self.chat.waitingSessionID else { return }
            expandForReply(in: replyingSession)
        }
    }

    var isVisible: Bool { panel?.isVisible == true }
    var isKeyWindow: Bool { !isClosing && panel?.isKeyWindow == true }
    var isExpanded: Bool { sessionID != nil }
    func owns(_ id: UUID) -> Bool { sessionID == id }

    private var bodyWidth: CGFloat { Theme.Size.quickAIWidth * (isExpanded ? 2 : 1) }

    var bodyHeight: CGFloat {
        let noticeHeight = notice == nil ? 0 : Theme.Size.headerHeight
        guard isExpanded else { return Theme.Size.quickAIComposerHeight + noticeHeight }
        if hasReceivedReply { return Theme.Size.panelHeight }
        let chrome = Theme.Size.quickAIHeaderHeight + Theme.Size.quickAIComposerHeight + Theme.Spacing.xl * 2
        return chrome + Theme.Size.quickAIInitialTranscriptHeight + noticeHeight
    }

    private func expandForReply(in id: UUID) {
        guard sessionID == id, !hasReceivedReply else { return }
        hasReceivedReply = true
        resize()
    }

    func openSession(_ id: UUID) {
        guard let session = chat.sessions.first(where: { $0.id == id }) else { return }
        sessionID = id
        notice = nil
        hasReceivedReply = session.messages.contains { $0.role == .assistant && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        resize()
    }

    func show(previousApplication: NSRunningApplication?) {
        let wasVisible = isVisible && !isClosing
        let wasClosing = isClosing
        motion?.cancel()
        isClosing = false
        panel?.ignoresMouseEvents = false
        if !wasVisible {
            previousApp = previousApplication
            previousWindow = NSApp.keyWindow
        }
        let panel = ensurePanel()
        if !wasVisible, !wasClosing, let screen = targetScreen() {
            let frame = QuickAIChatLayout.initialFrame(
                size: CGSize(width: bodyWidth, height: bodyHeight),
                visibleFrame: screen.visibleFrame, bottomGap: Theme.Spacing.xxl, margin: Theme.Spacing.md)
            panel.setFrame(frame, display: true)
        }
        let destination = motionTarget ?? panel.frame
        if !wasVisible && !wasClosing {
            panel.alphaValue = 0
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                panel.setFrame(destination.offsetBy(dx: 0, dy: -Theme.Spacing.md), display: false)
            }
        }
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        animate(to: destination, opacity: 1, duration: Theme.QuickAI.revealDuration)
        DispatchQueue.main.async { [weak self, weak panel] in
            guard let self, let panel, panel.isVisible, !self.isClosing else { return }
            panel.makeKeyAndOrderFront(nil)
            self.focusToken = UUID()
        }
    }

    func hide(restoreFocus: Bool = true, animated: Bool = true) {
        let shouldRestore = restoreFocus && isKeyWindow
        guard let panel else { return }
        isClosing = true
        panel.ignoresMouseEvents = true
        if animated && panel.isVisible {
            animate(to: motionTarget ?? panel.frame, opacity: 0, duration: Theme.QuickAI.dismissDuration) { [weak self] in
                self?.panel?.orderOut(nil)
                self?.isClosing = false
            }
        } else {
            motion?.cancel()
            motion = nil
            motionTarget = nil
            panel.orderOut(nil)
            panel.alphaValue = 0
            isClosing = false
        }
        if shouldRestore {
            if let previousWindow, previousWindow.isVisible { previousWindow.makeKeyAndOrderFront(nil) }
            else { previousApp?.activate() }
        }
    }

    func submit() {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard chat.isReady else {
            notice = "Configure OpenRouter or install Claude/Codex CLI in AI Chat Settings to send."
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
        hasReceivedReply = false
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
        let frame = QuickAIChatLayout.resizedFrame(motionTarget ?? panel.frame, width: bodyWidth,
            height: bodyHeight,
            visibleFrame: screen.visibleFrame, margin: Theme.Spacing.md)
        guard panel.frame != frame else { return }
        if panel.isVisible && !isClosing {
            animate(to: frame, opacity: 1, duration: Theme.QuickAI.expandDuration)
        } else {
            motion?.cancel()
            motionTarget = nil
            panel.setFrame(frame, display: true)
            if isClosing { panel.orderOut(nil); isClosing = false }
        }
    }

    private func animate(to frame: CGRect, opacity: CGFloat, duration: TimeInterval, completion: (() -> Void)? = nil) {
        motion?.cancel()
        guard let panel else { return }
        let startFrame = panel.frame
        let startOpacity = panel.alphaValue
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        motionTarget = frame
        if reduceMotion { panel.setFrame(frame, display: true) }
        motion = Task { @MainActor [weak self, weak panel] in
            let start = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                guard let self, let panel else { return }
                let t = min(1, (ProcessInfo.processInfo.systemUptime - start) / duration)
                // A normalized critically damped response settles quickly without bouncing the reading surface.
                let progress = CGFloat((1 - (1 + 8 * t) * exp(-8 * t)) / (1 - 9 * exp(-8)))
                if !reduceMotion {
                    panel.setFrame(CGRect(
                        x: startFrame.minX + (frame.minX - startFrame.minX) * progress,
                        y: startFrame.minY + (frame.minY - startFrame.minY) * progress,
                        width: startFrame.width + (frame.width - startFrame.width) * progress,
                        height: startFrame.height + (frame.height - startFrame.height) * progress), display: true)
                }
                panel.alphaValue = startOpacity + (opacity - startOpacity) * progress
                if t >= 1 {
                    motionTarget = nil
                    motion = nil
                    completion?()
                    return
                }
                do { try await Task.sleep(for: .milliseconds(8)) }
                catch { return }
            }
        }
    }

    private func ensurePanel() -> QuickAIChatPanel {
        if let panel { return panel }
        let view = QuickAIChatView(controller: self, chat: chat, tools: tools, router: router)
        let panel = QuickAIChatPanel(rootView: view,
            size: CGSize(width: bodyWidth, height: bodyHeight),
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
