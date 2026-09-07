import Foundation

/// Explicit destinations appended to every non-empty launcher query.
enum LauncherFallbackAction: String, CaseIterable, Identifiable, Sendable {
    case aiChat
    case chatGPT
    case terminal
    case fileSearch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aiChat: return "Send to AI Chat"
        case .chatGPT: return "Send to ChatGPT"
        case .terminal: return "Run in Terminal"
        case .fileSearch: return "Search Files"
        }
    }

    /// The AI Chat row names the model it will ask. A nil name means there is nothing to promise —
    /// no API key, so no request can be made — and the row keeps its generic title.
    func title(aiChatModel: String?) -> String {
        guard case .aiChat = self, let aiChatModel,
            !aiChatModel.trimmingCharacters(in: .whitespaces).isEmpty
        else { return title }
        return "Ask \(aiChatModel)…"
    }

    var systemImage: String {
        switch self {
        case .aiChat: return "sparkles"
        case .chatGPT: return "globe"
        case .terminal: return "terminal"
        case .fileSearch: return "doc.text.magnifyingglass"
        }
    }

    var contextLabel: String {
        switch self {
        // Named for what the row does, not for the app it happens inside — every row is Spotter.
        case .aiChat: return "Ask AI"
        case .chatGPT: return "Web"
        case .terminal: return "Terminal"
        // Named for where the row lands: the File Search screen when its plugin is on, Finder when it isn't.
        case .fileSearch: return "Files"
        }
    }
}

struct LauncherFallback: Identifiable, Equatable, Sendable {
    let action: LauncherFallbackAction
    let query: String
    /// Resolved here rather than at the row: this file stays pure, so the model name is passed in.
    let title: String

    var id: LauncherFallbackAction.ID { action.id }

    init(action: LauncherFallbackAction, query: String, aiChatModel: String? = nil) {
        self.action = action
        self.query = query
        self.title = action.title(aiChatModel: aiChatModel)
    }

    static func suggestions(for rawQuery: String, aiChatModel: String? = nil) -> [LauncherFallback] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return LauncherFallbackAction.allCases.map {
            LauncherFallback(action: $0, query: query, aiChatModel: aiChatModel)
        }
    }
}
