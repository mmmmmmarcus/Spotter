import Foundation

enum SelectionToolsResults {
    static func snapshot(
        state: SelectionToolsState, query: String
    ) -> PluginPaletteSnapshot {
        switch state {
        case .idle:
            return PluginPaletteSnapshot(
                sectionTitle: "Selection Tools", items: [],
                emptyMessage: "Select text in another app, then run a Selection Tools action")
        case .loading(let request):
            return PluginPaletteSnapshot(
                sectionTitle: "Selection Tools · \(request.snapshot.source.appName)",
                items: [], isLoading: true,
                loadingMessage: request.action.loadingMessage,
                emptyMessage: request.action.loadingMessage)
        case .translated(let request, let result):
            return resultSnapshot(request: request, result: result, query: query)
        case .defined(let request, let result):
            return definitionSnapshot(request: request, result: result, query: query)
        case .grammarChecked(let request, let result):
            return grammarSnapshot(request: request, result: result, query: query)
        case .failed(_, _, let error):
            return PluginPaletteSnapshot(
                sectionTitle: "Selection Tools", items: [],
                errorMessage: error.message,
                emptyMessage: error.message)
        }
    }

    static func copyText(state: SelectionToolsState, itemID: String) -> String? {
        switch state {
        case .translated(let request, let result):
            return itemID == "original" ? request.snapshot.text : result.translatedText
        case .defined(let request, let result):
            return itemID == "original" ? request.snapshot.text : result.definitionText
        case .grammarChecked(let request, let result):
            return itemID == "original" ? request.snapshot.text : result.correctedText
        case .idle, .loading, .failed:
            return nil
        }
    }

    private static func resultSnapshot(
        request: SelectionToolsRequest, result: SelectionTranslationResult, query: String
    ) -> PluginPaletteSnapshot {
        let items = [
            PluginPaletteItem(
                id: "translation",
                title: result.translatedText,
                subtitle: "\(languageName(result.sourceLanguageIdentifier)) → "
                    + "\(languageName(result.targetLanguageIdentifier)) · Selected in "
                    + request.snapshot.source.appName,
                icon: .symbol("translate"),
                titleLineLimit: nil,
                primaryActionTitle: "Copy Translation"),
            PluginPaletteItem(
                id: "original",
                title: result.originalText,
                subtitle: "Original text · \(request.snapshot.source.appName)",
                icon: .symbol("selection.pin.in.out"),
                titleLineLimit: nil,
                primaryActionTitle: "Copy Original"),
        ]
        return PluginPaletteSnapshot(
            sectionTitle: "Translation",
            items: filtered(items, query: query),
            emptyMessage: "No matching translation result")
    }

    private static func definitionSnapshot(
        request: SelectionToolsRequest, result: SelectionDefinitionResult, query: String
    ) -> PluginPaletteSnapshot {
        let items = [
            PluginPaletteItem(
                id: "definition",
                title: result.definitionText,
                subtitle: "English + 中文 · Selected in " + request.snapshot.source.appName,
                icon: .symbol("character.book.closed"),
                titleLineLimit: nil,
                primaryActionTitle: "Copy Definition"),
            PluginPaletteItem(
                id: "original",
                title: result.originalText,
                subtitle: "Original text · \(request.snapshot.source.appName)",
                icon: .symbol("selection.pin.in.out"),
                titleLineLimit: nil,
                primaryActionTitle: "Copy Original"),
        ]
        return PluginPaletteSnapshot(
            sectionTitle: "Definition",
            items: filtered(items, query: query),
            emptyMessage: "No matching definition result")
    }

    private static func grammarSnapshot(
        request: SelectionToolsRequest, result: SelectionGrammarResult, query: String
    ) -> PluginPaletteSnapshot {
        var items = [
            PluginPaletteItem(
                id: "corrected",
                title: result.correctedText,
                subtitle: result.issues.isEmpty
                    ? "No grammar issues found · \(request.snapshot.source.appName)"
                    : "Corrected text · \(result.issues.count) "
                        + (result.issues.count == 1 ? "issue" : "issues")
                        + " · \(request.snapshot.source.appName)",
                icon: .symbol(result.issues.isEmpty ? "checkmark.circle" : "text.badge.checkmark"),
                titleLineLimit: nil,
                primaryActionTitle: "Copy Corrected Text")
        ]
        items += result.issues.map { issue in
            let suggestion = issue.suggestions.first.map { "Suggestion: \($0)" }
                ?? "No automatic replacement"
            return PluginPaletteItem(
                id: "issue:\(issue.id)",
                title: issue.message,
                subtitle: "“\(issue.originalText)” · \(suggestion)",
                icon: .symbol("exclamationmark.bubble"),
                subtitleLineLimit: nil,
                primaryActionTitle: "Copy Corrected Text")
        }
        items.append(
            PluginPaletteItem(
                id: "original",
                title: result.originalText,
                subtitle: "Original text · \(request.snapshot.source.appName)",
                icon: .symbol("selection.pin.in.out"),
                titleLineLimit: nil,
                primaryActionTitle: "Copy Original"))
        return PluginPaletteSnapshot(
            sectionTitle: "Grammar",
            items: filtered(items, query: query),
            emptyMessage: "No matching grammar result")
    }

    private static func filtered(
        _ items: [PluginPaletteItem], query: String
    ) -> [PluginPaletteItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }
        return items.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
                || $0.subtitle?.localizedCaseInsensitiveContains(trimmed) == true
        }
    }

    private static func languageName(_ identifier: String) -> String {
        Locale.current.localizedString(forLanguageCode: identifier) ?? identifier
    }
}
