import AppKit
import Combine
import SwiftUI

extension PluginActionKey {
    static let openAppleShortcuts = standard(
        pluginID: .appleShortcuts, actionID: "open", title: "Search Apple Shortcuts")
}

@MainActor
enum AppleShortcutsPlugin {
    static func registration(core: AppCore) -> PluginRegistration {
        let open: () -> Void = { [weak core] in core?.openAppleShortcuts() }
        let screen = PluginPaletteScreenRegistration(
            placeholder: "Search Apple Shortcuts…",
            snapshot: { [weak core] query in
                guard let core else {
                    return PluginPaletteSnapshot(sectionTitle: "Apple Shortcuts", items: [], emptyMessage: "Unavailable")
                }
                let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                let matches = core.appleShortcuts.shortcuts.filter {
                    trimmed.isEmpty || $0.name.localizedCaseInsensitiveContains(trimmed)
                }
                return PluginPaletteSnapshot(
                    sectionTitle: "Apple Shortcuts",
                    items: matches.map {
                        PluginPaletteItem(id: $0.id.uuidString, title: $0.name, subtitle: nil,
                            icon: .file(path: applicationURL.path), primaryActionTitle: "Run Shortcut")
                    }, isLoading: core.appleShortcuts.isLoading,
                    errorMessage: core.appleShortcuts.errorMessage,
                    emptyMessage: core.appleShortcuts.shortcuts.isEmpty
                        ? "No Apple Shortcuts found." : "No matching shortcut.")
            },
            performPrimaryAction: { [weak core] itemID in
                guard let id = UUID(uuidString: itemID) else { return }
                core?.runAppleShortcut(id: id)
            },
            actions: { _ in nil },
            onOpen: { [weak core] in core?.appleShortcuts.refresh() },
            observeChanges: { [weak core] invalidate in
                core?.appleShortcuts.objectWillChange.sink { invalidate() } ?? AnyCancellable {}
            })
        return PluginRegistration(
            metadata: PluginMetadata(id: .appleShortcuts, name: "Apple Shortcuts",
                summary: "Search and run the shortcuts in Apple’s Shortcuts app.",
                systemImage: "square.2.layers.3d", tint: .purple),
            shortcutActions: [PluginActionRegistration(key: .openAppleShortcuts, perform: open)],
            launcherCommands: [PluginCommandRegistration(id: "command:apple-shortcuts", name: "Search Apple Shortcuts",
                systemImage: "square.2.layers.3d", actionKey: .openAppleShortcuts, perform: open)],
            dynamicLauncherCommands: { [weak core] in
                core?.appleShortcuts.shortcuts.map { shortcut in
                    PluginCommandRegistration(id: shortcut.entryID, name: shortcut.name,
                        systemImage: "square.2.layers.3d", iconFilePath: applicationURL.path) {
                        core?.runAppleShortcut(id: shortcut.id)
                    }
                } ?? []
            },
            paletteScreen: screen,
            onStart: { [weak core] in core?.appleShortcuts.refresh() },
            settingsView: { AnyView(AppleShortcutsSettingsView(store: core.appleShortcuts)) })
    }

    static let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts")
        ?? URL(fileURLWithPath: "/System/Applications/Shortcuts.app")
}

extension AppCore {
    func openAppleShortcuts() {
        palette.prepare(mode: .plugin(.appleShortcuts))
        showPalette(mode: .plugin(.appleShortcuts))
    }

    func runAppleShortcut(id: UUID) {
        let name = appleShortcuts.shortcuts.first { $0.id == id }?.name ?? "Shortcut"
        hidePalette(restoreFocus: true)
        Task { [weak self] in
            guard let self, let error = await appleShortcuts.run(id: id) else { return }
            AppLog.error("apple-shortcuts", "Couldn’t run \(name): \(error)")
            hud.show(title: "Couldn’t Run \(name)", symbol: "exclamationmark.triangle", isNoOp: true)
        }
    }
}

private struct AppleShortcutsSettingsView: View {
    @ObservedObject var store: AppleShortcutsStore

    var body: some View {
        SettingsPane(title: "Apple Shortcuts") {
            Section {
                SettingsRow(title: "Shortcuts", subtitle: status) {
                    Button("Refresh") { store.refresh() }.disabled(store.isLoading)
                }
                SettingsRow(title: "Shortcuts App") {
                    Button("Open") { AppLauncher.launch(AppleShortcutsPlugin.applicationURL) }
                }
            }
        }
    }

    private var status: String {
        if store.isLoading { return "Loading…" }
        if let error = store.errorMessage { return error }
        return "\(store.shortcuts.count) available"
    }
}
