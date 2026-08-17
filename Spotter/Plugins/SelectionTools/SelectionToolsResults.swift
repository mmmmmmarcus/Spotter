import Foundation

enum SelectionToolsResults {
    static func snapshot(state: SelectionToolsState, query: String = "") -> PluginPaletteSnapshot {
        switch state {
        case .idle:
            let message = "Select text in another app, then run Search or Translate Selected Text"
            return PluginPaletteSnapshot(
                sectionTitle: "Selection Tools", items: [], emptyMessage: message)
        case .loading(let original, let targets):
            return PluginPaletteSnapshot(
                sectionTitle: "Translation",
                items: [originalItem(original, subtitle: "Original")]
                    + targets.map {
                        item(id: $0.code, text: "Translating…", subtitle: $0.name, icon: "hourglass")
                    },
                isLoading: true,
                loadingMessage: "Translating with Google Cloud…",
                emptyMessage: "Translating…")
        case .translated(let translation):
            let source = TranslationLanguages.name(for: translation.sourceLanguage)
            let items = [originalItem(translation.original, subtitle: "Original · \(source)")]
                + translation.rows.map {
                    item(
                        id: $0.code, text: $0.text, subtitle: $0.name,
                        icon: "character.book.closed")
                }
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

    private static func originalItem(_ text: String, subtitle: String) -> PluginPaletteItem {
        item(id: SelectionTranslationRowID.original, text: text, subtitle: subtitle, icon: "text.quote")
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
