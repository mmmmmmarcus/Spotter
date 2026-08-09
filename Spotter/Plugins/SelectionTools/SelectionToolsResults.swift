import Foundation

enum SelectionToolsResults {
    static func snapshot(state: SelectionToolsState) -> PluginPaletteSnapshot {
        let message: String
        switch state {
        case .idle:
            message = "Select text in another app, then run Search Selected Text"
            return PluginPaletteSnapshot(
                sectionTitle: "Selection Tools", items: [], emptyMessage: message)
        case .failed(let failure):
            message = failure
            return PluginPaletteSnapshot(
                sectionTitle: "Selection Tools", items: [], errorMessage: message,
                emptyMessage: message)
        }
    }
}
