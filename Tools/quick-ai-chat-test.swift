import AppKit
import Combine
import SwiftUI

@MainActor
final class OpenRouterStore: ObservableObject {
    var isReady = true
    var chatModel = "fixture-model"
    var chatWebSearch = false
    var requests: [[(role: String, content: String)]] = []
    private var completions: [CheckedContinuation<Void, Error>] = []

    func chat(messages: [(role: String, content: String)], model: String, webSearch: Bool,
              onDelta: @escaping @MainActor @Sendable (String) -> Void) async throws {
        requests.append(messages)
        onDelta("Partial ")
        try await withCheckedThrowingContinuation { completions.append($0) }
        try Task.checkCancellation()
        onDelta("answer")
    }

    func completeNext() { completions.removeFirst().resume() }
}

@MainActor
final class AIToolStore: ObservableObject {
    var isEnabled = false
    func stop() {}
    func run(messages: [(role: String, content: String)], model: String, webSearch: Bool,
             sessionID: UUID, router: OpenRouterStore, onText: @escaping @MainActor @Sendable (String) -> Void) async throws {
        try await router.chat(messages: messages, model: model, webSearch: webSearch, onDelta: onText)
    }
}

enum AppLog {
    static func error(_ category: String, _ message: String) {}
}

// The harness exercises the real controller and panel without mounting the application's views.
struct QuickAIChatView: View {
    let controller: QuickAIChatController
    let chat: AIChatStore
    let tools: AIToolStore
    let router: OpenRouterStore
    var body: some View { EmptyView() }
}

@main
@MainActor
struct QuickAIChatTests {
    private static var failures = 0
    private static var passes = 0

    static func expect(_ value: Bool, _ message: String) {
        if value { passes += 1 }
        else { failures += 1; print("FAIL: \(message)") }
    }

    static func waitUntil(_ predicate: () -> Bool) async {
        for _ in 0..<1000 {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        expect(false, "fixture request completed before deadline")
    }

    static func main() async {
        layout()
        nativePanel()
        await conversations()
        print("\(passes)/\(passes + failures) passed")
        if failures > 0 { exit(1) }
    }

    private static func layout() {
        let visible = CGRect(x: -1440, y: 172, width: 1440, height: 800)
        let compact = QuickAIChatLayout.initialFrame(size: CGSize(width: Theme.Size.quickAIWidth, height: Theme.Size.quickAIComposerHeight + PaletteDragHandleView.stripHeight),
            visibleFrame: visible, bottomGap: 20, margin: 8)
        expect(compact.midX == visible.midX && compact.minY == 192,
            "the compact bar centers above the Dock's reserved visible-screen edge")
        let expanded = QuickAIChatLayout.resizedFrame(compact, width: compact.width * 2, height: 501, visibleFrame: visible, margin: 8)
        expect(expanded.minY == compact.minY && expanded.midX == compact.midX && expanded.width == compact.width * 2,
            "expansion doubles the width around the composer center and keeps the bottom position")
        expect(expanded.height == 501, "the conversation gets the requested expanded height")
        let dragged = compact.offsetBy(dx: -60, dy: 100)
        let afterDrag = QuickAIChatLayout.resizedFrame(dragged, width: compact.width * 2, height: 501, visibleFrame: visible, margin: 8)
        expect(afterDrag.midX == dragged.midX && afterDrag.minY == dragged.minY, "a dragged composer expands at its new position")
        let nearTop = compact.offsetBy(dx: 500, dy: 600)
        let clamped = QuickAIChatLayout.resizedFrame(nearTop, width: compact.width * 2, height: 501, visibleFrame: visible, margin: 8)
        expect(visible.insetBy(dx: 8, dy: 8).contains(clamped) && clamped.width == compact.width * 2,
            "expansion after dragging to an edge keeps the close button and entire frame on screen")
        let restored = QuickAIChatLayout.resizedFrame(expanded, width: compact.width, height: Theme.Size.quickAIComposerHeight + PaletteDragHandleView.stripHeight, visibleFrame: visible, margin: 8)
        expect(restored == compact, "starting another chat collapses onto the same composer anchor")
        let small = CGRect(x: 200, y: -600, width: 500, height: 400)
        let bounded = QuickAIChatLayout.initialFrame(size: CGSize(width: Theme.Size.quickAIWidth * 2, height: 501),
            visibleFrame: small, bottomGap: 20, margin: 8)
        expect(small.insetBy(dx: 8, dy: 8).contains(bounded), "small secondary displays cannot strand the panel offscreen")
    }

    private static func nativePanel() {
        _ = NSApplication.shared
        let panel = QuickAIChatPanel(rootView: Text("Fixture"), size: CGSize(width: Theme.Size.quickAIWidth, height: Theme.Size.quickAIComposerHeight + PaletteDragHandleView.stripHeight), cornerRadius: 26)
        panel.setFrameOrigin(CGPoint(x: -10000, y: -10000))
        expect(panel.canBecomeKey && !panel.canBecomeMain && panel.styleMask.contains(.nonactivatingPanel),
            "the floating composer accepts typing without becoming a main application window")
        expect(panel.level == .floating && !panel.hidesOnDeactivate && !panel.isMovableByWindowBackground,
            "the chat stays floating and only the shared handle owns dragging")
        expect(panel.glassView.style == .regular && panel.glassView.cornerRadius == 16,
            "one native Liquid Glass surface owns the chat body")
        expect(!panel.hasShadow && panel.glassView.layer?.masksToBounds == true
            && panel.glassView.layer?.cornerRadius == 16 && panel.glassView.layer?.cornerCurve == .circular,
            "the glass backing clips to its rounded silhouette without a rectangular window shadow")
        let host = panel.glassView.contentView?.subviews.first as? NSHostingView<Text>
        expect(host?.sizingOptions == [], "SwiftUI cannot drive the window size")
        panel.setFrame(CGRect(x: -10000, y: -10000, width: Theme.Size.quickAIWidth * 2, height: 501), display: false)
        panel.contentView?.layoutSubtreeIfNeeded()
        expect(panel.glassView.frame == CGRect(x: 0, y: 0, width: Theme.Size.quickAIWidth * 2, height: 475),
            "expansion resizes the native glass while reserving the handle strip")
        expect(panel.glassView.cornerRadius == 26 && panel.glassView.layer?.cornerRadius == 26
            && panel.glassView.layer?.cornerCurve == .continuous,
            "the expanded chat restores its larger continuous window corners")
        expect(host?.frame.size == CGSize(width: Theme.Size.quickAIWidth * 2, height: 475),
            "the transcript host follows the glass content size")
        expect(panel.dragHandle.frame.minY == 475 && panel.dragHandle.frame.height == 26,
            "the shared handle follows the expanded upper edge")
        for height: CGFloat in [44, 32] {
            panel.setFrame(CGRect(x: -10000, y: -10000, width: Theme.Size.quickAIWidth,
                height: height + PaletteDragHandleView.stripHeight), display: false)
            panel.contentView?.layoutSubtreeIfNeeded()
            expect(panel.glassView.cornerRadius == height / 2 && panel.glassView.layer?.cornerRadius == height / 2
                && panel.glassView.layer?.cornerCurve == .circular,
                "compact and transitional heights use matching half-height circular ends")
        }
        expect(!panel.isVisible, "native panel checks never show a window or take user focus")
        panel.close()
    }

    private static func conversations() async {
        let router = OpenRouterStore()
        let tools = AIToolStore()
        let chat = AIChatStore(openRouter: router, tools: tools)
        let palette = AIChatSession(messages: [AIChatMessage(role: .user, text: "Palette-only context")])
        chat.replace(sessions: [palette], currentID: palette.id)
        let quick = QuickAIChatController(chat: chat, tools: tools, router: router, showSettings: {})
        quick.draft = "Quick question"
        router.isReady = false
        quick.submit()
        expect(quick.draft == "Quick question" && quick.sessionID == nil && chat.sessions.count == 1 && router.requests.isEmpty,
            "missing credentials keep the draft and create no request or conversation")
        router.isReady = true
        quick.submit()
        guard let quickID = quick.sessionID else { expect(false, "accepted send creates a floating session"); return }
        expect(quick.isExpanded && quick.draft.isEmpty && quick.notice == nil,
            "only an accepted first send expands the floating chat and clears its composer")
        let initialHeight = quick.bodyHeight
        expect(initialHeight < Theme.Size.panelHeight / 2, "the first send opens a compact conversation rather than maximum height")
        quick.updateTranscriptSize(CGSize(width: Theme.Size.quickAIWidth, height: 900), sessionID: quickID)
        expect(quick.bodyHeight == initialHeight, "intermediate narrow-width measurements cannot prematurely maximize the chat")
        quick.updateTranscriptSize(CGSize(width: Theme.Size.quickAIWidth * 2, height: 120), sessionID: quickID)
        let grownHeight = quick.bodyHeight
        expect(grownHeight > initialHeight && grownHeight < Theme.Size.panelHeight,
            "rendered content grows the chat by the space actually needed")
        quick.updateTranscriptSize(CGSize(width: Theme.Size.quickAIWidth * 2, height: 80), sessionID: quickID)
        quick.updateTranscriptSize(CGSize(width: Theme.Size.quickAIWidth * 2, height: 900), sessionID: UUID())
        expect(quick.bodyHeight == grownHeight, "status removal and stale sessions cannot resize the current conversation")
        quick.updateTranscriptSize(CGSize(width: Theme.Size.quickAIWidth * 2, height: 900), sessionID: quickID)
        expect(quick.bodyHeight == Theme.Size.panelHeight, "long replies stop growing at the existing maximum height")
        expect(chat.currentID == palette.id && chat.messages == palette.messages,
            "the floating chat does not replace the palette's selected conversation")
        await waitUntil { router.requests.count == 1 }
        expect(router.requests[0].map(\.content).last == "Quick question"
            && !router.requests[0].contains { $0.content == "Palette-only context" },
            "the model receives only the owning floating conversation")
        expect(chat.messages(in: quickID).last?.text == "Partial " && chat.messages == palette.messages,
            "streaming output stays scoped to the session that asked")
        expect(!chat.send("Competing palette prompt"), "the two surfaces share one in-flight request gate")
        quick.draft = "Follow up"
        quick.submit()
        quick.hide()
        expect(quick.draft == "Follow up" && quick.sessionID == quickID && chat.isWaiting,
            "busy sends and closing retain the draft, conversation and ongoing reply")
        router.completeNext()
        await waitUntil { !chat.isWaiting }
        expect(chat.messages(in: quickID).map(\.text) == ["Quick question", "Partial answer"],
            "a reply completed while closed lands in the same history session")
        quick.submit()
        await waitUntil { router.requests.count == 2 }
        expect(router.requests[1].map(\.content).suffix(3) == ["Quick question", "Partial answer", "Follow up"],
            "follow-ups carry the previous user and assistant turns")
        chat.stop()
        router.completeNext()
        await Task.yield()
        expect(chat.messages(in: quickID).last?.text == "Partial " && !chat.isWaiting,
            "Stop retains partial text and rejects cancelled completion")
        quick.newConversation()
        expect(quick.bodyHeight == Theme.Size.quickAIComposerHeight, "New Chat clears the attained height")
        expect(!quick.isExpanded && quick.sessionID == nil && chat.historySessions.contains { $0.id == quickID },
            "New Chat returns to the compact composer while keeping the previous conversation in history")
        expect(!chat.send("Missing session", sessionID: UUID()) && !chat.isWaiting,
            "a stale session reference cannot dispatch a request")
    }
}
