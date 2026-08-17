import Combine
import Foundation
import NaturalLanguage

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
    @Published private(set) var targetCodes: [String]
    @Published private(set) var validation: Validation = .unknown

    private static let apiKeyKey = "selection-tools.google-translate-api-key"
    private static let targetsKey = "selection-tools.translation-targets"
    private let defaults: UserDefaults
    private var translationTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        apiKey = defaults.string(forKey: Self.apiKeyKey) ?? ""
        let stored = defaults.stringArray(forKey: Self.targetsKey)
        targetCodes = TranslationLanguages.targets(for: stored ?? TranslationLanguages.defaultTargetCodes)
            .map(\.code)
    }

    /// The API key is the gate: with no key no request can be made, so entering one is the consent
    /// act. See `AGENTS.md` — this mirrors the OpenRouter decision and is not a pattern to copy.
    var isTranslationReady: Bool { !apiKey.isEmpty }

    var targets: [TranslationLanguage] { TranslationLanguages.targets(for: targetCodes) }

    var availableTargets: [TranslationLanguage] {
        TranslationLanguages.all.filter { !targetCodes.contains($0.code) }
    }

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

    func addTarget(_ code: String) {
        guard let language = TranslationLanguages.language(for: code),
            !targetCodes.contains(language.code)
        else { return }
        setTargets(targetCodes + [language.code])
    }

    func removeTarget(_ code: String) {
        setTargets(targetCodes.filter { $0 != code })
    }

    func setTargets(_ codes: [String]) {
        let resolved = TranslationLanguages.targets(for: codes).map(\.code)
        guard resolved != targetCodes else { return }
        targetCodes = resolved
        defaults.set(resolved, forKey: Self.targetsKey)
    }

    func translate(_ original: String) {
        guard !apiKey.isEmpty else {
            showFailure(GoogleTranslationError.missingAPIKey.localizedDescription)
            return
        }
        guard !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showFailure("Select some text to translate.")
            return
        }
        let configured = targets
        guard !configured.isEmpty else {
            showFailure(GoogleTranslationError.noTargets.localizedDescription)
            return
        }

        // Detected here, on this Mac, so a target the selection is already written in costs neither
        // a request nor a row the user has to skip past.
        let source = Self.detectedLanguage(in: original)
        let wanted = configured.filter {
            !TranslationLanguages.isSameLanguage(target: $0.code, as: source)
        }
        guard !wanted.isEmpty else {
            showFailure(
                "The selection is already in \(TranslationLanguages.name(for: source)). "
                    + "Add another translation language in Selection Tools settings.")
            return
        }

        translationTask?.cancel()
        state = .loading(original: original, targets: wanted)
        let key = apiKey
        translationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let rows = try await Self.translate(original, into: wanted, apiKey: key)
                try Task.checkCancellation()
                guard self.apiKey == key else { return }
                self.state = .translated(
                    SelectionTranslation(original: original, sourceLanguage: source, rows: rows))
                self.translationTask = nil
            } catch is CancellationError {
            } catch {
                guard self.apiKey == key else { return }
                let message = (error as? GoogleTranslationError)?.localizedDescription
                    ?? "Google Cloud Translation could not be reached."
                self.state = .failed(message)
                self.translationTask = nil
                AppLog.error("selection-tools", "Translation failed: \(message)")
            }
        }
    }

    func validateAPIKey() async {
        let key = apiKey
        guard !key.isEmpty else {
            validation = .invalid(GoogleTranslationError.missingAPIKey.localizedDescription)
            return
        }
        let target = targets.first?.code ?? TranslationLanguages.defaultTargetCodes[0]
        validation = .checking
        do {
            _ = try await Self.request(text: "Hello", target: target, apiKey: key)
            try Task.checkCancellation()
            guard apiKey == key else { return }
            validation = .valid("API key is working.")
        } catch {
            guard apiKey == key else { return }
            validation = .invalid(
                (error as? GoogleTranslationError)?.localizedDescription
                    ?? "Google Cloud Translation could not be reached.")
        }
    }

    func text(for rowID: String) -> String? {
        switch state {
        case .loading(let original, _):
            return rowID == SelectionTranslationRowID.original ? original : nil
        case .translated(let translation):
            if rowID == SelectionTranslationRowID.original { return translation.original }
            return translation.rows.first { $0.code == rowID }?.text
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

    /// On-device and offline: `NLLanguageRecognizer` reads the selection without it leaving the Mac.
    private static func detectedLanguage(in text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return TranslationLanguages.normalizedSource(recognizer.dominantLanguage?.rawValue)
    }

    private nonisolated static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    /// One request per target, concurrently, reassembled into the configured target order.
    private nonisolated static func translate(
        _ text: String, into targets: [TranslationLanguage], apiKey: String
    ) async throws -> [SelectionTranslationRow] {
        let texts = try await withThrowingTaskGroup(of: (Int, String).self) { group in
            for (index, target) in targets.enumerated() {
                group.addTask {
                    (index, try await request(text: text, target: target.code, apiKey: apiKey)
                        .translatedText)
                }
            }
            var collected: [Int: String] = [:]
            for try await (index, translated) in group { collected[index] = translated }
            return collected
        }
        return targets.enumerated().compactMap { index, target in
            texts[index].map {
                SelectionTranslationRow(code: target.code, name: target.name, text: $0)
            }
        }
    }

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
