import Foundation

/// One turn of the palette conversation.
struct AIChatMessage: Identifiable, Equatable, Sendable {
    enum Role: String, Sendable {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    let text: String

    init(id: UUID = UUID(), role: Role, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

/// The pure half of AI Chat: prompt text and transcript windowing. Foundation-only so
/// `Tools/ai-chat-test.swift` compiles it standalone; the network lives in `OpenRouterStore`.
enum AIChatEngine {
    /// Short and general — the palette is a quick-answer surface, not a document editor.
    static let systemPrompt = """
        You are Spotter's assistant, answering inside a small macOS launcher window. \
        Be direct and concise: lead with the answer, prefer short paragraphs and plain text, \
        and skip preamble. Use code blocks only for code.
        """

    /// A session's menu title: its first user turn, whitespace collapsed and capped — the same
    /// derive-don't-ask rule Notes uses for titles.
    static func sessionTitle(for messages: [AIChatMessage], limit: Int = 40) -> String {
        guard
            let first = messages.first(where: { $0.role == .user })?.text
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " "),
            !first.isEmpty
        else { return "New Session" }
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
        var used = last.text.count
        for message in messages.dropLast().reversed() {
            used += message.text.count
            guard used <= budget else { break }
            kept.append(message)
        }
        return kept.reversed()
    }
}
