import Combine
import Foundation

/// One conversation in the session menu.
struct AIChatSession: Identifiable, Equatable, Sendable {
    let id: UUID
    var messages: [AIChatMessage]
    let startedAt: Date
    let titleOverride: String?
    let systemPrompt: String?

    init(
        id: UUID = UUID(), messages: [AIChatMessage] = [], startedAt: Date = Date(),
        titleOverride: String? = nil, systemPrompt: String? = nil
    ) {
        self.id = id
        self.messages = messages
        self.startedAt = startedAt
        self.titleOverride = titleOverride
        self.systemPrompt = systemPrompt
    }

    var title: String { titleOverride ?? AIChatEngine.sessionTitle(for: messages) }
}

/// The palette conversations: a stack of sessions, the current one, and the one in-flight request.
/// Session-only by design — nothing is persisted, and Quit is the privacy story. `AppCore` owns the
/// single instance.
@MainActor
final class AIChatStore: ObservableObject {
    enum Phase: Equatable {
        case idle
        case waiting
        case failed(String)
    }

    @Published private(set) var sessions: [AIChatSession]
    @Published private(set) var currentID: UUID
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var translationPrompt: String
    @Published private(set) var definitionPrompt: String
    @Published private(set) var grammarPrompt: String
    /// Which session the in-flight request belongs to, so a reply lands in the session that asked
    /// even if the user switched away, and the waiting row only shows where it applies.
    @Published private(set) var waitingSessionID: UUID?

    private let openRouter: OpenRouterStore
    private let defaults: UserDefaults
    private var task: Task<Void, Never>?
    // Keep the existing keys so prompt customizations survive the ownership move from Selection Tools.
    private static let translationPromptKey = "selection-tools.translation-prompt"
    private static let definitionPromptKey = "selection-tools.definition-prompt"
    private static let grammarPromptKey = "selection-tools.grammar-prompt"

    init(openRouter: OpenRouterStore, defaults: UserDefaults = .standard) {
        self.openRouter = openRouter
        self.defaults = defaults
        let first = AIChatSession()
        sessions = [first]
        currentID = first.id
        translationPrompt = defaults.string(forKey: Self.translationPromptKey)
            ?? AIChatSelectionPrompts.defaultTranslation
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
            if waitingSessionID != currentID { phase = .idle }
            return
        }
        replaceEmptySession(with: AIChatSession())
    }

    func switchTo(_ id: UUID) {
        guard sessions.contains(where: { $0.id == id }) else { return }
        currentID = id
        // The failure banner belongs to the conversation that failed, not whichever is shown.
        phase = waitingSessionID == id ? .waiting : .idle
    }

    func deleteCurrentSession() {
        stop()
        sessions.removeAll { $0.id == currentID }
        if sessions.isEmpty { sessions = [AIChatSession()] }
        currentID = orderedSessions[0].id
        phase = .idle
    }

    // MARK: - Sending

    /// Appends the turn and asks; a selected-text action may override the model for its first turn.
    @discardableResult
    func send(_ text: String, model: String? = nil, webSearch: Bool? = nil) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, phase != .waiting, isReady else { return false }
        let sessionID = currentID
        append(AIChatMessage(role: .user, text: trimmed), to: sessionID)
        phase = .waiting
        waitingSessionID = sessionID
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
    func startSelectionConversation(
        action: AIChatSelectionAction, text: String, detectedSourceLanguage: String?
    ) {
        stop()
        let prompt: String
        let model: String
        switch action {
        case .translate:
            let target = AIChatSelectionPrompts.targetLanguage(
                preferred: Locale.preferredLanguages,
                detectedSource: detectedSourceLanguage)
            let targetName = Locale(identifier: "en").localizedString(forLanguageCode: target)
                ?? target
            prompt = AIChatSelectionPrompts.translation(
                template: translationPrompt, targetLanguageName: targetName)
            model = openRouter.translationModel
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
        phase = .failed(message)
    }

    func setTranslationPrompt(_ prompt: String) {
        guard prompt != translationPrompt else { return }
        translationPrompt = prompt
        persist(
            prompt, key: Self.translationPromptKey,
            defaultPrompt: AIChatSelectionPrompts.defaultTranslation)
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
        waitingSessionID = nil
        if phase == .waiting { phase = .idle }
    }

    private func append(_ message: AIChatMessage, to sessionID: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].messages.append(message)
    }

    private func finishRequest(for sessionID: UUID, failure: String?) {
        waitingSessionID = nil
        // Only surface the outcome where the user is looking; a background session stays quiet.
        guard currentID == sessionID else { return }
        phase = failure.map(Phase.failed) ?? .idle
    }

    private func replaceEmptySession(with session: AIChatSession) {
        sessions.removeAll { $0.messages.isEmpty }
        sessions.append(session)
        currentID = session.id
        phase = .idle
    }

    private func persist(_ prompt: String, key: String, defaultPrompt: String) {
        if prompt == defaultPrompt {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(prompt, forKey: key)
        }
    }
}
