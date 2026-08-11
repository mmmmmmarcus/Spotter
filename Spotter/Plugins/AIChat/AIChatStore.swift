import Combine
import Foundation

/// Palette conversations join settings sync while the in-flight request ledger stays process-local.
@MainActor
final class AIChatStore: ObservableObject {
    @Published private(set) var sessions: [AIChatSession]
    @Published private(set) var currentID: UUID
    @Published private(set) var requests = AIChatRequestLedger()
    @Published private(set) var definitionPrompt: String
    @Published private(set) var grammarPrompt: String
    private let openRouter: OpenRouterStore
    private let defaults: UserDefaults
    private var task: Task<Void, Never>?
    private var backgroundTaskID: UUID?
    var onRequestStarted: ((String) -> UUID)?
    var onRequestFinished: ((UUID, Bool, String) -> Void)?
    var onRequestCancelled: ((UUID) -> Void)?
    // Keep the existing keys so prompt customizations survive the ownership move from Selection Tools.
    private static let definitionPromptKey = "selection-tools.definition-prompt"
    private static let grammarPromptKey = "selection-tools.grammar-prompt"

    init(openRouter: OpenRouterStore, defaults: UserDefaults = .standard) {
        self.openRouter = openRouter
        self.defaults = defaults
        let first = AIChatSession()
        sessions = [first]
        currentID = first.id
        definitionPrompt = defaults.string(forKey: Self.definitionPromptKey)
            ?? AIChatSelectionPrompts.defaultDefinition
        grammarPrompt = defaults.string(forKey: Self.grammarPromptKey)
            ?? AIChatSelectionPrompts.defaultGrammar
    }

    /// Mirrors the OpenRouter gate: no key, no chat (the key is the consent act).
    var isReady: Bool { openRouter.isReady }

    var current: AIChatSession {
        sessions.first { $0.id == currentID } ?? sessions[0]
    }

    var messages: [AIChatMessage] { current.messages }

    var phase: AIChatPhase { requests.phase(for: currentID) }

    var isWaiting: Bool { requests.waitingSessionID != nil }

    var waitingSessionID: UUID? { requests.waitingSessionID }

    var lastAssistantReply: String? {
        messages.last { $0.role == .assistant }?.text
    }

    /// The current conversation as copyable text.
    var transcript: String {
        messages.map { ($0.role == .user ? "You: " : "Assistant: ") + $0.text }
            .joined(separator: "\n\n")
    }

    /// Sessions for the menu, newest first, the empty current one included (it reads "New Session").
    var orderedSessions: [AIChatSession] {
        sessions.sorted { $0.startedAt > $1.startedAt }
    }

    // MARK: - Sessions

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
    func send(_ text: String, model: String? = nil, webSearch: Bool? = nil) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, isReady else { return false }
        let sessionID = currentID
        guard requests.begin(sessionID: sessionID) else { return false }
        append(AIChatMessage(role: .user, text: trimmed), to: sessionID)
        let sessionTitle = sessions.first { $0.id == sessionID }?.title ?? "AI Chat"
        backgroundTaskID = onRequestStarted?(sessionTitle)
        let window = AIChatEngine.transcriptWindow(messages)
        let sessionPrompt = current.systemPrompt
        let requestModel = model ?? openRouter.chatModel
        let requestWebSearch = webSearch ?? openRouter.chatWebSearch
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let systemPrompt = [AIChatEngine.systemPrompt, sessionPrompt]
                    .compactMap { $0 }
                    .joined(separator: "\n\n")
                let turns =
                    [(role: "system", content: systemPrompt)]
                    + window.map { (role: $0.role.rawValue, content: $0.text) }
                let reply = try await self.openRouter.chat(
                    messages: turns, model: requestModel, webSearch: requestWebSearch)
                guard !Task.isCancelled else { return }
                self.append(AIChatMessage(role: .assistant, text: reply), to: sessionID)
                self.finishRequest(for: sessionID, failure: nil)
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                self.finishRequest(for: sessionID, failure: error.localizedDescription)
                AppLog.error("ai-chat", "Reply failed: \(error.localizedDescription)")
            }
        }
        return true
    }

    /// Starts a dedicated conversation for a selected-text AI action. Its first answer uses the
    /// action's fast model; follow-ups use the normal chat model while retaining the action prompt.
    func startSelectionConversation(action: AIChatSelectionAction, text: String) {
        stop()
        let prompt: String
        let model: String
        switch action {
        case .define:
            prompt = definitionPrompt
            model = openRouter.definitionModel
        case .grammar:
            prompt = grammarPrompt
            model = openRouter.grammarModel
        }
        replaceEmptySession(
            with: AIChatSession(titleOverride: action.sessionTitle, systemPrompt: prompt))
        _ = send(text, model: model, webSearch: false)
    }

    func showSelectionFailure(action: AIChatSelectionAction, message: String) {
        stop()
        replaceEmptySession(with: AIChatSession(titleOverride: action.sessionTitle))
        requests.setFailure(message, for: currentID)
    }

    func setDefinitionPrompt(_ prompt: String) {
        guard prompt != definitionPrompt else { return }
        definitionPrompt = prompt
        persist(
            prompt, key: Self.definitionPromptKey,
            defaultPrompt: AIChatSelectionPrompts.defaultDefinition)
    }

    func setGrammarPrompt(_ prompt: String) {
        guard prompt != grammarPrompt else { return }
        grammarPrompt = prompt
        persist(
            prompt, key: Self.grammarPromptKey,
            defaultPrompt: AIChatSelectionPrompts.defaultGrammar)
    }

    /// Stops the in-flight request; the sent turn stays so the user can see what went unanswered.
    func stop() {
        task?.cancel()
        task = nil
        if let backgroundTaskID { onRequestCancelled?(backgroundTaskID) }
        backgroundTaskID = nil
        requests.cancel()
    }

    private func append(_ message: AIChatMessage, to sessionID: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].messages.append(message)
    }

    private func finishRequest(for sessionID: UUID, failure: String?) {
        guard requests.finish(sessionID: sessionID, failure: failure) else { return }
        task = nil
        guard let backgroundTaskID else { return }
        self.backgroundTaskID = nil
        let sessionTitle = sessions.first { $0.id == sessionID }?.title ?? "AI Chat"
        onRequestFinished?(
            backgroundTaskID, failure == nil,
            failure ?? "Reply ready in \(sessionTitle).")
    }

    private func replaceEmptySession(with session: AIChatSession) {
        let removedIDs = sessions.filter(\.messages.isEmpty).map(\.id)
        sessions.removeAll { $0.messages.isEmpty }
        for id in removedIDs { requests.remove(sessionID: id) }
        sessions.append(session)
        currentID = session.id
    }

    private func persist(_ prompt: String, key: String, defaultPrompt: String) {
        if prompt == defaultPrompt {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(prompt, forKey: key)
        }
    }
}
