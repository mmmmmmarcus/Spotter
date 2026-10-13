import AppKit
import Combine
import SwiftUI

extension PluginActionKey {
    static let switchWindows = standard(pluginID: .navigation, actionID: "windows", title: "Switch Windows")
}

@MainActor
enum NavigationPlugin {
    static func registration(core: AppCore) -> PluginRegistration {
        let screen = PluginPaletteScreenRegistration(
            placeholder: "Search open windows…",
            snapshot: { [weak core] query in
                guard let core else { return PluginPaletteSnapshot(sectionTitle: "Navigation", items: [], emptyMessage: "Unavailable") }
                let rows = NavigationResults.matching(core.navigation.results, query: query)
                return PluginPaletteSnapshot(sectionTitle: "Open Windows",
                    items: rows.map { result in
                        PluginPaletteItem(id: result.id, title: result.title,
                            subtitle: result.subtitle.isEmpty ? result.appName : result.subtitle,
                            icon: result.bundlePath.map(PluginPaletteIcon.file(path:)) ?? .symbol("macwindow"),
                            primaryActionTitle: "Switch to Window")
                    }, isLoading: core.navigation.isLoading, errorMessage: core.navigation.errorMessage,
                    emptyMessage: "No matching windows.")
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
                PluginActionRegistration(key: .switchWindows) { core.openNavigation() },
            ],
            launcherCommands: [
                PluginCommandRegistration(id: "command:navigation:windows", name: "Switch Windows",
                    systemImage: "macwindow.on.rectangle", actionKey: .switchWindows) { core.openNavigation() },
            ],
            paletteScreen: screen,
            settingsView: { AnyView(NavigationSettingsView()) })
    }
}

extension AppCore {
    func openNavigation() {
        navigation.prepare(.windows, target: previousApplication ?? NSWorkspace.shared.frontmostApplication)
        palette.prepare(mode: .plugin(.navigation))
        showPalette(mode: .plugin(.navigation))
    }
}

private struct NavigationSettingsView: View {
    var body: some View {
        SettingsPane(title: "Navigation") {
            Section {
                SettingsRow(title: "Switch Windows", subtitle: "Search every open application window.") { EmptyView() }
                SettingsRow(title: "Menu Bar Items", subtitle: "Search the current app’s menu commands directly in the Palette.") { EmptyView() }
            } footer: {
                Text("Navigation uses Accessibility to read and activate windows and menus. Assign shortcuts in System → Shortcuts.")
            }
        }
    }
}
