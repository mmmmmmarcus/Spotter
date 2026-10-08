import AppKit
import Combine
import SwiftUI

@MainActor
final class OpenRouterStore: ObservableObject {
    var isReady = true
    var chatModel = "fixture-model"
    var chatWebSearch = false
    var aiRouting = AIRoutingPreferences()
    var route = AIRoutingSelection(model: "chosen-model", category: .professional)
    var decisionRequests: [[(role: String, content: String)]] = []
    var waitsForDecision = false
    var ignoresDecisionCancellation = false
    private var decisions: [CheckedContinuation<Void, Error>] = []
    var models: [String] = []
    var requests: [[(role: String, content: String)]] = []
    private var completions: [CheckedContinuation<Void, Error>] = []

    func selectChatModel(messages: [(role: String, content: String)], defaultModel: String, routeModel: Bool = true) async throws -> AIRoutingSelection? {
        if !routeModel { return AIRoutingSelection(model: defaultModel, category: nil, webSearch: false) }
        decisionRequests.append(messages)
        if waitsForDecision { try await withCheckedThrowingContinuation { decisions.append($0) } }
        if !ignoresDecisionCancellation { try Task.checkCancellation() }
        return route
    }

    func completeDecision() { decisions.removeFirst().resume() }

    func chat(messages: [(role: String, content: String)], model: String, webSearch: Bool, imageDataURLs: [Int: [String]] = [:],
              onDelta: @escaping @MainActor @Sendable (String) -> Void) async throws {
        requests.append(messages)
        models.append(model)
        onDelta("Partial ")
        try await withCheckedThrowingContinuation { completions.append($0) }
        try Task.checkCancellation()
        onDelta("answer")
    }

    func completeNext() { completions.removeFirst().resume() }
}

enum OpenRouterError: Error { case notConfigured }

enum LocalAIModel {
    static func resolve(_ id: String) -> LocalAIModel? { nil }
}

@MainActor
final class LocalAIStore: ObservableObject {
    var isAvailable = false
    func chat(messages: [(role: String, content: String)], modelID: String, webSearch: Bool = false, images: [Data] = [],
              onDelta: @escaping @MainActor @Sendable (String) -> Void) async throws {
        throw OpenRouterError.notConfigured
    }
}

@MainActor
final class AIToolStore: ObservableObject {
    var isConfigured = false
    func stop() {}
    func run(messages: [(role: String, content: String)], model: String, webSearch: Bool,
             sessionID: UUID, router: OpenRouterStore, imageDataURLs: [Int: [String]] = [:], onText: @escaping @MainActor @Sendable (String) -> Void) async throws {
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
        await nativePanel()
        headerDragging()
        await conversations()
        await sidebarSessions()
        await routing()
        await commandConversations()
        print("\(passes)/\(passes + failures) passed")
        if failures > 0 { exit(1) }
    }

    private static func commandConversations() async {
        let router = OpenRouterStore()
        let tools = AIToolStore()
        let chat = AIChatStore(openRouter: router, localAI: LocalAIStore(), tools: tools)
        let quick = QuickAIChatController(chat: chat, tools: tools, router: router, showSettings: {})
        let command = AICommand(name: "Explain", prompt: "Explain this clearly: {selection}", model: "command-model")
        let input = "A selection with {selection} and\na second line"
        let commandID = chat.startCommandConversation(command: command, selection: input, selectSession: false)
        quick.draft = "An unsent draft"
        quick.openSession(commandID)
        expect(chat.currentID == commandID && quick.owns(commandID) && quick.isExpanded && !quick.hasReceivedReply,
            "commands open at the first expansion and become the selected session")
        expect(quick.draft.isEmpty, "a command session does not inherit another composer draft")
        quick.newConversation()
        expect(quick.draft == "An unsent draft", "the new-conversation draft survives a command detour")
        quick.openSession(commandID)
        expect(chat.messages(in: commandID).first?.displayedText == input
            && chat.messages(in: commandID).first?.commandInput?.name == "Explain",
            "command bubbles retain just the selected input and the command name")
        await waitUntil { router.requests.count == 1 }
        expect(router.requests[0].last?.content == command.rendered(selection: input)
            && router.models == ["command-model"] && quick.hasReceivedReply,
            "floating commands send the full rendered prompt using their pinned model and expand on reply")
        router.completeNext()
        await waitUntil { !chat.isWaiting }
        chat.send("Explain more", sessionID: commandID)
        await waitUntil { router.requests.count == 2 }
        expect(router.requests[1].contains { $0.content == command.rendered(selection: input) }
            && chat.messages(in: commandID).dropLast().last?.commandInput == nil,
            "follow-ups keep command instructions in context and remain ordinary chat bubbles")
        router.completeNext()
        await waitUntil { !chat.isWaiting }
        let failedID = chat.showCommandFailure(command: command, message: "No selected text", selectSession: false)
        quick.openSession(failedID)
        expect(chat.currentID == failedID && quick.owns(failedID) && !quick.hasReceivedReply
            && chat.requests.phase(for: failedID) == .failed("No selected text"),
            "command capture failures stay in their owning session")
        let mainID = chat.startCommandConversation(command: command, selection: "Palette input")
        expect(chat.currentID == mainID, "a directly created command can select its session")
        await waitUntil { router.requests.count == 3 }
        router.completeNext()
        await waitUntil { !chat.isWaiting }
    }

    private static func layout() {
        let visible = CGRect(x: -1440, y: 172, width: 1440, height: 800)
        let compact = QuickAIChatLayout.initialFrame(size: CGSize(width: Theme.Size.quickAIWidth, height: Theme.Size.quickAIComposerHeight),
            visibleFrame: visible, bottomGap: 20, margin: 8)
        expect(compact.midX == visible.midX && compact.minY == 192,
            "the compact bar centers above the Dock's reserved visible-screen edge")
        let expanded = QuickAIChatLayout.resizedFrame(compact, width: compact.width * 2, height: 475, visibleFrame: visible, margin: 8)
        expect(expanded.minY == compact.minY && expanded.midX == compact.midX && expanded.width == compact.width * 2,
            "expansion doubles the width around the composer center and keeps the bottom position")
        expect(expanded.height == 475, "the conversation gets the requested expanded height")
        let dragged = compact.offsetBy(dx: -60, dy: 100)
        let afterDrag = QuickAIChatLayout.resizedFrame(dragged, width: compact.width * 2, height: 475, visibleFrame: visible, margin: 8)
        expect(afterDrag.midX == dragged.midX && afterDrag.minY == dragged.minY, "a dragged composer expands at its new position")
        let nearTop = compact.offsetBy(dx: 500, dy: 600)
        let clamped = QuickAIChatLayout.resizedFrame(nearTop, width: compact.width * 2, height: 475, visibleFrame: visible, margin: 8)
        expect(visible.insetBy(dx: 8, dy: 8).contains(clamped) && clamped.width == compact.width * 2,
            "expansion after dragging to an edge keeps the close button and entire frame on screen")
        let withSidebar = QuickAIChatLayout.resizedFrame(expanded,
            width: expanded.width + Theme.QuickAI.sidebarWidth, height: expanded.height,
            visibleFrame: visible, margin: 8, anchorTrailing: true)
        expect(withSidebar.maxX == expanded.maxX && withSidebar.width - Theme.QuickAI.sidebarWidth == expanded.width,
            "sidebar grows leftward while preserving the conversation width and trailing edge")
        let withoutSidebar = QuickAIChatLayout.resizedFrame(withSidebar,
            width: expanded.width, height: expanded.height, visibleFrame: visible, margin: 8, anchorTrailing: true)
        expect(withoutSidebar == expanded, "closing the sidebar restores the same conversation frame")
        let restored = QuickAIChatLayout.resizedFrame(expanded, width: compact.width, height: Theme.Size.quickAIComposerHeight, visibleFrame: visible, margin: 8)
        expect(restored == compact, "starting another chat collapses onto the same composer anchor")
        let small = CGRect(x: 200, y: -600, width: 500, height: 400)
        let bounded = QuickAIChatLayout.initialFrame(size: CGSize(width: Theme.Size.quickAIWidth * 2, height: 475),
            visibleFrame: small, bottomGap: 20, margin: 8)
        expect(small.insetBy(dx: 8, dy: 8).contains(bounded), "small secondary displays cannot strand the panel offscreen")
    }

    private static func nativePanel() async {
        _ = NSApplication.shared
        let savedAppearance = NSApp.appearance
        defer { NSApp.appearance = savedAppearance }
        NSApp.appearance = NSAppearance(named: .aqua)
        let panel = QuickAIChatPanel(rootView: Text("Fixture"), size: CGSize(width: Theme.Size.quickAIWidth, height: Theme.Size.quickAIComposerHeight), cornerRadius: 26)
        panel.setFrameOrigin(CGPoint(x: -10000, y: -10000))
        expect(panel.canBecomeKey && !panel.canBecomeMain && panel.styleMask.contains(.nonactivatingPanel),
            "the floating composer accepts typing without becoming a main application window")
        expect(panel.level == .floating && !panel.hidesOnDeactivate && !panel.isMovableByWindowBackground,
            "the chat stays floating without making the transcript or composer draggable")
        expect(panel.glassView.style == .regular && panel.glassView.cornerRadius == 16
            && panel.effectiveAppearance.isDark,
            "light system appearance gives the floating glass a dark backdrop")
        NSApp.appearance = NSAppearance(named: .darkAqua)
        await waitUntil { !panel.effectiveAppearance.isDark }
        expect(!panel.effectiveAppearance.isDark, "an open floating panel switches to white glass and dark text in dark mode")
        NSApp.appearance = NSAppearance(named: .aqua)
        await waitUntil { panel.effectiveAppearance.isDark }
        expect(panel.effectiveAppearance.isDark, "switching back to light mode restores the dark floating surface")
        for symbol in ["arrow.trianglehead.branch", "ellipsis.bubble", "text.line.first.and.arrowtriangle.forward",
                       "network", "brain", "hand.raised", "wrench.and.screwdriver"] {
            expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil,
                "the progress symbol exists: \(symbol)")
        }
        expect(panel.hasShadow && panel.glassView.layer?.masksToBounds == true
            && panel.glassView.layer?.cornerRadius == 16 && panel.glassView.layer?.cornerCurve == .circular,
            "the native window shadow is enabled while the glass backing keeps its capsule silhouette")
        let host = panel.contentView?.subviews.compactMap { $0 as? NSHostingView<Text> }.first
        expect(host?.sizingOptions == [], "SwiftUI cannot drive the window size")
        panel.setFrame(CGRect(x: -10000, y: -10000, width: Theme.Size.quickAIWidth * 2, height: 475), display: false)
        panel.contentView?.layoutSubtreeIfNeeded()
        expect(panel.glassView.frame == CGRect(x: 0, y: 0, width: Theme.Size.quickAIWidth * 2, height: 475),
            "the native glass fills the window without a handle strip")
        expect(panel.glassView.cornerRadius == 26 && panel.glassView.layer?.cornerRadius == 26
            && panel.glassView.layer?.cornerCurve == .continuous,
            "the expanded chat restores its larger continuous window corners")
        expect(host?.frame.size == CGSize(width: Theme.Size.quickAIWidth * 2, height: 475),
            "the transcript host follows the glass content size")
        expect(panel.contentView?.subviews.count == 2, "glass backing and full-window content are separate without a drag handle")
        for height: CGFloat in [44, 32] {
            panel.setFrame(CGRect(x: -10000, y: -10000, width: Theme.Size.quickAIWidth,
                height: height), display: false)
            panel.contentView?.layoutSubtreeIfNeeded()
            expect(panel.glassView.cornerRadius == height / 2 && panel.glassView.layer?.cornerRadius == height / 2
                && panel.glassView.layer?.cornerCurve == .circular,
                "compact and transitional heights use matching half-height circular ends")
        }
        panel.setFrame(CGRect(x: -10000, y: -10000,
            width: Theme.Size.quickAIWidth + Theme.QuickAI.compactAccessoryWidth,
            height: Theme.Size.quickAIComposerHeight), display: false)
        panel.compactAccessoryWidth = Theme.QuickAI.compactAccessoryWidth
        panel.contentView?.layoutSubtreeIfNeeded()
        expect(panel.glassView.frame.minX == Theme.QuickAI.compactAccessoryWidth
            && panel.glassView.frame.width == Theme.Size.quickAIWidth,
            "compact glass starts after the external circular button and transparent gap")
        expect(host?.frame.width == panel.contentView?.bounds.width,
            "the content host keeps the external sidebar button outside the composer's clip")
        panel.compactAccessoryWidth = 0
        expect(panel.glassView.frame.minX == 0, "expanded glass reclaims the full panel width")
        expect(panel.collectionBehavior.contains(.managed) && panel.collectionBehavior.contains(.participatesInCycle)
            && !panel.collectionBehavior.contains(.transient), "Quick AI Chat participates in Mission Control and window cycling")
        expect(!panel.isVisible, "native panel checks never show a window or take user focus")
        panel.close()
    }

    private static func headerDragging() {
        let window = DragProbeWindow(contentRect: CGRect(x: -10000, y: -10000, width: 200, height: 80),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let area = QuickAIChatDragView(frame: CGRect(x: 44, y: 20, width: 112, height: 24))
        window.contentView?.addSubview(area)
        let event = NSEvent.mouseEvent(with: .leftMouseDown, location: CGPoint(x: 80, y: 32), modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        expect(area.acceptsFirstMouse(for: event), "header dragging works when the floating panel is inactive")
        expect(window.contentView?.hitTest(CGPoint(x: 80, y: 32)) === area,
            "the empty header area receives pointer events")
        let previousCursor = NSCursor.current
        area.mouseDown(with: event)
        expect(NSCursor.current === NSCursor.closedHand && !window.areCursorRectsEnabled,
            "native drag retains a closed hand after performDrag returns")
        area.mouseUp(with: event)
        expect(NSCursor.current === previousCursor && window.areCursorRectsEnabled,
            "mouse release restores the cursor and window cursor rectangles")
        let cursor = WindowDragCursor()
        cursor.begin(in: area)
        cursor.update(isPressed: false)
        cursor.end()
        expect(NSCursor.current === previousCursor && window.areCursorRectsEnabled,
            "a consumed mouse-up restores the cursor exactly once")
        let handle = PaletteDragHandleView()
        window.contentView?.addSubview(handle)
        var clicks = 0
        handle.onClick = { clicks += 1 }
        handle.mouseDown(with: event)
        expect(NSCursor.current === NSCursor.closedHand, "palette uses a closed hand from mouse-down")
        handle.mouseUp(with: event)
        expect(clicks == 1 && NSCursor.current === previousCursor, "palette click still recenters and restores the cursor")
        area.mouseDown(with: event)
        area.removeFromSuperview()
        expect(NSCursor.current === previousCursor && window.areCursorRectsEnabled,
            "removing a dragging view restores cursor state")
        expect(window.dragEvents == 2 && !window.isVisible, "header dragging uses the native window drag without showing a test window")
        window.close()
    }

    private static func conversations() async {
        let router = OpenRouterStore()
        let tools = AIToolStore()
        let chat = AIChatStore(openRouter: router, localAI: LocalAIStore(), tools: tools)
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
        expect(!quick.hasReceivedReply, "sending alone does not trigger the second expansion")
        expect(chat.messages(in: quickID).first?.text == "Quick question" && chat.waitingStatus == "Jev is choosing a model…",
            "the first expansion already has the submitted prompt and an accurate waiting status")
        expect(chat.currentID == quickID && chat.messages(in: palette.id) == palette.messages,
            "Quick Chat selects its session without changing historical messages")
        await waitUntil { router.requests.count == 1 }
        expect(quick.hasReceivedReply && quick.bodyHeight == Theme.Size.panelHeight,
            "the first nonempty streamed reply immediately selects the final height")
        expect(router.requests[0].map(\.content).last == "Quick question"
            && !router.requests[0].contains { $0.content == "Palette-only context" },
            "the model receives only the owning floating conversation")
        expect(chat.waitingStatus == "Generating reply…", "received text advances the progress to generating")
        expect(chat.messages(in: quickID).last?.text == "Partial " && chat.messages(in: palette.id) == palette.messages,
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
        expect(quick.bodyHeight == Theme.Size.panelHeight, "follow-up sends keep the final size")
        await waitUntil { router.requests.count == 2 }
        expect(router.requests[1].map(\.content).suffix(3) == ["Quick question", "Partial answer", "Follow up"],
            "follow-ups carry the previous user and assistant turns")
        chat.stop()
        router.completeNext()
        await Task.yield()
        expect(chat.messages(in: quickID).last?.text == "Partial " && !chat.isWaiting,
            "Stop retains partial text and rejects cancelled completion")
        quick.newConversation()
        expect(!quick.hasReceivedReply, "New Chat resets the two-stage expansion")
        expect(quick.bodyHeight == Theme.Size.quickAIComposerHeight, "New Chat clears the attained height")
        expect(!quick.isExpanded && quick.sessionID == nil && chat.historySessions.contains { $0.id == quickID },
            "New Chat returns to the compact composer while keeping the previous conversation in history")
        quick.draft = "Old floating request"
        quick.submit()
        await waitUntil { router.requests.count == 3 }
        quick.newConversation()
        router.completeNext()
        await waitUntil { !chat.isWaiting }
        expect(!quick.isExpanded && !quick.hasReceivedReply && quick.bodyHeight == Theme.Size.quickAIComposerHeight,
            "a previous conversation finishing cannot expand the new composer")
        chat.send("Palette request")
        await waitUntil { router.requests.count == 4 }
        expect(!quick.hasReceivedReply, "a palette reply cannot expand the floating composer")
        router.completeNext()
        await waitUntil { !chat.isWaiting }
        expect(!chat.send("Missing session", sessionID: UUID()) && !chat.isWaiting,
            "a stale session reference cannot dispatch a request")
    }

    private static func sidebarSessions() async {
        let router = OpenRouterStore()
        let chat = AIChatStore(openRouter: router, localAI: LocalAIStore(), tools: AIToolStore())
        let tools = AIToolStore()
        let first = AIChatSession(messages: [AIChatMessage(role: .user, text: "First")])
        let second = AIChatSession(messages: [AIChatMessage(role: .user, text: "Second"),
            AIChatMessage(role: .assistant, text: "Answer")])
        chat.replace(sessions: [first, second], currentID: first.id)
        let quick = QuickAIChatController(chat: chat, tools: tools, router: router, showSettings: {})
        quick.draft = "Unsent new question"
        quick.toggleSidebar()
        expect(quick.showsSidebar && quick.isExpanded && quick.bodyHeight == Theme.Size.panelHeight,
            "history is reachable from a compact empty composer without creating a session")
        expect(chat.sessions.count == 2, "opening history creates no blank session")
        quick.openSession(first.id)
        quick.draft = "First draft"
        let attachment = AIChatMessage.Attachment(name: "first.txt", kind: .text, content: "First attachment")
        _ = chat.addPendingAttachments([attachment])
        quick.openSession(second.id)
        expect(chat.pendingAttachments.isEmpty, "attachments do not leak into another session")
        expect(quick.draft.isEmpty && quick.hasReceivedReply && chat.currentID == second.id,
            "switching sessions selects the matching transcript and attained size")
        quick.draft = "Second draft"
        quick.openSession(first.id)
        expect(quick.draft == "First draft" && chat.pendingAttachments == [attachment],
            "each session restores its own unsent draft and attachments")
        quick.newConversation()
        expect(quick.draft == "Unsent new question" && quick.showsSidebar,
            "returning to a new conversation restores its draft and keeps history open")
        quick.openSession(second.id)
        expect(quick.draft == "Second draft", "returning through new conversation preserves historical drafts")
        quick.draft = "Request in second"
        quick.submit()
        await waitUntil { router.requests.count == 1 }
        quick.openSession(first.id)
        router.completeNext()
        await waitUntil { !chat.isWaiting }
        expect(chat.messages(in: second.id).last?.text == "Partial answer"
            && chat.messages(in: first.id).count == 1 && quick.sessionID == first.id,
            "switching while a reply streams never redirects it to the selected transcript")
        quick.openSession(second.id)
        quick.draft = "Second draft"
        quick.deleteSession(first.id)
        expect(quick.sessionID == second.id && quick.draft == "Second draft" && chat.sessions.count == 1,
            "deleting an unselected session leaves the current draft intact")
        quick.deleteSession(second.id)
        expect(quick.sessionID == nil && quick.draft == "Unsent new question" && !chat.sessions.isEmpty,
            "deleting the selected last session returns to the new composer safely")
        quick.toggleSidebar()
        expect(!quick.isExpanded && quick.bodyHeight == Theme.Size.quickAIComposerHeight,
            "closing history on an empty composer returns to compact size")
    }

    private static func routing() async {
        let router = OpenRouterStore()
        router.waitsForDecision = true
        let tools = AIToolStore()
        let chat = AIChatStore(openRouter: router, localAI: LocalAIStore(), tools: tools)
        let quick = QuickAIChatController(chat: chat, tools: tools, router: router, showSettings: {})
        quick.draft = "Analyze this design"
        quick.submit()
        await waitUntil { router.decisionRequests.count == 1 }
        expect(chat.isChoosingModel && router.requests.isEmpty && !quick.hasReceivedReply,
            "routing holds the shared request gate without triggering reply expansion or a model call")
        expect(!chat.send("Competing prompt"), "routing is part of the one-request gate")
        router.completeDecision()
        await waitUntil { router.requests.count == 1 }
        expect(router.models == ["chosen-model"] && !chat.isChoosingModel && quick.hasReceivedReply,
            "the configured model answers only after Jev's decision")
        expect(chat.streamingReply?.routing == router.route, "streaming carries the selected category and model")
        router.completeNext()
        await waitUntil { !chat.isWaiting }
        expect(chat.sessions.first { $0.id == quick.sessionID }?.messages.last?.routing == router.route,
            "routing metadata persists on the owning floating conversation")

        router.waitsForDecision = false
        chat.send("Pinned", model: "pinned-model")
        await waitUntil { router.requests.count == 2 }
        expect(router.decisionRequests.count == 1 && router.models.last == "pinned-model" && chat.streamingReply?.routing == nil,
            "explicit model choices bypass Jev and do not inherit previous routing metadata")
        router.completeNext()
        await waitUntil { !chat.isWaiting }

        chat.startNewSession()
        tools.isConfigured = true
        router.route = AIRoutingSelection(model: "fallback-model", category: nil, fallback: .unavailable)
        chat.send("Follow up through tools")
        await waitUntil { router.requests.count == 3 }
        expect(router.models.last == "fallback-model" && chat.streamingReply?.routing?.fallback == .unavailable,
            "the selected fallback also reaches the existing tool path and is labelled")
        router.completeNext()
        await waitUntil { !chat.isWaiting }
        expect(router.decisionRequests.last?.map(\.content).contains("Follow up through tools") == true,
            "new session routing uses its own prompt")

        chat.startNewSession()
        router.waitsForDecision = true
        router.ignoresDecisionCancellation = true
        chat.send("Cancel while deciding")
        await waitUntil { router.decisionRequests.count == 3 }
        chat.stop()
        chat.send("Replacement request", model: router.chatModel)
        await waitUntil { router.requests.count == 4 }
        router.completeDecision()
        try? await Task.sleep(for: .milliseconds(20))
        expect(router.requests.count == 4 && router.models.last == router.chatModel && chat.streamingReply?.routing == nil,
            "a late cancelled decision cannot send another request or relabel a replacement reply")
        router.completeNext()
        await waitUntil { !chat.isWaiting }
    }
}

@MainActor
private final class DragProbeWindow: NSWindow {
    var dragEvents = 0
    override func performDrag(with event: NSEvent) { dragEvents += 1 }
}
