import Foundation
import NaturalLanguage
import Translation

enum SelectionTranslationServiceError: Error, Equatable, Sendable {
    case sourceLanguageUnknown
    case languagesNotInstalled
    case unavailable
}

protocol SelectionTranslationServing: Sendable {
    func translate(_ text: String) async throws -> SelectionTranslationResult
}

struct SystemSelectionTranslationService: SelectionTranslationServing {
    func translate(_ text: String) async throws -> SelectionTranslationResult {
        try Task.checkCancellation()
        guard let detected = NLLanguageRecognizer.dominantLanguage(for: text) else {
            throw SelectionTranslationServiceError.sourceLanguageUnknown
        }

        let source = Locale.Language(identifier: detected.rawValue)
        let session = TranslationSession(installedSource: source, target: nil)
        guard await session.isReady else {
            throw SelectionTranslationServiceError.languagesNotInstalled
        }

        do {
            let response = try await session.translate(text)
            try Task.checkCancellation()
            return SelectionTranslationResponseMapper.map(
                originalText: text,
                translatedText: response.targetText,
                sourceLanguageIdentifier: response.sourceLanguage.minimalIdentifier,
                targetLanguageIdentifier: response.targetLanguage.minimalIdentifier)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if TranslationError.notInstalled ~= error {
                throw SelectionTranslationServiceError.languagesNotInstalled
            }
            if TranslationError.unableToIdentifyLanguage ~= error {
                throw SelectionTranslationServiceError.sourceLanguageUnknown
            }
            throw SelectionTranslationServiceError.unavailable
        }
    }
}

enum SelectionTranslationResponseMapper {
    static func map(
        originalText: String, translatedText: String,
        sourceLanguageIdentifier: String, targetLanguageIdentifier: String
    ) -> SelectionTranslationResult {
        SelectionTranslationResult(
            originalText: originalText,
            translatedText: translatedText,
            sourceLanguageIdentifier: sourceLanguageIdentifier,
            targetLanguageIdentifier: targetLanguageIdentifier)
    }
}
