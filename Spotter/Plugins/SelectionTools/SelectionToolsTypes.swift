import Foundation

enum SelectionToolsState: Equatable, Sendable {
    case idle
    case loading(String)
    case translated(SelectionTranslation)
    case failed(String)
}

struct SelectionTranslation: Equatable, Sendable {
    let original: String
    let chinese: String
    let english: String
    let detectedSourceLanguage: String?
}

enum SelectionTranslationRowID: String, Sendable {
    case original
    case chinese
    case english
}

struct GoogleTranslationRequest: Encodable, Equatable, Sendable {
    let q: String
    let target: String
    let format = "text"
}

struct GoogleTranslationResponse: Decodable, Equatable, Sendable {
    struct Payload: Decodable, Equatable, Sendable {
        let translations: [Translation]
    }

    struct Translation: Decodable, Equatable, Sendable {
        let detectedSourceLanguage: String?
        let translatedText: String
    }

    let data: Payload
}

struct GoogleTranslationErrorResponse: Decodable, Sendable {
    struct Payload: Decodable, Sendable {
        let message: String?
    }

    let error: Payload?
}

enum GoogleTranslationError: LocalizedError, Equatable, Sendable {
    case disabled
    case missingAPIKey
    case invalidResponse
    case http(Int, detail: String?)

    var errorDescription: String? {
        switch self {
        case .disabled:
            "Google Translate is off. Enable it in Selection Tools settings."
        case .missingAPIKey:
            "Add a Google Cloud Translation API key in Selection Tools settings."
        case .invalidResponse:
            "Google Cloud Translation returned an unreadable response."
        case .http(let status, let detail):
            if let detail, !detail.isEmpty {
                "Google Cloud Translation: \(detail) (HTTP \(status))"
            } else {
                "Google Cloud Translation failed (HTTP \(status))."
            }
        }
    }
}
