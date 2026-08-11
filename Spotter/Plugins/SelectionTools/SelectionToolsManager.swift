import Combine
import Foundation

@MainActor
final class SelectionToolsManager: ObservableObject {
    static let provider = "Google Cloud Translation"
    static let providerURL = URL(string: "https://cloud.google.com/translate/docs/setup")!
    private nonisolated static let endpoint = URL(
        string: "https://translation.googleapis.com/language/translate/v2")!

    enum Validation: Equatable {
        case unknown
        case checking
        case valid(String)
        case invalid(String)
    }

    @Published private(set) var state: SelectionToolsState = .idle
    @Published private(set) var apiKey: String
    @Published private(set) var isTranslationEnabled: Bool
    @Published private(set) var validation: Validation = .unknown

    private static let apiKeyKey = "selection-tools.google-translate-api-key"
    private static let consentKey = "selection-tools.google-translate-enabled"
    private let defaults: UserDefaults
    private var translationTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        apiKey = defaults.string(forKey: Self.apiKeyKey) ?? ""
        isTranslationEnabled = defaults.bool(forKey: Self.consentKey)
    }

    var isTranslationReady: Bool { isTranslationEnabled && !apiKey.isEmpty }

    func setAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != apiKey else { return }
        translationTask?.cancel()
        translationTask = nil
        apiKey = trimmed
        validation = .unknown
        state = .idle
        if trimmed.isEmpty {
            defaults.removeObject(forKey: Self.apiKeyKey)
        } else {
            defaults.set(trimmed, forKey: Self.apiKeyKey)
        }
    }

    func setTranslationEnabled(_ enabled: Bool) {
        guard enabled != isTranslationEnabled else { return }
        isTranslationEnabled = enabled
        defaults.set(enabled, forKey: Self.consentKey)
        if !enabled {
            translationTask?.cancel()
            translationTask = nil
            validation = .unknown
            state = .idle
        }
    }

    func translate(_ original: String) {
        guard isTranslationEnabled else {
            showFailure(GoogleTranslationError.disabled.localizedDescription)
            return
        }
        guard !apiKey.isEmpty else {
            showFailure(GoogleTranslationError.missingAPIKey.localizedDescription)
            return
        }
        guard !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showFailure("Select some text to translate.")
            return
        }

        translationTask?.cancel()
        state = .loading(original)
        let key = apiKey
        translationTask = Task { [weak self] in
            guard let self else { return }
            do {
                async let chinese = Self.request(text: original, target: "zh-CN", apiKey: key)
                async let english = Self.request(text: original, target: "en", apiKey: key)
                let (chineseResult, englishResult) = try await (chinese, english)
                try Task.checkCancellation()
                guard self.isTranslationEnabled, self.apiKey == key else { return }
                self.state = .translated(
                    SelectionTranslation(
                        original: original,
                        chinese: chineseResult.translatedText,
                        english: englishResult.translatedText,
                        detectedSourceLanguage: chineseResult.detectedSourceLanguage
                            ?? englishResult.detectedSourceLanguage))
                self.translationTask = nil
            } catch is CancellationError {
            } catch {
                guard self.isTranslationEnabled, self.apiKey == key else { return }
                let message = (error as? GoogleTranslationError)?.localizedDescription
                    ?? "Google Cloud Translation could not be reached."
                self.state = .failed(message)
                self.translationTask = nil
                AppLog.error("selection-tools", "Translation failed: \(message)")
            }
        }
    }

    func validateAPIKey() async {
        guard isTranslationEnabled else {
            validation = .invalid(GoogleTranslationError.disabled.localizedDescription)
            return
        }
        let key = apiKey
        guard !key.isEmpty else {
            validation = .invalid(GoogleTranslationError.missingAPIKey.localizedDescription)
            return
        }
        validation = .checking
        do {
            _ = try await Self.request(text: "Hello", target: "zh-CN", apiKey: key)
            try Task.checkCancellation()
            guard isTranslationEnabled, apiKey == key else { return }
            validation = .valid("API key is working.")
        } catch {
            guard isTranslationEnabled, apiKey == key else { return }
            validation = .invalid(
                (error as? GoogleTranslationError)?.localizedDescription
                    ?? "Google Cloud Translation could not be reached.")
        }
    }

    func text(for rowID: String) -> String? {
        guard let row = SelectionTranslationRowID(rawValue: rowID) else { return nil }
        switch state {
        case .loading(let original):
            return row == .original ? original : nil
        case .translated(let translation):
            switch row {
            case .original: return translation.original
            case .chinese: return translation.chinese
            case .english: return translation.english
            }
        case .idle, .failed:
            return nil
        }
    }

    func showFailure(_ message: String) {
        translationTask?.cancel()
        translationTask = nil
        state = .failed(message)
    }

    func reset() {
        translationTask?.cancel()
        translationTask = nil
        state = .idle
    }

    private nonisolated static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    private nonisolated static func request(
        text: String, target: String, apiKey: String
    ) async throws -> GoogleTranslationResponse.Translation {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components?.url else { throw GoogleTranslationError.invalidResponse }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            GoogleTranslationRequest(q: text, target: target))

        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else {
            throw GoogleTranslationError.invalidResponse
        }
        guard http.statusCode == 200 else {
            let detail = (try? JSONDecoder().decode(
                GoogleTranslationErrorResponse.self, from: data))?.error?.message
            throw GoogleTranslationError.http(http.statusCode, detail: detail)
        }
        guard
            let translation = (try? JSONDecoder().decode(
                GoogleTranslationResponse.self, from: data))?.data.translations.first,
            !translation.translatedText.isEmpty
        else { throw GoogleTranslationError.invalidResponse }
        return translation
    }
}
