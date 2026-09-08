import Foundation

enum TranslateResults {
    static func snapshot(
        screen: TranslateScreen, state: TranslateState, query: String = "",
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

    /// The result of Translate Selected Text: the query filters rows rather than feeding them.
    private static func selectionSnapshot(state: TranslateState, query: String)
        -> PluginPaletteSnapshot
    {
        switch state {
        case .idle:
            return PluginPaletteSnapshot(
                sectionTitle: "Translate", items: [],
                emptyMessage: "Select text in another app, then run Translate Selected Text")
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
                sectionTitle: "Translate", items: [], errorMessage: failure,
                emptyMessage: failure)
        }
    }

    /// The Translate page: the palette's own search field is the text, so the query is the input and
    /// never a filter. Rows appear on their own once typing pauses; the only row the user can
    /// activate into a request is the retry a failure leaves behind.
    private static func composeSnapshot(
        state: TranslateState, query: String, targets: [TranslationLanguage], hasAPIKey: Bool
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
                emptyMessage: "Type text — it translates when you pause")
        }
        if case .failed(let failure) = state {
            return PluginPaletteSnapshot(
                sectionTitle: "Translate", items: [retryItem(note: failure)],
                emptyMessage: failure)
        }
        // Only the text that produced them: a run for older text never claims the newly typed text.
        guard state.original == typed else {
            return PluginPaletteSnapshot(
                sectionTitle: "Translate", items: [],
                emptyMessage: "Pause typing to translate into "
                    + targets.map(\.name).joined(separator: ", "))
        }
        switch state {
        case .loading(_, let pending):
            return PluginPaletteSnapshot(
                sectionTitle: "Translate", items: pending.map(pendingItem), isLoading: true,
                loadingMessage: "Translating with Google Cloud…", emptyMessage: "Translating…")
        case .translated(let translation):
            return PluginPaletteSnapshot(
                sectionTitle: "Translation", items: translation.rows.map(translatedItem),
                emptyMessage: "Nothing came back to translate")
        case .idle, .failed:
            return PluginPaletteSnapshot(
                sectionTitle: "Translate", items: [],
                emptyMessage: "Type text — it translates when you pause")
        }
    }

    /// A missing key and an empty target list are both settings problems, so the page names them
    /// instead of offering a row that could not run.
    private static func blocked(_ message: String) -> PluginPaletteSnapshot {
        PluginPaletteSnapshot(
            sectionTitle: "Translate", items: [], errorMessage: message, emptyMessage: message)
    }

    private static func retryItem(note: String) -> PluginPaletteItem {
        PluginPaletteItem(
            id: TranslateRowID.retry,
            title: "Try Again",
            subtitle: note,
            icon: .symbol("arrow.clockwise"),
            subtitleLineLimit: nil,
            primaryActionTitle: "Try Again")
    }

    private static func pendingItem(_ target: TranslationLanguage) -> PluginPaletteItem {
        item(id: target.code, text: "Translating…", subtitle: target.name, icon: "hourglass")
    }

    private static func translatedItem(_ row: TranslationRow) -> PluginPaletteItem {
        item(id: row.code, text: row.text, subtitle: row.name, icon: "character.book.closed")
    }

    private static func originalItem(_ text: String, subtitle: String) -> PluginPaletteItem {
        item(
            id: TranslateRowID.original, text: text, subtitle: subtitle,
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
