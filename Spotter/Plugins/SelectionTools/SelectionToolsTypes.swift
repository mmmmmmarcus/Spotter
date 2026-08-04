import Foundation

enum SelectionToolAction: String, Equatable, Sendable {
    case search
    case translate
    case grammar

    var title: String {
        switch self {
        case .search: "Search Selected Text"
        case .translate: "Translate Selected Text"
        case .grammar: "Check Selected Text Grammar"
        }
    }

    var loadingMessage: String {
        switch self {
        case .search: "Opening Google Search…"
        case .translate: "Translating…"
        case .grammar: "Checking grammar…"
        }
    }
}

struct SelectedTextSourceSnapshot: Equatable, Sendable {
    let processIdentifier: Int32
    let appName: String
    let bundleIdentifier: String?
}

struct SelectedTextSnapshot: Equatable, Sendable {
    let text: String
    let source: SelectedTextSourceSnapshot
    let capturedAt: Date
}

struct SelectionTranslationResult: Equatable, Sendable {
    let originalText: String
    let translatedText: String
    let sourceLanguageIdentifier: String
    let targetLanguageIdentifier: String
}

struct SelectionGrammarIssue: Equatable, Identifiable, Sendable {
    let location: Int
    let length: Int
    let originalText: String
    let message: String
    let suggestions: [String]

    var id: String { "\(location):\(length):\(message)" }
}

struct SelectionGrammarResult: Equatable, Sendable {
    let originalText: String
    let correctedText: String
    let issues: [SelectionGrammarIssue]
}

enum SelectionToolsFailure: Error, Equatable, Sendable {
    case accessibilityDenied
    case noFrontmostApplication
    case spotterIsFrontmost
    case focusedControlUnavailable
    case selectedTextUnavailable
    case emptySelection
    case invalidSearchURL
    case browserOpenFailed
    case sourceLanguageUnknown
    case translationLanguagesNotInstalled
    case translationUnavailable
    case grammarUnavailable
    case cancelled

    var message: String {
        switch self {
        case .accessibilityDenied:
            "Accessibility access is required to read selected text. Grant it in System Settings."
        case .noFrontmostApplication:
            "No frontmost application was available."
        case .spotterIsFrontmost:
            "Spotter is frontmost. Return to another app, select text, then use the global shortcut."
        case .focusedControlUnavailable:
            "The frontmost app did not expose a focused text control, and copying the selection produced no text."
        case .selectedTextUnavailable:
            "The selection could not be read through Accessibility, and copying it produced no text."
        case .emptySelection:
            "No text is selected in the frontmost app."
        case .invalidSearchURL:
            "Spotter could not build a Google Search URL for the selected text."
        case .browserOpenFailed:
            "The default browser could not open the Google Search URL."
        case .sourceLanguageUnknown:
            "macOS could not identify the selected text language."
        case .translationLanguagesNotInstalled:
            "The required macOS Translation languages are not installed on this Mac."
        case .translationUnavailable:
            "macOS Translation could not translate the selected text."
        case .grammarUnavailable:
            "The macOS grammar service could not check the selected text."
        case .cancelled:
            "The request was cancelled."
        }
    }
}

struct SelectionToolsRequest: Equatable, Sendable {
    let generation: Int
    let action: SelectionToolAction
    let snapshot: SelectedTextSnapshot
}

enum SelectionToolsState: Equatable, Sendable {
    case idle
    case loading(SelectionToolsRequest)
    case translated(SelectionToolsRequest, SelectionTranslationResult)
    case grammarChecked(SelectionToolsRequest, SelectionGrammarResult)
    case failed(
        action: SelectionToolAction, snapshot: SelectedTextSnapshot?, error: SelectionToolsFailure)
}

struct SelectionToolsStateMachine: Sendable {
    private(set) var state: SelectionToolsState = .idle
    private(set) var generation = 0
    private var activeRequest: SelectionToolsRequest?

    mutating func begin(
        action: SelectionToolAction, snapshot: SelectedTextSnapshot
    ) -> SelectionToolsRequest {
        generation += 1
        let request = SelectionToolsRequest(
            generation: generation, action: action, snapshot: snapshot)
        activeRequest = request
        state = .loading(request)
        return request
    }

    @discardableResult
    mutating func completeTranslation(
        _ result: SelectionTranslationResult, for request: SelectionToolsRequest
    ) -> Bool {
        guard request == activeRequest, request.action == .translate else { return false }
        activeRequest = nil
        state = .translated(request, result)
        return true
    }

    @discardableResult
    mutating func completeGrammar(
        _ result: SelectionGrammarResult, for request: SelectionToolsRequest
    ) -> Bool {
        guard request == activeRequest, request.action == .grammar else { return false }
        activeRequest = nil
        state = .grammarChecked(request, result)
        return true
    }

    @discardableResult
    mutating func fail(
        _ error: SelectionToolsFailure, for request: SelectionToolsRequest
    ) -> Bool {
        guard request == activeRequest else { return false }
        activeRequest = nil
        state = .failed(action: request.action, snapshot: request.snapshot, error: error)
        return true
    }

    mutating func failCapture(action: SelectionToolAction, error: SelectionToolsFailure) {
        generation += 1
        activeRequest = nil
        state = .failed(action: action, snapshot: nil, error: error)
    }

    @discardableResult
    mutating func cancelActive() -> Bool {
        guard let request = activeRequest else { return false }
        activeRequest = nil
        state = .failed(action: request.action, snapshot: request.snapshot, error: .cancelled)
        return true
    }

    mutating func reset() {
        activeRequest = nil
        state = .idle
    }
}
