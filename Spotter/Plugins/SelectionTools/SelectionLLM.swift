import Foundation

/// Prompt construction and response parsing for the LLM-backed translate/grammar path.
/// Foundation-only and pure so `Tools/selection-tools-test.swift` compiles the real logic.
enum SelectionLLM {
    /// Translate into the user's first preferred language; text already in it goes to the next preferred language, falling back to English.
    static func targetLanguage(preferred: [String], detectedSource: String?) -> String {
        let bases = preferred.map(baseCode).filter { !$0.isEmpty }
        let source = detectedSource.map(baseCode)
        guard let first = bases.first else { return "en" }
        if first != source { return first }
        if let next = bases.dropFirst().first(where: { $0 != source }) { return next }
        return source == "en" ? first : "en"
    }

    static func translationSystemPrompt(targetLanguageName: String) -> String {
        "You are a translator. Translate the user's text into \(targetLanguageName). "
            + "Preserve meaning, tone, formatting and line breaks. "
            + "Reply with the translation only — no quotes, no commentary."
    }

    static func grammarSystemPrompt() -> String {
        "You are a proofreader. Fix grammar, spelling and punctuation in the user's text without "
            + "changing its meaning, tone, language or formatting. Reply with only a JSON object: "
            + #"{"corrected": "<full corrected text>", "issues": [{"original": "<exact fragment "#
            + #"from the text>", "message": "<short explanation>", "suggestion": "<replacement>"}]}. "#
            + "Use an empty issues array when the text is already correct. No other output."
    }

    static func parseTranslation(_ raw: String) -> String {
        stripCodeFence(raw).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Decodes the grammar JSON; a reply that isn't valid JSON degrades to "the whole reply is the corrected text".
    static func parseGrammar(_ raw: String, originalText: String) -> SelectionGrammarResult {
        let cleaned = stripCodeFence(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let data = cleaned.data(using: .utf8),
            let reply = try? JSONDecoder().decode(GrammarReply.self, from: data),
            !reply.corrected.isEmpty
        else {
            return SelectionGrammarResult(
                originalText: originalText, correctedText: cleaned, issues: [])
        }

        let source = originalText as NSString
        var searchStart = 0
        let issues = (reply.issues ?? []).compactMap { issue -> SelectionGrammarIssue? in
            guard !issue.original.isEmpty, !issue.message.isEmpty else { return nil }
            // Anchor each fragment left-to-right so a repeated fragment maps to successive occurrences.
            let range = source.range(
                of: issue.original,
                range: NSRange(location: searchStart, length: source.length - searchStart))
            let location: Int
            let length: Int
            if range.location != NSNotFound {
                location = range.location
                length = range.length
                searchStart = range.location + range.length
            } else {
                location = 0
                length = 0
            }
            let suggestion = issue.suggestion?.isEmpty == false ? [issue.suggestion!] : []
            return SelectionGrammarIssue(
                location: location, length: length,
                originalText: issue.original, message: issue.message,
                suggestions: suggestion)
        }

        return SelectionGrammarResult(
            originalText: originalText, correctedText: reply.corrected, issues: issues)
    }

    /// Models wrap JSON or plain replies in Markdown fences despite instructions; strip one outer fence.
    static func stripCodeFence(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("```") else { return text }
        text.removeFirst(3)
        // Drop a language tag like `json` on the fence line.
        if let newline = text.firstIndex(of: "\n") {
            let tag = text[..<newline]
            if !tag.contains(" "), tag.count <= 16 {
                text = String(text[text.index(after: newline)...])
            }
        }
        if text.hasSuffix("```") {
            text.removeLast(3)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func baseCode(_ identifier: String) -> String {
        let normalized = identifier.replacingOccurrences(of: "_", with: "-")
        return normalized.split(separator: "-").first.map(String.init) ?? normalized
    }

    private struct GrammarReply: Decodable {
        struct Issue: Decodable {
            let original: String
            let message: String
            let suggestion: String?
        }
        let corrected: String
        let issues: [Issue]?
    }
}
