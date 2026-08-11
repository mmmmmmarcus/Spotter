import Foundation

enum AIChatSelectionAction: String, Equatable, Sendable {
    case define
    case grammar

    var title: String {
        switch self {
        case .define: "Define Selected Text"
        case .grammar: "Check Selected Text Grammar"
        }
    }

    var sessionTitle: String {
        switch self {
        case .define: "Definition"
        case .grammar: "Grammar Check"
        }
    }
}

/// Pure construction for the selected-text conversations owned by AI Chat.
enum AIChatSelectionPrompts {
    static let defaultDefinition =
        "For the first user message, act as a bilingual dictionary and language tutor. Define and "
        + "explain the selected word or phrase in both English and Simplified Chinese. Start with "
        + "‘English:’ and then ‘中文：’, include the part of speech when relevant, and keep both "
        + "explanations concise. For later messages, answer follow-up questions about the term."
    static let defaultGrammar =
        "For the first user message, proofread the selected text without changing its meaning, tone, "
        + "language, or formatting. Show the complete corrected text first, then briefly explain each "
        + "change; say that no issues were found when it is already correct. For later messages, "
        + "answer questions or revise the text as requested."

}
