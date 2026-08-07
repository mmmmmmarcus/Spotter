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
            placeholder: "Search saved cities, or type any city to add it…",
            // ←/→ scrub every row by an hour while the query is empty; each open resets to now.
            adjustHours: { [weak core] delta in core?.worldClock.adjustPreview(byHours: delta) },
            snapshot: { [weak core] query in
                guard let core else {
                    return PluginPaletteSnapshot(
                        sectionTitle: "Cities", items: [], emptyMessage: "Plugin unavailable")
                }
                return snapshot(store: core.worldClock, query: query)
            },
            performPrimaryAction: { [weak core] itemID in
                if itemID.hasPrefix("add:") {
                    core?.addWorldClockCity(id: String(itemID.dropFirst("add:".count)))
                } else {
                    core?.copyWorldClockTime(cityID: itemID)
                }
            },
            actions: { [weak core] itemID in
                guard let core else { return nil }
                if itemID.hasPrefix("add:") {
                    let cityID = String(itemID.dropFirst("add:".count))
                    guard let city = WorldClockEngine.city(id: cityID) else { return nil }
                    return PopoverMenuContent(
                        header: city.name,
                        items: [
                            PopoverMenuItem(
                                title: "Add City", systemImage: "plus.circle", shortcut: "↵"
                            ) { core.addWorldClockCity(id: cityID) }
                        ])
                }
                guard let result = core.worldClock.result(for: itemID) else { return nil }
                return PopoverMenuContent(
                    header: result.city,
                    items: [
                        PopoverMenuItem(
                            title: "Copy Time", systemImage: "doc.on.doc", shortcut: "↵"
                        ) { core.copyWorldClockTime(cityID: itemID) },
                        PopoverMenuItem(
                            title: "Remove City", systemImage: "minus.circle",
                            isDestructive: true
                        ) { core.worldClock.remove(id: itemID) },
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

    /// Saved cities lead; a non-empty query also surfaces catalog matches as "Add City" rows, so
    /// the list is managed right here without a trip to Settings.
    private static func snapshot(
        store: WorldClockStore, query: String
    ) -> PluginPaletteSnapshot {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let cities = store.cities.filter { city in
            trimmed.isEmpty
                || city.name.localizedCaseInsensitiveContains(trimmed)
                || city.timeZoneIdentifier.localizedCaseInsensitiveContains(trimmed)
        }
        var items = cities.compactMap { city -> PluginPaletteItem? in
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
        if !trimmed.isEmpty {
            items += store.availableCities(matching: trimmed).prefix(8).map { city in
                PluginPaletteItem(
                    id: "add:" + city.id,
                    title: city.name,
                    subtitle: city.timeZoneIdentifier,
                    icon: .symbol("plus.circle"),
                    primaryActionTitle: "Add City")
            }
        }
        // The scrubbed offset is part of the section header so a shifted list can't read as now.
        let offset = store.previewOffsetHours
        let title = offset == 0 ? "Cities" : String(format: "Cities · %+d h", offset)
        return PluginPaletteSnapshot(
            sectionTitle: title, items: items,
            emptyMessage: trimmed.isEmpty
                ? "No cities added — type a city name to add one."
                : "No city matches that name.")
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

    /// Adds a catalog city from its "Add City" row, clearing the query so the grown list shows.
    func addWorldClockCity(id: String) {
        guard plugins.isEnabled(.worldClock), let city = WorldClockEngine.city(id: id) else {
            return
        }
        worldClock.add(city)
        palette.query = ""
        palette.selection = 0
    }
}
