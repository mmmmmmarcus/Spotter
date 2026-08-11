import Foundation

enum SelectionToolsResults {
    static func snapshot(state: SelectionToolsState, query: String = "") -> PluginPaletteSnapshot {
        let message: String
        switch state {
        case .idle:
            message = "Select text in another app, then run Search or Translate Selected Text"
            return PluginPaletteSnapshot(
                sectionTitle: "Selection Tools", items: [], emptyMessage: message)
        case .loading(let original):
            return PluginPaletteSnapshot(
                sectionTitle: "Translation",
                items: [
                    item(.original, text: original, subtitle: "Original", icon: "text.quote"),
                    item(
                        .chinese, text: "Translating…", subtitle: "Simplified Chinese",
                        icon: "hourglass"),
                    item(.english, text: "Translating…", subtitle: "English", icon: "hourglass"),
                ],
                isLoading: true,
                loadingMessage: "Translating with Google Cloud…",
                emptyMessage: "Translating…")
        case .translated(let translation):
            let source = translation.detectedSourceLanguage.map { "Original · \($0)" } ?? "Original"
            let items = [
                item(.original, text: translation.original, subtitle: source, icon: "text.quote"),
                item(
                    .chinese, text: translation.chinese, subtitle: "Simplified Chinese",
                    icon: "character.book.closed"),
                item(.english, text: translation.english, subtitle: "English", icon: "character"),
            ]
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
            message = failure
            return PluginPaletteSnapshot(
                sectionTitle: "Selection Tools", items: [], errorMessage: message,
                emptyMessage: message)
        }
    }

    private static func item(
        _ id: SelectionTranslationRowID, text: String, subtitle: String, icon: String
    ) -> PluginPaletteItem {
        PluginPaletteItem(
            id: id.rawValue, title: text, subtitle: subtitle, icon: .symbol(icon),
            titleLineLimit: 3, subtitleLineLimit: 1,
            primaryActionTitle: "Copy \(subtitle.components(separatedBy: " · ")[0])")
    }
}
