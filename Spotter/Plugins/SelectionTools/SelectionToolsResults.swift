import Foundation

enum SelectionToolsResults {
    static func snapshot(
        screen: SelectionToolsScreen, state: SelectionToolsState, query: String = "",
        targets: [TranslationLanguage] = [], hasAPIKey: Bool = false
    ) -> PluginPaletteSnapshot {
        switch screen {
        case .selection:
            return selectionSnapshot(state: state, query: query)
        case .compose:
            return composeSnapshot(
                state: state, query: query, targets: targets, hasAPIKey: hasAPIKey)
        }
    }

    /// The result of Search / Translate Selected Text: the query filters rows rather than feeding them.
    private static func selectionSnapshot(state: SelectionToolsState, query: String)
        -> PluginPaletteSnapshot
    {
        switch state {
        case .idle:
            let message = "Select text in another app, then run Search or Translate Selected Text"
            return PluginPaletteSnapshot(
                sectionTitle: "Selection Tools", items: [], emptyMessage: message)
        case .loading(let original, let targets):
            return PluginPaletteSnapshot(
                sectionTitle: "Translation",
                items: targets.map(pendingItem) + [originalItem(original, subtitle: "Original")],
                isLoading: true,
                loadingMessage: "Translating with Google Cloud…",
                emptyMessage: "Translating…")
        case .translated(let translation):
            let source = TranslationLanguages.name(for: translation.sourceLanguage)
            // The translation leads: it is what the user asked for, and the original is the input they already had.
            let items = translation.rows.map(translatedItem)
                + [originalItem(translation.original, subtitle: "Original · \(source)")]
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let filtered = trimmed.isEmpty
                ? items
                : items.filter {
                    $0.title.localizedCaseInsensitiveContains(trimmed)
                        || ($0.subtitle?.localizedCaseInsensitiveContains(trimmed) == true)
                }
            return PluginPaletteSnapshot(
                sectionTitle: "Translation", items: filtered,
                emptyMessage: "No translation row matches \(trimmed)")
        case .failed(let failure):
            return PluginPaletteSnapshot(
                sectionTitle: "Selection Tools", items: [], errorMessage: failure,
                emptyMessage: failure)
        }
    }

    /// The Translate page: the palette's own search field is the text, so the query is the input and
    /// never a filter, and its single action row is the only thing that can spend a request.
    private static func composeSnapshot(
        state: SelectionToolsState, query: String, targets: [TranslationLanguage], hasAPIKey: Bool
    ) -> PluginPaletteSnapshot {
        guard hasAPIKey else {
            return blocked(GoogleTranslationError.missingAPIKey.localizedDescription)
        }
        guard !targets.isEmpty else {
            return blocked(GoogleTranslationError.noTargets.localizedDescription)
        }
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else {
            return PluginPaletteSnapshot(
                sectionTitle: "Translate", items: [],
                emptyMessage: "Type text to translate, then press ↵")
        }
        switch state {
        case .loading(let original, let pending) where original == typed:
            return PluginPaletteSnapshot(
                sectionTitle: "Translate", items: pending.map(pendingItem), isLoading: true,
                loadingMessage: "Translating with Google Cloud…", emptyMessage: "Translating…")
        // Only the text that produced them: editing the query hands the action row back rather than leaving a stale answer under new input.
        case .translated(let translation) where translation.original == typed:
            return PluginPaletteSnapshot(
                sectionTitle: "Translation", items: translation.rows.map(translatedItem),
                emptyMessage: "Nothing came back to translate")
        case .failed(let failure):
            return PluginPaletteSnapshot(
                sectionTitle: "Translate", items: [translateItem(targets: targets, note: failure)],
                emptyMessage: failure)
        case .idle, .loading, .translated:
            return PluginPaletteSnapshot(
                sectionTitle: "Translate", items: [translateItem(targets: targets, note: nil)],
                emptyMessage: "Type text to translate, then press ↵")
        }
    }

    /// A missing key and an empty target list are both settings problems, so the page names them
    /// instead of offering a row that could not run.
    private static func blocked(_ message: String) -> PluginPaletteSnapshot {
        PluginPaletteSnapshot(
            sectionTitle: "Translate", items: [], errorMessage: message, emptyMessage: message)
    }

    private static func translateItem(targets: [TranslationLanguage], note: String?)
        -> PluginPaletteItem
    {
        PluginPaletteItem(
            id: SelectionTranslationRowID.translate,
            title: "Translate",
            subtitle: note ?? "Into " + targets.map(\.name).joined(separator: ", "),
            icon: .symbol("translate"),
            subtitleLineLimit: nil,
            primaryActionTitle: note == nil ? "Translate" : "Try Again")
    }

    private static func pendingItem(_ target: TranslationLanguage) -> PluginPaletteItem {
        item(id: target.code, text: "Translating…", subtitle: target.name, icon: "hourglass")
    }

    private static func translatedItem(_ row: SelectionTranslationRow) -> PluginPaletteItem {
        item(id: row.code, text: row.text, subtitle: row.name, icon: "character.book.closed")
    }

    private static func originalItem(_ text: String, subtitle: String) -> PluginPaletteItem {
        item(
            id: SelectionTranslationRowID.original, text: text, subtitle: subtitle,
            icon: "text.quote")
    }

    /// No title line limit: a translation the user cannot read in full is not a translation.
    private static func item(
        id: String, text: String, subtitle: String, icon: String
    ) -> PluginPaletteItem {
        PluginPaletteItem(
            id: id, title: text, subtitle: subtitle, icon: .symbol(icon),
            titleLineLimit: nil, subtitleLineLimit: 1,
            primaryActionTitle: "Copy \(subtitle.components(separatedBy: " · ")[0])")
    }
}
