import Combine
import SwiftUI

extension PluginActionKey {
    static let openWorldClock = standard(
        pluginID: .worldClock, actionID: "open", title: "World Clock")
}

@MainActor
enum WorldClockPlugin {
    static func registration(core: AppCore) -> PluginRegistration {
        let open: () -> Void = { [weak core] in core?.openWorldClock() }
        let screen = PluginPaletteScreenRegistration(
            placeholder: "Filter saved cities…",
            snapshot: { [weak core] query in
                guard let core else {
                    return PluginPaletteSnapshot(
                        sectionTitle: "Cities", items: [], emptyMessage: "Plugin unavailable")
                }
                return snapshot(store: core.worldClock, query: query)
            },
            performPrimaryAction: { [weak core] cityID in
                core?.copyWorldClockTime(cityID: cityID)
            },
            actions: { [weak core] cityID in
                guard let core, let result = core.worldClock.result(for: cityID) else { return nil }
                return PopoverMenuContent(
                    header: result.city,
                    items: [
                        PopoverMenuItem(
                            title: "Copy Time", systemImage: "doc.on.doc", shortcut: "↵"
                        ) { core.copyWorldClockTime(cityID: cityID) },
                        PopoverMenuItem(
                            title: "Remove City", systemImage: "minus.circle",
                            isDestructive: true
                        ) { core.worldClock.remove(id: cityID) },
                    ])
            },
            onOpen: { [weak core] in core?.worldClock.start() },
            onClose: { [weak core] in core?.worldClock.stop() },
            observeChanges: { [weak core] invalidate in
                core?.worldClock.objectWillChange.sink { invalidate() }
                    ?? AnyCancellable {}
            })
        return PluginRegistration(
            metadata: PluginMetadata(
                id: .worldClock,
                name: "World Clock",
                summary: "Compare local time and keep a launcher list of cities around the world.",
                systemImage: "globe.americas",
                tint: .blue),
            defaultEnabled: true,
            shortcutActions: [PluginActionRegistration(key: .openWorldClock, perform: open)],
            launcherCommands: [
                PluginCommandRegistration(
                    id: "command:world-clock", name: "World Clock",
                    systemImage: "globe.americas", actionKey: .openWorldClock, perform: open)
            ],
            queryProvider: WorldClockQueryProvider(),
            paletteScreen: screen,
            onDisable: { [weak core] in
                core?.worldClock.stop()
                if core?.palette.mode == .plugin(.worldClock) {
                    core?.palette.prepare(mode: .launcher)
                }
            },
            settingsView: { AnyView(WorldClockSettingsView(store: core.worldClock)) })
    }

    private static func snapshot(
        store: WorldClockStore, query: String
    ) -> PluginPaletteSnapshot {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let cities = store.cities.filter { city in
            trimmed.isEmpty
                || city.name.localizedCaseInsensitiveContains(trimmed)
                || city.timeZoneIdentifier.localizedCaseInsensitiveContains(trimmed)
        }
        let items = cities.compactMap { city -> PluginPaletteItem? in
            guard let result = store.result(for: city.id) else { return nil }
            return PluginPaletteItem(
                id: city.id,
                title: city.name,
                subtitle: result.date + " · " + city.timeZoneIdentifier,
                icon: .symbol("clock"),
                accessories: [
                    PluginPaletteAccessory(systemImage: "clock.fill", text: result.time)
                ],
                primaryActionTitle: "Copy Time")
        }
        return PluginPaletteSnapshot(
            sectionTitle: "Cities", items: items,
            emptyMessage: trimmed.isEmpty ? "No cities added" : "No matching cities")
    }
}

extension AppCore {
    func openWorldClock() {
        guard plugins.isEnabled(.worldClock) else { return }
        showPalette(mode: .plugin(.worldClock))
    }

    func copyWorldClockTime(cityID: String) {
        guard plugins.isEnabled(.worldClock), let result = worldClock.result(for: cityID)
        else { return }
        hidePalette(restoreFocus: false)
        Paster.copyPlainText(result.time)
    }
}
