import Combine
import Foundation
import NaturalLanguage

@MainActor
final class TranslateManager: ObservableObject {
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

    @Published private(set) var state: TranslateState = .idle
    /// Which surface the plugin's one palette screen shows; set by whichever entry point opened it.
    @Published private(set) var screen: TranslateScreen = .selection
    @Published private(set) var apiKey: String
    @Published private(set) var targetCodes: [String]
    @Published private(set) var validation: Validation = .unknown

    // Kept from the Selection Tools era so an existing key and target list survive the split.
    private static let apiKeyKey = "selection-tools.google-translate-api-key"
    private static let targetsKey = "selection-tools.translation-targets"
    private let defaults: UserDefaults
    private var translationTask: Task<Void, Never>?
    private var pauseTask: Task<Void, Never>?
    /// The text the page is currently about to spend on, so a re-emitted identical query does not
    /// restart the pause and a superseded one is recognized.
    private var pendingText = ""
    private var memo = TranslationMemo()
    private var queryObserver: AnyCancellable?

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
        cancelWork()
        apiKey = trimmed
        validation = .unknown
        state = .idle
        // A different key is a different billing account; nothing it did not pay for carries over.
        memo.removeAll()
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

    // MARK: - Live translation

    /// Subscribed only while the palette screen is on stage, so nothing is typed at Google from a
    /// window that is not open.
    func startObservingQuery(_ publisher: Published<String>.Publisher) {
        queryObserver = publisher.sink { [weak self] query in
            self?.queryChanged(query)
        }
    }

    func stopObservingQuery() {
        queryObserver = nil
        cancelWork()
    }

    /// The Translate page's only trigger. Every keystroke lands here and almost all of them cost
    /// nothing: the request waits out `TranslateTiming.typingPause`, and text this key has already
    /// translated into these targets is answered from the memo without touching the network.
    func queryChanged(_ raw: String) {
        guard screen == .compose else { return }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text != pendingText else { return }
        pendingText = text
        pauseTask?.cancel()
        pauseTask = nil
        // A run whose text has been superseded is abandoned rather than left to land under new input.
        if state.original != text { translationTask?.cancel(); translationTask = nil }
        // A failure belongs to the text that produced it; editing clears it instead of retrying.
        if case .failed = state { state = .idle }

        guard !text.isEmpty else {
            state = .idle
            return
        }
        guard isTranslationReady, !targets.isEmpty else { return }
        if let answered = memo.value(for: memoKey(for: text)) {
            state = .translated(answered)
            return
        }
        if state.original == text { return }
        state = .idle
        pauseTask = Task { [weak self] in
            try? await Task.sleep(for: TranslateTiming.typingPause)
            guard !Task.isCancelled else { return }
            self?.pauseTask = nil
            self?.translate(text)
        }
    }

    /// The retry a failed page offers. It is the one place the user deliberately spends a request.
    func retry(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingText = trimmed
        state = .idle
        translate(trimmed)
    }

    // MARK: - Translation

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
        // Already paid for: the same text into the same targets never bills twice.
        if let answered = memo.value(for: memoKey(for: original)) {
            translationTask?.cancel()
            translationTask = nil
            state = .translated(answered)
            return
        }

        // Detected here, on this Mac, so a target the text is already written in costs neither a
        // request nor a row the user has to skip past.
        let source = Self.detectedLanguage(in: original)
        let wanted = configured.filter {
            !TranslationLanguages.isSameLanguage(target: $0.code, as: source)
        }
        guard !wanted.isEmpty else {
            showFailure(
                "The text is already in \(TranslationLanguages.name(for: source)). "
                    + "Add another translation language in Translate settings.")
            return
        }

        translationTask?.cancel()
        state = .loading(original: original, targets: wanted)
        let key = apiKey
        let memoKey = memoKey(for: original)
        translationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let rows = try await Self.translate(original, into: wanted, apiKey: key)
                try Task.checkCancellation()
                guard self.apiKey == key else { return }
                let result = TranslationResult(
                    original: original, sourceLanguage: source, rows: rows)
                self.memo.insert(result, for: memoKey)
                self.state = .translated(result)
                self.translationTask = nil
            } catch is CancellationError {
            } catch {
                guard self.apiKey == key else { return }
                let message = (error as? GoogleTranslationError)?.localizedDescription
                    ?? "Google Cloud Translation could not be reached."
                self.state = .failed(message)
                self.translationTask = nil
                AppLog.error("translate", "Translation failed: \(message)")
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
            return rowID == TranslateRowID.original ? original : nil
        case .translated(let translation):
            if rowID == TranslateRowID.original { return translation.original }
            return translation.rows.first { $0.code == rowID }?.text
        case .idle, .failed:
            return nil
        }
    }

    /// Switches the shared palette screen and drops whatever the previous run left behind. Every
    /// entry point goes through it, so the screen only ever changes where a command decides it.
    func prepare(screen: TranslateScreen) {
        self.screen = screen
        reset()
    }

    func showFailure(_ message: String) {
        cancelWork()
        state = .failed(message)
    }

    func reset() {
        cancelWork()
        state = .idle
    }

    private func cancelWork() {
        pauseTask?.cancel()
        pauseTask = nil
        translationTask?.cancel()
        translationTask = nil
        pendingText = ""
    }

    private func memoKey(for text: String) -> TranslationMemo.Key {
        TranslationMemo.key(text: text, targets: targetCodes)
    }

    /// On-device and offline: `NLLanguageRecognizer` reads the text without it leaving the Mac.
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
    ) async throws -> [TranslationRow] {
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
                TranslationRow(code: target.code, name: target.name, text: $0)
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
