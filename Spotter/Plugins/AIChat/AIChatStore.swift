import Combine
import Foundation

/// Chat conversations join settings sync while the in-flight request ledger stays process-local.
@MainActor
final class AIChatStore: ObservableObject {
    @Published private(set) var sessions: [AIChatSession]
    @Published private(set) var currentID: UUID
    @Published private(set) var requests = AIChatRequestLedger()
    private let openRouter: OpenRouterStore
    private let localAI: LocalAIStore
    private let tools: AIToolStore
    private var task: Task<Void, Never>?
    @Published private(set) var streamingReply: AIChatMessage?
    @Published private(set) var isChoosingModel = false
    @Published private(set) var routingSelection: AIRoutingSelection?
    @Published private(set) var pendingAttachments: [AIChatMessage.Attachment] = []
    private var pendingReply = ""
    private var replyID = UUID()
    private var revealTask: Task<Void, Never>?
    private var backgroundTaskID: UUID?
    /// The session ID rides along so the launcher row can offer a way back into that conversation,
    /// and so a reply that lands while the user is already reading it needs no row at all.
    var onRequestStarted: ((UUID, String) -> UUID)?
    var onRequestFinished: ((UUID, UUID, Bool, String) -> Void)?
    var onRequestCancelled: ((UUID) -> Void)?

    init(openRouter: OpenRouterStore, localAI: LocalAIStore, tools: AIToolStore) {
        self.openRouter = openRouter
        self.localAI = localAI
        self.tools = tools
        let first = AIChatSession()
        sessions = [first]
        currentID = first.id
    }

    var isReady: Bool { openRouter.isReady || localAI.isAvailable }

    var current: AIChatSession {
        sessions.first { $0.id == currentID } ?? sessions[0]
    }

    var messages: [AIChatMessage] {
        messages(in: currentID)
    }

    func messages(in sessionID: UUID) -> [AIChatMessage] {
        let saved = sessions.first { $0.id == sessionID }?.messages ?? []
        guard waitingSessionID == sessionID, let streamingReply else { return saved }
        return saved + [streamingReply]
    }

    var phase: AIChatPhase { requests.phase(for: currentID) }

    var isWaiting: Bool { requests.waitingSessionID != nil }

    var waitingSessionID: UUID? { requests.waitingSessionID }

    var waitingStatus: String {
        if isChoosingModel { return "Jev is choosing a model…" }
        return streamingReply == nil ? "Waiting for reply…" : "Generating reply…"
    }

    var lastAssistantReply: String? {
        messages.last { $0.role == .assistant }?.text
    }

    /// The current conversation as copyable text.
    var transcript: String {
        messages.map { ($0.role == .user ? "You: " : "Assistant: ") + $0.text }
            .joined(separator: "\n\n")
    }

    func addPendingAttachments(_ attachments: [AIChatMessage.Attachment]) {
        let existing = Set(pendingAttachments.map { $0.name + "\u{0}" + $0.content })
        pendingAttachments.append(contentsOf: attachments.filter { !existing.contains($0.name + "\u{0}" + $0.content) })
    }

    func removePendingAttachment(id: UUID) {
        pendingAttachments.removeAll { $0.id == id }
    }

    func clearPendingAttachments() { pendingAttachments = [] }

    /// Sessions for the menu, newest first, the empty current one included (it reads "New Session").
    var orderedSessions: [AIChatSession] {
        sessions.sorted { $0.startedAt > $1.startedAt }
    }

    /// Rows visible on the empty-session History surface.
    var historySessions: [AIChatSession] {
        AIChatEngine.historySessions(sessions)
    }

    /// The root palette reads this same predicate as the view so its flat selection count always
    /// matches the rows actually on screen.
    var showsHistory: Bool {
        isReady && messages.isEmpty && phase == .idle && !isWaiting && !historySessions.isEmpty
    }

    // MARK: - Sessions

    // A floating conversation shares history without changing the palette's selected session.
    func createSession() -> UUID {
        let session = AIChatSession()
        sessions.append(session)
        return session.id
    }

    /// Tab's contract: every entry into chat is a fresh session. An already-empty current session is
    /// reused so cycling through the modes can't pile up blank sessions.
    func startNewSession() {
        if current.messages.isEmpty, current.titleOverride == nil, current.systemPrompt == nil {
            return
        }
        replaceEmptySession(with: AIChatSession())
    }

    func switchTo(_ id: UUID) {
        guard sessions.contains(where: { $0.id == id }) else { return }
        currentID = id
    }

    func deleteCurrentSession() {
        let deletedID = currentID
        if waitingSessionID == deletedID { stop() }
        sessions.removeAll { $0.id == currentID }
        requests.remove(sessionID: deletedID)
        if sessions.isEmpty { sessions = [AIChatSession()] }
        currentID = orderedSessions[0].id
    }

    /// An active local request wins so sync cannot detach its executor from the owning session.
    @discardableResult
    func replace(sessions newSessions: [AIChatSession], currentID newCurrentID: UUID?) -> Bool {
        guard !isWaiting else { return false }
        let usable = newSessions.filter { session in
            session.messages.allSatisfy { !$0.text.isEmpty }
        }
        sessions = usable.isEmpty ? [AIChatSession()] : usable
        if let newCurrentID, sessions.contains(where: { $0.id == newCurrentID }) {
            currentID = newCurrentID
        } else {
            currentID = sessions.max(by: { $0.startedAt < $1.startedAt })!.id
        }
        requests = AIChatRequestLedger()
        return true
    }

    // MARK: - Sending

    /// Appends the turn and asks; a selected-text action may override the model for its first turn.
    @discardableResult
    func send(_ text: String, model: String? = nil, webSearch: Bool? = nil, allowsTools: Bool = true,
        sessionID: UUID? = nil, commandInput: AIChatMessage.CommandInput? = nil,
        attachments suppliedAttachments: [AIChatMessage.Attachment]? = nil) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, isReady else { return false }
        let sessionID = sessionID ?? currentID
        guard let session = sessions.first(where: { $0.id == sessionID }) else { return false }
        guard requests.begin(sessionID: sessionID) else { return false }
        let attachments = suppliedAttachments ?? pendingAttachments
        append(AIChatMessage(role: .user, text: trimmed, commandInput: commandInput,
            attachments: attachments), to: sessionID)
        if suppliedAttachments == nil { pendingAttachments = [] }
        // Named after the turn just appended, so the row carries the question rather than a label.
        let sessionTitle = title(of: sessionID)
        backgroundTaskID = onRequestStarted?(sessionID, sessionTitle)
        let window = AIChatEngine.transcriptWindow(messages(in: sessionID))
        let sessionPrompt = session.systemPrompt
        let pinnedModel = model.flatMap { value -> String? in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let requestModel = pinnedModel ?? openRouter.chatModel
        let requestWebSearch = webSearch ?? openRouter.chatWebSearch
        let usesTools = allowsTools && tools.isConfigured
        pendingReply = ""
        streamingReply = nil
        routingSelection = nil
        isChoosingModel = pinnedModel == nil
        replyID = UUID()
        let expectedReply = replyID
        revealTask?.cancel()
        revealTask = nil
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let systemPrompt = [AIChatEngine.systemPrompt, sessionPrompt]
                    .compactMap { $0 }
                    .joined(separator: "\n\n")
                let turns =
                    [(role: "system", content: systemPrompt)]
                    + window.map { (role: $0.role.rawValue, content: $0.modelText) }
                let routingTurns = AIChatEngine.routingMessages(messages(in: sessionID))
                let selection: AIRoutingSelection?
                if pinnedModel != nil {
                    selection = nil
                } else if openRouter.isReady {
                    selection = try await openRouter.selectChatModel(messages: routingTurns, defaultModel: requestModel)
                } else {
                    let fallback = openRouter.aiRouting.everydayModel
                    guard LocalAIModel.resolve(fallback) != nil else { throw OpenRouterError.notConfigured }
                    selection = AIRoutingSelection(model: fallback, category: .everyday, fallback: .unavailable)
                }
                try Task.checkCancellation()
                guard waitingSessionID == sessionID, replyID == expectedReply else { throw CancellationError() }
                routingSelection = selection
                isChoosingModel = false
                let selectedModel = routingSelection?.model ?? requestModel
                let receive: @MainActor @Sendable (String) -> Void = { [weak self] delta in
                    guard !Task.isCancelled, let self, self.waitingSessionID == sessionID else { return }
                    self.pendingReply += delta
                    if self.streamingReply == nil { self.publishReveal() }
                    self.startReveal(for: sessionID)
                }
                if LocalAIModel.resolve(selectedModel) != nil {
                    try await localAI.chat(messages: turns, modelID: selectedModel, onDelta: receive)
                } else if usesTools {
                    try await tools.run(messages: turns, model: selectedModel, webSearch: requestWebSearch,
                        sessionID: sessionID, router: openRouter, onText: receive)
                } else {
                    try await openRouter.chat(messages: turns, model: selectedModel, webSearch: requestWebSearch, onDelta: receive)
                }
                guard !Task.isCancelled else { return }
                self.finishRequest(for: sessionID, failure: nil)
            } catch is CancellationError {
                if !Task.isCancelled { self.stop() }
            } catch {
                guard !Task.isCancelled else { return }
                self.finishRequest(for: sessionID, failure: error.localizedDescription)
                AppLog.error("ai-chat", "Reply failed: \(error.localizedDescription)")
            }
        }
        return true
    }

    // Keep the full rendered prompt in model context while the transcript presents only the command input.
    @discardableResult
    func startCommandConversation(command: AICommand, selection: String, selectInPalette: Bool = true) -> UUID {
        stop()
        let session = createCommandSession(command, selectInPalette: selectInPalette)
        _ = send(
            command.rendered(selection: selection),
            model: command.resolvedModel(),
            webSearch: false, allowsTools: false, sessionID: session.id,
            commandInput: .init(name: command.name, text: selection))
        return session.id
    }

    @discardableResult
    func showCommandFailure(command: AICommand, message: String, selectInPalette: Bool = true) -> UUID {
        stop()
        let session = createCommandSession(command, selectInPalette: selectInPalette)
        requests.setFailure(message, for: session.id)
        return session.id
    }

    private func createCommandSession(_ command: AICommand, selectInPalette: Bool) -> AIChatSession {
        let session = AIChatSession(titleOverride: command.sessionTitle, sourceSystemImage: command.systemImage)
        if selectInPalette { replaceEmptySession(with: session) }
        else { sessions.append(session) }
        return session
    }

    /// Stops the in-flight request; the sent turn stays so the user can see what went unanswered.
    func stop() {
        task?.cancel()
        isChoosingModel = false
        tools.stop()
        if let sessionID = waitingSessionID { commitStream(to: sessionID) }
        task = nil
        if let backgroundTaskID { onRequestCancelled?(backgroundTaskID) }
        backgroundTaskID = nil
        requests.cancel()
    }

    private func append(_ message: AIChatMessage, to sessionID: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].messages.append(message)
    }

    private func publishReveal() {
        streamingReply = AIChatMessage(id: replyID, role: .assistant, text: pendingReply, routing: routingSelection)
    }

    private func startReveal(for sessionID: UUID) {
        guard revealTask == nil else { return }
        let expectedReply = replyID
        revealTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(33)) }
            catch { return }
            guard !Task.isCancelled, let self,
                self.waitingSessionID == sessionID, self.replyID == expectedReply else { return }
            self.publishReveal()
            self.revealTask = nil
        }
    }

    // Persist once on completion, failure or Stop; token updates never rewrite the settings-sync file.
    private func commitStream(to sessionID: UUID) {
        revealTask?.cancel()
        revealTask = nil
        if !pendingReply.isEmpty {
            append(AIChatMessage(id: replyID, role: .assistant, text: pendingReply, routing: routingSelection), to: sessionID)
        }
        pendingReply = ""
        streamingReply = nil
    }

    private func finishRequest(for sessionID: UUID, failure: String?) {
        guard waitingSessionID == sessionID else { return }
        isChoosingModel = false
        commitStream(to: sessionID)
        guard requests.finish(sessionID: sessionID, failure: failure) else { return }
        task = nil
        guard let backgroundTaskID else { return }
        self.backgroundTaskID = nil
        // The row is titled with the conversation, so its status says only what happened.
        onRequestFinished?(
            backgroundTaskID, sessionID, failure == nil,
            failure ?? AIChatEngine.replyReadyStatus)
    }

    private func title(of sessionID: UUID) -> String {
        sessions.first { $0.id == sessionID }?.title ?? AIChatEngine.untitledSessionTitle
    }

    private func replaceEmptySession(with session: AIChatSession) {
        let removedIDs = sessions.filter(\.messages.isEmpty).map(\.id)
        sessions.removeAll { $0.messages.isEmpty }
        for id in removedIDs { requests.remove(sessionID: id) }
        sessions.append(session)
        currentID = session.id
    }
}
