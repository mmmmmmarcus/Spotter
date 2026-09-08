import Foundation

enum SelectionToolsResults {
    /// A successful search leaves for the browser, so this screen exists for the failures: it never
    /// has rows, only a message that says which step could not be taken.
    static func snapshot(state: SelectionToolsState) -> PluginPaletteSnapshot {
        switch state {
        case .idle:
            return PluginPaletteSnapshot(
                sectionTitle: "Search", items: [],
                emptyMessage: "Select text in another app, then run Search Selected Text")
        case .failed(let failure):
            return PluginPaletteSnapshot(
                sectionTitle: "Search", items: [], errorMessage: failure, emptyMessage: failure)
        }
    }
}
