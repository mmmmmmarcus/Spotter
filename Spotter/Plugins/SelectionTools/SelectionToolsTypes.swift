import Foundation

/// A language Google Cloud Translation can translate into. The table is fixed at compile time: a
/// language menu is not worth a network round trip, and Settings has to render offline.
struct TranslationLanguage: Identifiable, Equatable, Sendable {
    let code: String
    let name: String

    var id: String { code }
}

enum TranslationLanguages {
    /// Ordered by name so Settings can offer it as-is.
    static let all: [TranslationLanguage] = [
        TranslationLanguage(code: "ar", name: "Arabic"),
        TranslationLanguage(code: "bn", name: "Bengali"),
        TranslationLanguage(code: "bg", name: "Bulgarian"),
        TranslationLanguage(code: "zh-CN", name: "Chinese (Simplified)"),
        TranslationLanguage(code: "zh-TW", name: "Chinese (Traditional)"),
        TranslationLanguage(code: "cs", name: "Czech"),
        TranslationLanguage(code: "da", name: "Danish"),
        TranslationLanguage(code: "nl", name: "Dutch"),
        TranslationLanguage(code: "en", name: "English"),
        TranslationLanguage(code: "fi", name: "Finnish"),
        TranslationLanguage(code: "fr", name: "French"),
        TranslationLanguage(code: "de", name: "German"),
        TranslationLanguage(code: "el", name: "Greek"),
        TranslationLanguage(code: "iw", name: "Hebrew"),
        TranslationLanguage(code: "hi", name: "Hindi"),
        TranslationLanguage(code: "hu", name: "Hungarian"),
        TranslationLanguage(code: "id", name: "Indonesian"),
        TranslationLanguage(code: "it", name: "Italian"),
        TranslationLanguage(code: "ja", name: "Japanese"),
        TranslationLanguage(code: "ko", name: "Korean"),
        TranslationLanguage(code: "ms", name: "Malay"),
        TranslationLanguage(code: "no", name: "Norwegian"),
        TranslationLanguage(code: "fa", name: "Persian"),
        TranslationLanguage(code: "pl", name: "Polish"),
        TranslationLanguage(code: "pt", name: "Portuguese"),
        TranslationLanguage(code: "ro", name: "Romanian"),
        TranslationLanguage(code: "ru", name: "Russian"),
        TranslationLanguage(code: "es", name: "Spanish"),
        TranslationLanguage(code: "sv", name: "Swedish"),
        TranslationLanguage(code: "th", name: "Thai"),
        TranslationLanguage(code: "tr", name: "Turkish"),
        TranslationLanguage(code: "uk", name: "Ukrainian"),
        TranslationLanguage(code: "vi", name: "Vietnamese"),
    ]

    /// What Selection Tools translated into before targets were configurable.
    static let defaultTargetCodes = ["zh-CN", "en"]

    /// When detection is inconclusive the selection is treated as English, so a target list that
    /// contains English still drops its own row rather than paying for a pointless request.
    static let fallbackSourceCode = "en"

    static func language(for code: String) -> TranslationLanguage? {
        all.first { $0.code.caseInsensitiveCompare(code) == .orderedSame }
    }

    static func name(for code: String) -> String {
        language(for: code)?.name ?? code
    }

    /// Resolves stored codes into languages, dropping unknown ones and repeats but keeping order.
    static func targets(for codes: [String]) -> [TranslationLanguage] {
        var seen: Set<String> = []
        return codes.compactMap { language(for: $0) }.filter { seen.insert($0.code).inserted }
    }

    /// True when translating into `target` would hand back the selection unchanged.
    static func isSameLanguage(target: String, as source: String) -> Bool {
        let target = canonical(target)
        let source = canonical(source)
        if target == source { return true }
        // Simplified and Traditional are real translations of each other, so `zh` needs an exact match.
        if target.hasPrefix("zh") || source.hasPrefix("zh") { return false }
        return primary(target) == primary(source)
    }

    /// Maps what a language detector reports onto the codes this table uses.
    static func normalizedSource(_ detected: String?) -> String {
        guard let detected, !detected.isEmpty else { return fallbackSourceCode }
        let canonical = canonical(detected)
        if let exact = all.first(where: { self.canonical($0.code) == canonical }) { return exact.code }
        if let byPrimary = all.first(where: { primary(self.canonical($0.code)) == primary(canonical) }) {
            return byPrimary.code
        }
        return detected
    }

    /// Detector output and Google's codes disagree on a handful of languages; reconcile them here so
    /// every comparison in the plugin is made on one spelling.
    private static func canonical(_ code: String) -> String {
        let lowered = code.lowercased().replacingOccurrences(of: "_", with: "-")
        switch lowered {
        case "zh-hans", "zh": return "zh-cn"
        case "zh-hant": return "zh-tw"
        case "he": return "iw"
        case "nb", "nn": return "no"
        case "in": return "id"
        default: return lowered
        }
    }

    private static func primary(_ code: String) -> String {
        String(code.prefix { $0 != "-" })
    }
}

enum SelectionToolsState: Equatable, Sendable {
    case idle
    case loading(original: String, targets: [TranslationLanguage])
    case translated(SelectionTranslation)
    case failed(String)
}

struct SelectionTranslationRow: Identifiable, Equatable, Sendable {
    let code: String
    let name: String
    let text: String

    var id: String { code }
}

struct SelectionTranslation: Equatable, Sendable {
    let original: String
    /// Detected on this Mac before anything leaves it; English when detection is inconclusive.
    let sourceLanguage: String
    let rows: [SelectionTranslationRow]
}

enum SelectionTranslationRowID {
    /// A language code can never collide with this: none of them contain a letter sequence this long.
    static let original = "original"
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

    /// Google also reports the language it detected; Spotter detects on device before sending, so
    /// there is nothing left to read off the response.
    struct Translation: Decodable, Equatable, Sendable {
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
    case missingAPIKey
    case noTargets
    case invalidResponse
    case http(Int, detail: String?)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Add a Google Cloud Translation API key in Selection Tools settings."
        case .noTargets:
            "Add a translation language in Selection Tools settings."
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
