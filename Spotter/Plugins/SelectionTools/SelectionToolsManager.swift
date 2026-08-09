import AppKit
import Combine

@MainActor
final class SelectionToolsManager: ObservableObject {
    @Published private(set) var state: SelectionToolsState = .idle
    @Published private(set) var translationPrompt: String
    @Published private(set) var definitionPrompt: String
    @Published private(set) var grammarPrompt: String

    private var machine = SelectionToolsStateMachine()
    private var requestTask: Task<Void, Never>?
    /// The only AI engine; without an API key requests fail with `.llmNotConfigured`.
    private let openRouter: OpenRouterStore
    private let defaults: UserDefaults
    private static let translationPromptKey = "selection-tools.translation-prompt"
    private static let definitionPromptKey = "selection-tools.definition-prompt"
    private static let grammarPromptKey = "selection-tools.grammar-prompt"
    /// Wired by `AppCore.start()` so the ⌘C fallback can pause clipboard-history capture around its transient pasteboard use without reaching into another plugin's manager.
    var suspendClipboardCapture: (() -> Void)?
    var resumeClipboardCapture: (() -> Void)?

    init(openRouter: OpenRouterStore, defaults: UserDefaults = .standard) {
        self.openRouter = openRouter
        self.defaults = defaults
        translationPrompt = defaults.string(forKey: Self.translationPromptKey)
            ?? SelectionLLM.defaultTranslationSystemPrompt
        definitionPrompt = defaults.string(forKey: Self.definitionPromptKey)
            ?? SelectionLLM.defaultDefinitionSystemPrompt
        grammarPrompt = defaults.string(forKey: Self.grammarPromptKey)
            ?? SelectionLLM.defaultGrammarSystemPrompt
    }

    func captureSelection() async -> Result<SelectedTextSnapshot, SelectionToolsFailure> {
        // Snapshot the frontmost app before the first await; it must be the app the user was in, not whatever is frontmost when the accessibility retries finish.
        let application = NSWorkspace.shared.frontmostApplication
        guard let application else { return .failure(.noFrontmostApplication) }
        guard application.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return .failure(.spotterIsFrontmost)
        }

        let source = SelectedTextSourceSnapshot(
            processIdentifier: application.processIdentifier,
            appName: application.localizedName ?? "Unknown App",
            bundleIdentifier: application.bundleIdentifier)
        switch await SelectedTextReader.readAwaitingAccessibilityTree(
            pid: source.processIdentifier)
        {
        case .success(let text):
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .failure(.emptySelection)
            }
            return .success(
                SelectedTextSnapshot(text: text, source: source, capturedAt: Date()))
        case .failure(.accessibilityDenied):
            return .failure(.accessibilityDenied)
        case .failure(let error):
            return await copyFallback(source: source, accessibilityError: error)
        }
    }

    /// Accessibility couldn't see the selection (canvas apps, lazy web views): briefly borrow the pasteboard for a synthetic ⌘C, then restore it.
    private func copyFallback(
        source: SelectedTextSourceSnapshot, accessibilityError: SelectedTextReadError
    ) async -> Result<SelectedTextSnapshot, SelectionToolsFailure> {
        suspendClipboardCapture?()
        defer { resumeClipboardCapture?() }
        switch await SelectionCopyCapture.read(pid: source.processIdentifier) {
        case .copied(let text):
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .failure(.emptySelection)
            }
            return .success(
                SelectedTextSnapshot(text: text, source: source, capturedAt: Date()))
        case .nothingCopied:
            // The app ignored ⌘C entirely — the strongest signal that nothing was selected.
            return .failure(.emptySelection)
        case .noText:
            return .failure(
                accessibilityError == .focusedControlUnavailable
                    ? .focusedControlUnavailable : .selectedTextUnavailable)
        }
    }

    func start(action: SelectionToolAction, snapshot: SelectedTextSnapshot) {
        requestTask?.cancel()
        let request = machine.begin(action: action, snapshot: snapshot)
        guard openRouter.isReady else {
            machine.fail(.llmNotConfigured, for: request)
            publishState()
            return
        }
        publishState()

        switch action {
        case .search:
            return
        case .translate:
            let service = OpenRouterTranslationService(
                store: openRouter, systemPromptTemplate: translationPrompt)
            requestTask = Task { [weak self] in
                do {
                    let result = try await service.translate(snapshot.text)
                    try Task.checkCancellation()
                    self?.completeTranslation(result, request: request)
                } catch is CancellationError {
                    self?.completeFailure(.cancelled, request: request)
                } catch is OpenRouterError {
                    self?.completeFailure(.llmRequestFailed, request: request)
                } catch let error as SelectionTranslationServiceError {
                    self?.completeFailure(Self.map(error), request: request)
                } catch {
                    self?.completeFailure(.translationUnavailable, request: request)
                }
            }
        case .define:
            let service = OpenRouterDefinitionService(
                store: openRouter, systemPrompt: definitionPrompt)
            requestTask = Task { [weak self] in
                do {
                    let result = try await service.define(snapshot.text)
                    try Task.checkCancellation()
                    self?.completeDefinition(result, request: request)
                } catch is CancellationError {
                    self?.completeFailure(.cancelled, request: request)
                } catch is OpenRouterError {
                    self?.completeFailure(.llmRequestFailed, request: request)
                } catch {
                    self?.completeFailure(.definitionUnavailable, request: request)
                }
            }
        case .grammar:
            let service = OpenRouterGrammarService(
                store: openRouter, systemPrompt: grammarPrompt)
            requestTask = Task { [weak self] in
                do {
                    let result = try await service.check(snapshot.text)
                    try Task.checkCancellation()
                    self?.completeGrammar(result, request: request)
                } catch is CancellationError {
                    self?.completeFailure(.cancelled, request: request)
                } catch is OpenRouterError {
                    self?.completeFailure(.llmRequestFailed, request: request)
                } catch {
                    self?.completeFailure(.grammarUnavailable, request: request)
                }
            }
        }
    }

    func showFailure(action: SelectionToolAction, error: SelectionToolsFailure) {
        requestTask?.cancel()
        requestTask = nil
        machine.failCapture(action: action, error: error)
        publishState()
    }

    func cancel() {
        requestTask?.cancel()
        requestTask = nil
        if machine.cancelActive() { publishState() }
    }

    func reset() {
        requestTask?.cancel()
        requestTask = nil
        machine.reset()
        publishState()
    }

    var primaryCopyText: String? {
        switch state {
        case .translated(_, let result): result.translatedText
        case .defined(_, let result): result.definitionText
        case .grammarChecked(_, let result): result.correctedText
        case .idle, .loading, .failed: nil
        }
    }

    var originalText: String? {
        switch state {
        case .loading(let request): request.snapshot.text
        case .translated(let request, _): request.snapshot.text
        case .defined(let request, _): request.snapshot.text
        case .grammarChecked(let request, _): request.snapshot.text
        case .failed(_, let snapshot, _): snapshot?.text
        case .idle: nil
        }
    }

    private func completeTranslation(
        _ result: SelectionTranslationResult, request: SelectionToolsRequest
    ) {
        guard machine.completeTranslation(result, for: request) else { return }
        requestTask = nil
        publishState()
    }

    private func completeDefinition(
        _ result: SelectionDefinitionResult, request: SelectionToolsRequest
    ) {
        guard machine.completeDefinition(result, for: request) else { return }
        requestTask = nil
        publishState()
    }

    private func completeGrammar(
        _ result: SelectionGrammarResult, request: SelectionToolsRequest
    ) {
        guard machine.completeGrammar(result, for: request) else { return }
        requestTask = nil
        publishState()
    }

    private func completeFailure(
        _ error: SelectionToolsFailure, request: SelectionToolsRequest
    ) {
        guard machine.fail(error, for: request) else { return }
        AppLog.error("selection-tools", "\(request.action.rawValue) failed: \(error)")
        requestTask = nil
        publishState()
    }

    private func publishState() {
        state = machine.state
    }

    func setTranslationPrompt(_ prompt: String) {
        guard prompt != translationPrompt else { return }
        translationPrompt = prompt
        persist(
            prompt, key: Self.translationPromptKey,
            defaultPrompt: SelectionLLM.defaultTranslationSystemPrompt)
    }

    func setDefinitionPrompt(_ prompt: String) {
        guard prompt != definitionPrompt else { return }
        definitionPrompt = prompt
        persist(
            prompt, key: Self.definitionPromptKey,
            defaultPrompt: SelectionLLM.defaultDefinitionSystemPrompt)
    }

    func setGrammarPrompt(_ prompt: String) {
        guard prompt != grammarPrompt else { return }
        grammarPrompt = prompt
        persist(
            prompt, key: Self.grammarPromptKey,
            defaultPrompt: SelectionLLM.defaultGrammarSystemPrompt)
    }

    private func persist(_ prompt: String, key: String, defaultPrompt: String) {
        if prompt == defaultPrompt {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(prompt, forKey: key)
        }
    }

    nonisolated private static func map(
        _ error: SelectionTranslationServiceError
    ) -> SelectionToolsFailure {
        switch error {
        case .sourceLanguageUnknown: .sourceLanguageUnknown
        case .unavailable: .translationUnavailable
        }
    }
}
