import AppKit
import Combine
import SwiftUI

extension PluginActionKey {
    static let switchWindows = standard(pluginID: .navigation, actionID: "windows", title: "Switch Windows")
    static let searchMenus = standard(pluginID: .navigation, actionID: "menus", title: "Search Menu Bar Items")
}

@MainActor
enum NavigationPlugin {
    static func registration(core: AppCore) -> PluginRegistration {
        let screen = PluginPaletteScreenRegistration(
            placeholder: "Search windows and menus…",
            livePlaceholder: { [weak core] in
                core?.navigation.mode == .windows ? "Search open windows…" : "Search menu bar items…"
            },
            snapshot: { [weak core] query in
                guard let core else { return PluginPaletteSnapshot(sectionTitle: "Navigation", items: [], emptyMessage: "Unavailable") }
                let rows = NavigationResults.matching(core.navigation.results, query: query)
                return PluginPaletteSnapshot(sectionTitle: core.navigation.mode == .windows ? "Open Windows" : "Menu Bar Items",
                    items: rows.map { result in
                        PluginPaletteItem(id: result.id, title: result.title,
                            subtitle: result.subtitle.isEmpty ? result.appName : result.subtitle,
                            icon: result.bundlePath.map(PluginPaletteIcon.file(path:)) ?? .symbol("macwindow"),
                            primaryActionTitle: core.navigation.mode == .windows ? "Switch to Window" : "Activate Menu Item")
                    }, isLoading: core.navigation.isLoading, errorMessage: core.navigation.errorMessage,
                    emptyMessage: core.navigation.mode == .windows ? "No matching windows." : "No matching menu items.")
            },
            performPrimaryAction: { [weak core] itemID in
                core?.navigation.activate(id: itemID)
                core?.hidePalette(restoreFocus: false)
            },
            actions: { _ in nil },
            onOpen: { [weak core] in core?.navigation.refresh() },
            onClose: { [weak core] in core?.navigation.close() },
            observeChanges: { [weak core] invalidate in
                core?.navigation.objectWillChange.sink { invalidate() } ?? AnyCancellable {}
            })
        return PluginRegistration(
            metadata: PluginMetadata(id: .navigation, name: "Navigation",
                summary: "Search every open window or activate commands from the frontmost app’s menu bar.",
                systemImage: "rectangle.3.group", tint: .cyan),
            permissions: [.accessibility],
            shortcutActions: [
                PluginActionRegistration(key: .switchWindows) { core.openNavigation(.windows) },
                PluginActionRegistration(key: .searchMenus) { core.openNavigation(.menus) },
            ],
            launcherCommands: [
                PluginCommandRegistration(id: "command:navigation:windows", name: "Switch Windows",
                    systemImage: "macwindow.on.rectangle", actionKey: .switchWindows) { core.openNavigation(.windows) },
                PluginCommandRegistration(id: "command:navigation:menus", name: "Search Menu Bar Items",
                    systemImage: "menubar.rectangle", actionKey: .searchMenus) { core.openNavigation(.menus) },
            ],
            paletteScreen: screen,
            settingsView: { AnyView(NavigationSettingsView()) })
    }
}

extension AppCore {
    func openNavigation(_ mode: NavigationMode) {
        navigation.prepare(mode, target: previousApplication ?? NSWorkspace.shared.frontmostApplication)
        palette.prepare(mode: .plugin(.navigation))
        showPalette(mode: .plugin(.navigation))
    }
}

private struct NavigationSettingsView: View {
    var body: some View {
        SettingsPane(title: "Navigation") {
            Section {
                SettingsRow(title: "Switch Windows", subtitle: "Search every open application window.") { EmptyView() }
                SettingsRow(title: "Search Menu Bar Items", subtitle: "Search commands exposed by the frontmost app.") { EmptyView() }
            } footer: {
                Text("Navigation uses Accessibility to read and activate windows and menus. Assign shortcuts in System → Shortcuts.")
            }
        }
    }
}
