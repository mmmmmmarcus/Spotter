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
            placeholder: "Search cities, type one to add it, or convert “8pm in London”…",
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
                } else if itemID.hasPrefix(WorldClockEngine.conversionRowPrefix) {
                    core?.copyWorldClockConvertedTime(rowID: itemID)
                } else {
                    core?.copyWorldClockTime(cityID: itemID)
                }
            },
            actions: { [weak core] itemID in
                guard let core else { return nil }
                if itemID.hasPrefix(WorldClockEngine.conversionRowPrefix) {
                    guard let row = core.worldClockConversionRow(id: itemID) else { return nil }
                    return PopoverMenuContent(
                        header: row.name,
                        items: [
                            PopoverMenuItem(
                                title: "Copy Time", systemImage: "doc.on.doc", shortcut: "↵"
                            ) { core.copyWorldClockConvertedTime(rowID: itemID) }
                        ])
                }
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
            shortcutActions: [PluginActionRegistration(key: .openWorldClock, perform: open)],
            launcherCommands: [
                PluginCommandRegistration(
                    id: "command:world-clock", name: "World Clock",
                    systemImage: "globe.americas", actionKey: .openWorldClock, perform: open)
            ],
            queryProvider: WorldClockQueryProvider(),
            paletteScreen: screen,
            settingsView: { AnyView(WorldClockSettingsView(store: core.worldClock)) })
    }

    /// Saved cities lead; a non-empty query also surfaces catalog matches as "Add City" rows, so
    /// the list is managed right here without a trip to Settings. A query that opens with a clock
    /// time (`8pm in london`) converts instead — the parse decides, so city search is untouched.
    private static func snapshot(
        store: WorldClockStore, query: String
    ) -> PluginPaletteSnapshot {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        switch store.screenIntent(for: trimmed) {
        case .conversion(let conversion):
            return conversionSnapshot(conversion, store: store)
        case .unresolvedCity(let phrase):
            return PluginPaletteSnapshot(
                sectionTitle: "Convert Time", items: [],
                emptyMessage: phrase.isEmpty
                    ? "Name a city after the time, for example “8pm in London”."
                    : "No city called “\(displayPhrase(phrase))” — try another name.")
        case .citySearch:
            break
        }
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
                icon: rowIcon(for: city, store: store, fallback: "clock"),
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
                    icon: rowIcon(for: city, store: store, fallback: "plus.circle"),
                    primaryActionTitle: "Add City")
            }
        }
        return finishSnapshot(items: items, store: store, trimmed: trimmed)
    }

    /// The converted instant in every configured city, in saved order, plus the Mac's own zone.
    private static func conversionSnapshot(
        _ conversion: WorldClockConversion, store: WorldClockStore
    ) -> PluginPaletteSnapshot {
        let items = conversion.rows.map { row in
            PluginPaletteItem(
                id: row.id,
                title: row.name,
                subtitle: row.date + " · " + row.timeZoneIdentifier,
                icon: store.flag(forTimeZoneIdentifier: row.timeZoneIdentifier)
                    .map(PluginPaletteIcon.emoji) ?? .symbol(row.isLocal ? "house" : "clock"),
                accessories: [
                    PluginPaletteAccessory(systemImage: "clock.fill", text: row.time)
                ],
                primaryActionTitle: "Copy Time")
        }
        return PluginPaletteSnapshot(
            sectionTitle: conversion.headline, items: items,
            emptyMessage: "No cities to convert into.")
    }

    private static func displayPhrase(_ phrase: String) -> String {
        phrase.split(separator: " ").map { $0.capitalized }.joined(separator: " ")
    }

    /// The city's country flag where the tz table places it; the symbol is only the fallback.
    private static func rowIcon(
        for city: WorldClockCity, store: WorldClockStore, fallback: String
    ) -> PluginPaletteIcon {
        store.flag(forTimeZoneIdentifier: city.timeZoneIdentifier).map(PluginPaletteIcon.emoji)
            ?? .symbol(fallback)
    }

    private static func finishSnapshot(
        items: [PluginPaletteItem], store: WorldClockStore, trimmed: String
    ) -> PluginPaletteSnapshot {
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
        showPalette(mode: .plugin(.worldClock))
    }

    func copyWorldClockTime(cityID: String) {
        guard let result = worldClock.result(for: cityID)
        else { return }
        hidePalette(restoreFocus: false)
        Paster.copyPlainText(result.time)
    }

    /// Conversion rows carry no state of their own: the live query is re-read, so the row a menu or
    /// ↵ names is always the one the list is showing.
    func worldClockConversionRow(id: String) -> WorldClockConversionRow? {
        guard case .conversion(let conversion) = worldClock.screenIntent(
                for: palette.query.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return nil }
        return conversion.rows.first { $0.id == id }
    }

    func copyWorldClockConvertedTime(rowID: String) {
        guard let row = worldClockConversionRow(id: rowID) else { return }
        hidePalette(restoreFocus: false)
        Paster.copyPlainText(row.time)
    }

    /// Adds a catalog city from its "Add City" row, clearing the query so the grown list shows.
    func addWorldClockCity(id: String) {
        guard let city = WorldClockEngine.city(id: id) else {
            return
        }
        worldClock.add(city)
        palette.query = ""
        palette.selection = 0
    }
}
