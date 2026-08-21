import AppKit
import Combine
import SwiftUI

extension PluginActionKey {
    static let openFileSearch = standard(
        pluginID: .fileSearch, actionID: "open", title: "Search Files")
}

@MainActor
enum FileSearchPlugin {
    static func registration(core: AppCore) -> PluginRegistration {
        let open: () -> Void = { [weak core] in core?.openFileSearch() }
        let screen = PluginPaletteScreenRegistration(
            placeholder: "Search files and folders by name…",
            snapshot: { [weak core] query in
                guard let core else {
                    return PluginPaletteSnapshot(
                        sectionTitle: "Files", items: [], emptyMessage: "Plugin unavailable")
                }
                return snapshot(session: core.fileSearch, query: query)
            },
            performPrimaryAction: { [weak core] itemID in
                guard let core, let result = result(itemID: itemID, session: core.fileSearch) else {
                    return
                }
                core.openFile(result)
            },
            performSecondaryAction: { [weak core] itemID in
                guard let core, let result = result(itemID: itemID, session: core.fileSearch) else {
                    return
                }
                core.revealFile(result)
            },
            actions: { [weak core] itemID in
                guard let core, let result = result(itemID: itemID, session: core.fileSearch) else {
                    return nil
                }
                return actions(result: result, core: core)
            },
            onOpen: { [weak core] in
                guard let core else { return }
                core.fileSearch.observe(core.palette.$query)
                core.fileSearch.search(core.palette.query)
            },
            onClose: { [weak core] in core?.fileSearch.stop() },
            observeChanges: { [weak core] invalidate in
                core?.fileSearch.objectWillChange.sink { invalidate() } ?? AnyCancellable {}
            })
        return PluginRegistration(
            metadata: PluginMetadata(
                id: .fileSearch,
                name: "File Search",
                summary: "Find files and folders by name through the system Spotlight index.",
                systemImage: "doc.text.magnifyingglass",
                tint: .teal),
            defaultEnabled: true,
            shortcutActions: [PluginActionRegistration(key: .openFileSearch, perform: open)],
            launcherCommands: [
                PluginCommandRegistration(
                    id: "command:search-files", name: "Search Files",
                    systemImage: "doc.text.magnifyingglass", actionKey: .openFileSearch,
                    perform: open)
            ],
            paletteScreen: screen,
            onDisable: { [weak core] in
                core?.fileSearch.stop()
                if core?.palette.mode == .plugin(.fileSearch) {
                    core?.palette.prepare(mode: .launcher)
                }
            },
            settingsView: { AnyView(FileSearchSettingsView()) })
    }

    private static func snapshot(session: FileSearchSession, query: String) -> PluginPaletteSnapshot {
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let items = session.results.map { result in
            PluginPaletteItem(
                id: result.id,
                title: result.name,
                subtitle: result.parentPath,
                icon: .file(path: result.url.path),
                primaryActionTitle: result.isDirectory ? "Open Folder" : "Open File")
        }
        return PluginPaletteSnapshot(
            sectionTitle: "Files", items: items,
            // Previous rows stay visible while the next search runs — Spotlight takes most of a second, and blanking the list on every keystroke reads as breakage.
            isLoading: session.state == .searching,
            loadingMessage: "Searching…",
            errorMessage: session.state == .failed ? "Spotlight could not run that search" : nil,
            emptyMessage: typed.isEmpty ? "Type to search files" : "No files match “\(typed)”")
    }

    private static func result(itemID: String, session: FileSearchSession) -> FileSearchResult? {
        session.results.first { $0.id == itemID }
    }

    private static func actions(result: FileSearchResult, core: AppCore) -> PopoverMenuContent {
        PopoverMenuContent(
            header: result.name,
            items: [
                PopoverMenuItem(
                    title: result.isDirectory ? "Open Folder" : "Open File",
                    systemImage: "arrow.up.forward.app", shortcut: "↵"
                ) { core.openFile(result) },
                PopoverMenuItem(title: "Show in Finder", systemImage: "folder", shortcut: "⌘↵") {
                    core.revealFile(result)
                },
                PopoverMenuItem(title: "Copy Path", systemImage: "doc.on.doc") {
                    core.copyFilePath(result)
                },
            ])
    }
}

extension AppCore {
    func openFileSearch() {
        guard plugins.isEnabled(.fileSearch) else { return }
        showPalette(mode: .plugin(.fileSearch))
    }

    /// Opens the launcher's Search Files screen with `query` already typed — where the launcher's own "Search Files" fallback row lands once the plugin is on.
    func openFileSearch(query: String) {
        guard plugins.isEnabled(.fileSearch) else { return }
        showPalette(mode: .plugin(.fileSearch))
        palette.query = query
        palette.selection = 0
    }

    func openFile(_ result: FileSearchResult) {
        hidePalette(restoreFocus: false)
        NSWorkspace.shared.open(result.url)
    }

    func revealFile(_ result: FileSearchResult) {
        hidePalette(restoreFocus: false)
        NSWorkspace.shared.activateFileViewerSelecting([result.url])
    }

    func copyFilePath(_ result: FileSearchResult) {
        hidePalette(restoreFocus: false)
        Paster.copyPlainText(result.url.path)
    }
}
