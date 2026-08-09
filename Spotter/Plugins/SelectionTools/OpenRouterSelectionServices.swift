import Foundation
import NaturalLanguage

enum SelectionTranslationServiceError: Error, Equatable, Sendable {
    case sourceLanguageUnknown
    case unavailable
}

/// The AI selection engines: OpenRouter is the only path — no key means the manager fails the
/// request with `.llmNotConfigured` before these are ever constructed.
@MainActor
struct OpenRouterTranslationService {
    let store: OpenRouterStore
    let systemPromptTemplate: String

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
            system: SelectionLLM.translationSystemPrompt(
                targetLanguageName: targetName, template: systemPromptTemplate),
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
struct OpenRouterDefinitionService {
    let store: OpenRouterStore
    let systemPrompt: String

    func define(_ text: String) async throws -> SelectionDefinitionResult {
        try Task.checkCancellation()
        let raw = try await store.chat(
            system: SelectionLLM.definitionSystemPrompt(template: systemPrompt), user: text,
            model: store.definitionModel)
        try Task.checkCancellation()
        let definition = SelectionLLM.parseDefinition(raw)
        guard !definition.isEmpty else { throw OpenRouterError.badResponse }
        return SelectionDefinitionResult(originalText: text, definitionText: definition)
    }
}

@MainActor
struct OpenRouterGrammarService {
    let store: OpenRouterStore
    let systemPrompt: String

    func check(_ text: String) async throws -> SelectionGrammarResult {
        try Task.checkCancellation()
        let raw = try await store.chat(
            system: SelectionLLM.grammarSystemPrompt(template: systemPrompt), user: text,
            model: store.grammarModel)
        try Task.checkCancellation()
        let result = SelectionLLM.parseGrammar(raw, originalText: text)
        guard !result.correctedText.isEmpty else { throw OpenRouterError.badResponse }
        return result
    }
}
