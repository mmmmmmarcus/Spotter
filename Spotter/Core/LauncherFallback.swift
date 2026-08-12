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
        case .aiChat: return "Spotter"
        case .chatGPT: return "Web"
        case .terminal: return "Terminal"
        case .fileSearch: return "Finder"
        }
    }
}

struct LauncherFallback: Identifiable, Equatable, Sendable {
    let action: LauncherFallbackAction
    let query: String

    var id: LauncherFallbackAction.ID { action.id }

    static func suggestions(for rawQuery: String) -> [LauncherFallback] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return LauncherFallbackAction.allCases.map { LauncherFallback(action: $0, query: query) }
    }
}
