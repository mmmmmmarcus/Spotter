import Foundation
import NaturalLanguage

enum SelectionTranslationServiceError: Error, Equatable, Sendable {
    case sourceLanguageUnknown
    case unavailable
}

/// The translate/grammar engines: OpenRouter is the only path — no key means the manager fails the
/// request with `.llmNotConfigured` before these are ever constructed.
@MainActor
struct OpenRouterTranslationService {
    let store: OpenRouterStore

    func translate(_ text: String) async throws -> SelectionTranslationResult {
        try Task.checkCancellation()
        guard let detected = NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue else {
            throw SelectionTranslationServiceError.sourceLanguageUnknown
        }
        let target = SelectionLLM.targetLanguage(
            preferred: Locale.preferredLanguages, detectedSource: detected)
        // The English name keeps the instruction unambiguous regardless of the user's UI language.
        let targetName =
            Locale(identifier: "en").localizedString(forLanguageCode: target) ?? target
        let raw = try await store.chat(
            system: SelectionLLM.translationSystemPrompt(targetLanguageName: targetName),
            user: text,
            model: store.translationModel)
        try Task.checkCancellation()
        let translated = SelectionLLM.parseTranslation(raw)
        guard !translated.isEmpty else { throw OpenRouterError.badResponse }
        return SelectionTranslationResult(
            originalText: text,
            translatedText: translated,
            sourceLanguageIdentifier: detected,
            targetLanguageIdentifier: target)
    }
}

@MainActor
struct OpenRouterGrammarService {
    let store: OpenRouterStore

    func check(_ text: String) async throws -> SelectionGrammarResult {
        try Task.checkCancellation()
        let raw = try await store.chat(
            system: SelectionLLM.grammarSystemPrompt(), user: text,
            model: store.grammarModel)
        try Task.checkCancellation()
        let result = SelectionLLM.parseGrammar(raw, originalText: text)
        guard !result.correctedText.isEmpty else { throw OpenRouterError.badResponse }
        return result
    }
}
