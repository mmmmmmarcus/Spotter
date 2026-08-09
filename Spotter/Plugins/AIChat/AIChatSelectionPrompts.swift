import Foundation

enum AIChatSelectionAction: String, Equatable, Sendable {
    case translate
    case define
    case grammar

    var title: String {
        switch self {
        case .translate: "Translate Selected Text"
        case .define: "Define Selected Text"
        case .grammar: "Check Selected Text Grammar"
        }
    }

    var sessionTitle: String {
        switch self {
        case .translate: "Translation"
        case .define: "Definition"
        case .grammar: "Grammar Check"
        }
    }
}

/// Pure construction for the selected-text conversations owned by AI Chat.
enum AIChatSelectionPrompts {
    static let targetLanguagePlaceholder = "{{target_language}}"
    static let defaultTranslation =
        "For the first user message, translate the selected text into {{target_language}} while "
        + "preserving its meaning, tone, formatting, and line breaks. Reply with the translation "
        + "only. For later messages, answer questions about the translation or revise it as requested."
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

    static func targetLanguage(preferred: [String], detectedSource: String?) -> String {
        let bases = preferred.map(baseCode).filter { !$0.isEmpty }
        let source = detectedSource.map(baseCode)
        guard let first = bases.first else { return "en" }
        if first != source { return first }
        if let next = bases.dropFirst().first(where: { $0 != source }) { return next }
        return source == "en" ? first : "en"
    }

    static func translation(template: String, targetLanguageName: String) -> String {
        template.replacingOccurrences(
            of: targetLanguagePlaceholder, with: targetLanguageName)
    }

    private static func baseCode(_ identifier: String) -> String {
        let normalized = identifier.replacingOccurrences(of: "_", with: "-")
        return normalized.split(separator: "-").first.map(String.init) ?? normalized
    }
}
