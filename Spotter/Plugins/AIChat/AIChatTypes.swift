import Foundation

/// One turn of the palette conversation.
struct AIChatMessage: Identifiable, Equatable, Codable, Sendable {
    enum Role: String, Codable, Sendable {
        case user
        case assistant
    }

    struct CommandInput: Equatable, Codable, Sendable {
        let name: String
        let text: String
        var symbol: String? = nil
    }

    struct Attachment: Identifiable, Equatable, Codable, Sendable {
        enum Kind: String, Codable, Sendable { case text, image, pdf }
        let id: UUID
        let name: String
        let kind: Kind
        let content: String
        var imageData: Data? = nil

        init(id: UUID = UUID(), name: String, kind: Kind, content: String, imageData: Data? = nil) {
            self.id = id
            self.name = name
            self.kind = kind
            self.content = content
            self.imageData = imageData
        }
    }

    let id: UUID
    let role: Role
    let text: String
    let routing: AIRoutingSelection?
    let commandInput: CommandInput?
    let attachments: [Attachment]
    var displayedText: String { role == .user ? commandInput?.text ?? text : text }
    var modelText: String {
        guard !attachments.isEmpty else { return text }
        let documents = attachments.map { attachment in
            let name = attachment.name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.map(String.init).joined()
            let runs = attachment.content.split(whereSeparator: { $0 != "`" }).map(\.count)
            let fence = String(repeating: "`", count: max(3, (runs.max() ?? 0) + 1))
            return "Attachment: \(String(name.prefix(128))) (\(attachment.kind.rawValue))\n\(fence)\n\(attachment.content)\n\(fence)"

        }.joined(separator: "\n\n")
        return text + "\n\n" + documents
    }

    init(id: UUID = UUID(), role: Role, text: String, routing: AIRoutingSelection? = nil,
        commandInput: CommandInput? = nil, attachments: [Attachment] = []) {
        self.id = id
        self.role = role
        self.text = text
        self.routing = routing
        self.commandInput = commandInput
        self.attachments = attachments
    }

    private enum CodingKeys: String, CodingKey { case id, role, text, routing, commandInput, attachments }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(Role.self, forKey: .role)
        text = try container.decode(String.self, forKey: .text)
        // Unknown metadata from a newer writer must never make an otherwise readable conversation disappear.
        routing = try? container.decode(AIRoutingSelection.self, forKey: .routing)
        commandInput = try? container.decode(CommandInput.self, forKey: .commandInput)
        attachments = (try? container.decode([Attachment].self, forKey: .attachments)) ?? []
    }
}

/// One portable conversation in the session menu.
struct AIChatSession: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var messages: [AIChatMessage]
    var selectedModel: String?
    let startedAt: Date
    let titleOverride: String?
    let sourceSystemImage: String?
    /// Only ever set by a conversation started before AI commands rendered their prompt into the
    /// first user turn; still applied so a synced session from then keeps answering in character.
    let systemPrompt: String?

    init(
        id: UUID = UUID(), messages: [AIChatMessage] = [], startedAt: Date = Date(),
        titleOverride: String? = nil, systemPrompt: String? = nil,
        sourceSystemImage: String? = nil
    ) {
        self.id = id
        self.messages = messages
        self.startedAt = startedAt
        self.titleOverride = titleOverride
        self.sourceSystemImage = sourceSystemImage
        self.systemPrompt = systemPrompt
    }

    var routingModel: String? {
        selectedModel ?? messages.last(where: { $0.role == .assistant && $0.routing != nil })?.routing?.model
    }

    var title: String { titleOverride ?? AIChatEngine.sessionTitle(for: messages) }

    var systemImage: String {
        if let sourceSystemImage { return sourceSystemImage }
        // Earlier selection actions persisted these exact titles instead of explicit source metadata.
        switch titleOverride {
        case "Translation": return "translate"
        case "Definition": return "character.book.closed"
        case "Grammar Check": return "text.badge.checkmark"
        default: return "bubble.left.and.bubble.right"
        }
    }
}

enum AIChatPhase: Equatable, Sendable {
    case idle
    case waiting
    case failed(String)
}

/// Pure ownership for the one allowed request plus failures scoped to their conversations.
struct AIChatRequestLedger: Equatable, Sendable {
    private(set) var waitingSessionID: UUID?
    private var failures: [UUID: String] = [:]

    mutating func begin(sessionID: UUID) -> Bool {
        guard waitingSessionID == nil else { return false }
        failures.removeValue(forKey: sessionID)
        waitingSessionID = sessionID
        return true
    }

    @discardableResult
    mutating func finish(sessionID: UUID, failure: String?) -> Bool {
        guard waitingSessionID == sessionID else { return false }
        waitingSessionID = nil
        if let failure {
            failures[sessionID] = failure
        } else {
            failures.removeValue(forKey: sessionID)
        }
        return true
    }

    mutating func cancel() {
        waitingSessionID = nil
    }

    mutating func setFailure(_ message: String, for sessionID: UUID) {
        failures[sessionID] = message
    }

    mutating func remove(sessionID: UUID) {
        if waitingSessionID == sessionID { waitingSessionID = nil }
        failures.removeValue(forKey: sessionID)
    }

    func phase(for sessionID: UUID) -> AIChatPhase {
        if waitingSessionID == sessionID { return .waiting }
        return failures[sessionID].map(AIChatPhase.failed) ?? .idle
    }
}

/// The pure half of AI Chat: prompt text and transcript windowing. Foundation-only so
/// `Tools/ai-chat-test.swift` compiles it standalone; the network lives in `OpenRouterStore`.
enum AIChatEngine {
    /// Short and general — the palette is a quick-answer surface, not a document editor.
    static let systemPrompt = """
        You are Spotter's assistant, answering inside a small macOS launcher window. \
        Be direct and concise: lead with the answer, prefer short paragraphs, and skip preamble. \
        Markdown is rendered, so light formatting is fine — bold, lists, short tables and code \
        blocks — but do not decorate a one-line answer with headings.
        """

    /// What a conversation is called before a user turn has named it.
    static let untitledSessionTitle = "New Session"

    /// The one status vocabulary for a request in flight and for the reply that lands. The
    /// transcript status row, the footer pill and the launcher's background-task row all read these,
    /// so a row can never describe a state the store doesn't have.
    static let waitingStatus = "Thinking…"
    static let replyReadyStatus = "Reply ready."

    /// Completed conversations shown on a fresh chat surface, newest first. The blank current
    /// session stays out of the list because it is the composer the user is already in.
    static func historySessions(_ sessions: [AIChatSession]) -> [AIChatSession] {
        sessions.filter { !$0.messages.isEmpty }.sorted { $0.startedAt > $1.startedAt }
    }

    /// A session's menu title: its first user turn, whitespace collapsed and capped — the same
    /// derive-don't-ask rule Notes uses for titles.
    static func sessionTitle(for messages: [AIChatMessage], limit: Int = 40) -> String {
        guard
            let first = messages.first(where: { $0.role == .user })?.text
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " "),
            !first.isEmpty
        else { return untitledSessionTitle }
        guard first.count > limit else { return first }
        return String(first.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// Newest turns that fit a character budget, oldest dropped first. The latest message always
    /// survives, over budget or not — sending nothing would turn a long question into an empty one.
    static func transcriptWindow(
        _ messages: [AIChatMessage], budget: Int = 24_000
    ) -> [AIChatMessage] {
        guard let last = messages.last else { return [] }
        var kept: [AIChatMessage] = [last]
        var used = last.modelText.count
        var imageBytes = last.attachments.reduce(0) { $0 + ($1.imageData?.count ?? 0) }
        for message in messages.dropLast().reversed() {
            used += message.modelText.count
            imageBytes += message.attachments.reduce(0) { $0 + ($1.imageData?.count ?? 0) }
            guard used <= budget, imageBytes <= 20 * 1024 * 1024 else { break }
            kept.append(message)
        }
        return kept.reversed()
    }

    static func routingMessages(_ messages: [AIChatMessage]) -> [(role: String, content: String)] {
        messages.map { (role: $0.role.rawValue, content: $0.text) }
    }

    /// Uses URLComponents because browser handoff prompts may contain spaces, Unicode, newlines and reserved query bytes.
    static func chatGPTURL(for rawPrompt: String) -> URL? {
        let prompt = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "chatgpt.com"
        components.path = "/"
        components.queryItems = [URLQueryItem(name: "q", value: prompt)]
        return components.url
    }
}
