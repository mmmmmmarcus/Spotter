import Foundation

enum RaycastStorePresentation {
    static func snapshot(query: String, enabled: Bool, busy: Bool, searching: Bool,
        status: String?, results: [ExtensionListing], installedNames: Set<String>) -> PluginPaletteSnapshot {
        func row(_ id: String, _ title: String, _ subtitle: String? = nil, action: String = "Open") -> PluginPaletteItem {
            PluginPaletteItem(id: id, title: title, subtitle: subtitle, icon: .symbol("puzzlepiece.extension"), primaryActionTitle: action)
        }
        var items: [PluginPaletteItem] = []
        if busy {
            items = [row("cancel", "Cancel Installation", status, action: "Cancel")]
        } else if !enabled {
            items = [row("enable", "Enable Raycast Extensions", "Allow third-party extensions before searching or installing.", action: "Enable")]
        } else if ExtensionGitHubSource(query) != nil {
            items = [row("source", "Install from GitHub", "Runs extension build scripts using local Node.js and your package manager.", action: "Install")]
        } else if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items = [row("local", "Import Built Extension…"), row("raycast", "Import from Raycast…"),
                row("updates", "Check for Extension Updates"), row("update-all", "Update All Extensions", action: "Update"),
                row("clean", "Clean Unused Extension Data…")]
        } else {
            items = results.map { result in
                row("listing:" + result.id, result.title, result.author + " · " + result.summary,
                    action: !installedNames.contains(result.name) ? "Install" : "Reinstall")
            }
        }
        return PluginPaletteSnapshot(sectionTitle: status ?? "Raycast Extension Store", items: items,
            isLoading: searching, loadingMessage: "Searching Raycast Store…", emptyMessage: status ?? "No extensions found.")
    }

}
