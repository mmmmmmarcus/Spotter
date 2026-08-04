import Foundation
import NaturalLanguage

/// LLM-backed counterparts of the system translation/grammar services; chosen by
/// `SelectionToolsManager` when `OpenRouterStore.isReady`, with the on-device services as fallback.
@MainActor
struct OpenRouterTranslationService: SelectionTranslationServing {
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
            user: text)
        try Task.checkCancellation()
        let translated = SelectionLLM.parseTranslation(raw)
        guard !translated.isEmpty else { throw OpenRouterError.badResponse }
        return SelectionTranslationResponseMapper.map(
            originalText: text,
            translatedText: translated,
            sourceLanguageIdentifier: detected,
            targetLanguageIdentifier: target)
    }
}

@MainActor
struct OpenRouterGrammarService: SelectionGrammarChecking {
    let store: OpenRouterStore

    func check(_ text: String) async throws -> SelectionGrammarResult {
        try Task.checkCancellation()
        let raw = try await store.chat(system: SelectionLLM.grammarSystemPrompt(), user: text)
        try Task.checkCancellation()
        let result = SelectionLLM.parseGrammar(raw, originalText: text)
        guard !result.correctedText.isEmpty else { throw OpenRouterError.badResponse }
        return result
    }
}
