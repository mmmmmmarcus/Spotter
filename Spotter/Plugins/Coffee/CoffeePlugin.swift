import AppKit
import Combine
import SwiftUI

extension PluginActionKey {
    static let coffeeStart = standard(pluginID: .coffee, actionID: "start", title: "Caffeinate")
    static let coffeeStatus = standard(
        pluginID: .coffee, actionID: "status", title: "Caffeination Status")
    static let coffeeStop = standard(pluginID: .coffee, actionID: "stop", title: "Decaffeinate")
    static let coffeeFor = standard(
        pluginID: .coffee, actionID: "for", title: "Caffeinate For…")
    static let coffeeWhile = standard(
        pluginID: .coffee, actionID: "while", title: "Caffeinate While App Runs…")
}

@MainActor
enum CoffeePlugin {
    static func registration(core: AppCore) -> PluginRegistration {
        let screen = PluginPaletteScreenRegistration(
            placeholder: "Choose how long to stay awake…",
            snapshot: { [weak core] query in
                guard let core else {
                    return PluginPaletteSnapshot(
                        sectionTitle: "Caffeinate", items: [], emptyMessage: "Plugin unavailable")
                }
                return CoffeeResults.snapshot(core: core, query: query)
            },
            performPrimaryAction: { [weak core] itemID in
                core?.performCoffeeRow(itemID: itemID)
            },
            actions: { [weak core] _ in
                guard let core else { return nil }
                var items = [
                    PopoverMenuItem(title: "Caffeinate", systemImage: "cup.and.saucer.fill") {
                        core.coffee.caffeinate()
                        core.hidePalette(restoreFocus: false)
                    }
                ]
                if core.coffee.isOn {
                    items.append(
                        PopoverMenuItem(title: "Decaffeinate", systemImage: "moon.zzz") {
                            core.coffee.decaffeinate()
                            core.hidePalette(restoreFocus: false)
                        })
                }
                return PopoverMenuContent(header: "Caffeinate", items: items)
            },
            observeChanges: { [weak core] invalidate in
                core?.coffee.objectWillChange.sink { invalidate() } ?? AnyCancellable {}
            })

        return PluginRegistration(
            // Display-renamed from "Coffee"; the id keeps its raw value so persisted enable state
            // and `KeyboardShortcuts_plugin.coffee.*` bindings survive the rename.
            metadata: PluginMetadata(
                id: .coffee,
                name: "Caffeinate",
                summary: "Keep your Mac awake — indefinitely, for a set time, or while an app runs.",
                systemImage: "cup.and.saucer",
                tint: .orange),
            defaultEnabled: true,
            shortcutActions: [
                PluginActionRegistration(key: .coffeeStart) { core.startCoffee() },
                PluginActionRegistration(key: .coffeeStop) { core.stopCoffee() },
                PluginActionRegistration(key: .coffeeFor) { core.openCoffeeScreen(.duration) },
                PluginActionRegistration(key: .coffeeWhile) { core.openCoffeeScreen(.app) },
                PluginActionRegistration(key: .coffeeStatus) { core.openCoffeeScreen(.status) },
            ],
            launcherCommands: [
                PluginCommandRegistration(
                    id: "command:coffee:start", name: "Caffeinate",
                    systemImage: "cup.and.saucer.fill", actionKey: .coffeeStart
                ) { core.startCoffee() },
                PluginCommandRegistration(
                    id: "command:coffee:stop", name: "Decaffeinate", systemImage: "moon.zzz",
                    actionKey: .coffeeStop
                ) { core.stopCoffee() },
                PluginCommandRegistration(
                    id: "command:coffee:for", name: "Caffeinate For…", systemImage: "timer",
                    actionKey: .coffeeFor
                ) { core.openCoffeeScreen(.duration) },
                PluginCommandRegistration(
                    id: "command:coffee:while", name: "Caffeinate While App Runs…",
                    systemImage: "app.badge.checkmark", actionKey: .coffeeWhile
                ) { core.openCoffeeScreen(.app) },
                PluginCommandRegistration(
                    id: "command:coffee:status", name: "Caffeination Status",
                    systemImage: "info.circle", actionKey: .coffeeStatus
                ) { core.openCoffeeScreen(.status) },
            ],
            paletteScreen: screen,
            // Leaving the assertion held after the user turned the plugin off would be a lie about what's running.
            onDisable: { [weak core] in
                core?.coffee.decaffeinate()
                if core?.palette.mode == .plugin(.coffee) {
                    core?.palette.prepare(mode: .launcher)
                }
            },
            settingsView: { AnyView(CoffeeSettingsView()) })
    }
}

/// Which list the shared palette screen is currently showing.
enum CoffeeScreen: Equatable {
    case status
    case duration
    case app
}

@MainActor
enum CoffeeResults {
    static func snapshot(core: AppCore, query: String) -> PluginPaletteSnapshot {
        let coffee = core.coffee
        switch core.coffeeScreen {
        case .status:
            let remaining = coffee.remaining.map { " · \($0) left" } ?? ""
            let items = [
                PluginPaletteItem(
                    id: "status",
                    title: coffee.isOn ? "Caffeinated" : "Not Caffeinated",
                    subtitle: coffee.state.summary + remaining,
                    icon: .symbol(coffee.isOn ? "cup.and.saucer.fill" : "moon.zzz"),
                    primaryActionTitle: coffee.isOn ? "Decaffeinate" : "Caffeinate")
            ]
            return PluginPaletteSnapshot(
                sectionTitle: "Caffeinate", items: filtered(items, query: query),
                emptyMessage: "No matching result")
        case .duration:
            let items = CoffeeDuration.allCases.map { duration in
                PluginPaletteItem(
                    id: "duration:" + duration.rawValue,
                    title: duration.title,
                    subtitle: "Stay awake for \(duration.title), then sleep normally",
                    icon: .symbol("timer"),
                    primaryActionTitle: "Caffeinate")
            }
            return PluginPaletteSnapshot(
                sectionTitle: "Caffeinate For", items: filtered(items, query: query),
                emptyMessage: "No matching duration")
        case .app:
            // Only apps with a UI can meaningfully be watched, and Spotter itself would never end.
            let apps = NSWorkspace.shared.runningApplications.filter {
                $0.activationPolicy == .regular
                    && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
                    && $0.localizedName != nil
            }
            let items = apps.map { app in
                PluginPaletteItem(
                    id: "app:\(app.processIdentifier)",
                    title: app.localizedName ?? "App",
                    subtitle: "Stay awake until \(app.localizedName ?? "it") quits",
                    icon: app.bundleURL.map { PluginPaletteIcon.file(path: $0.path) }
                        ?? .symbol("app"),
                    primaryActionTitle: "Caffeinate While Running")
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            return PluginPaletteSnapshot(
                sectionTitle: "Caffeinate While", items: filtered(items, query: query),
                emptyMessage: "No running applications")
        }
    }

    private static func filtered(_ items: [PluginPaletteItem], query: String)
        -> [PluginPaletteItem]
    {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }
        return items.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }
}

extension AppCore {
    func toggleCoffee() {
        guard plugins.isEnabled(.coffee) else { return }
        coffee.toggle()
        hidePalette(restoreFocus: false)
    }

    func startCoffee() {
        guard plugins.isEnabled(.coffee) else { return }
        coffee.caffeinate()
        hidePalette(restoreFocus: false)
    }

    func stopCoffee() {
        guard plugins.isEnabled(.coffee) else { return }
        coffee.decaffeinate()
        hidePalette(restoreFocus: false)
    }

    func openCoffeeScreen(_ screen: CoffeeScreen) {
        guard plugins.isEnabled(.coffee) else { return }
        coffeeScreen = screen
        palette.prepare(mode: .plugin(.coffee))
        showPalette(mode: .plugin(.coffee))
    }

    func performCoffeeRow(itemID: String) {
        guard plugins.isEnabled(.coffee) else { return }
        if itemID == "status" {
            coffee.toggle()
        } else if itemID.hasPrefix("duration:"),
            let duration = CoffeeDuration(rawValue: String(itemID.dropFirst("duration:".count)))
        {
            coffee.caffeinate(for: duration)
        } else if itemID.hasPrefix("app:"),
            let pid = Int32(itemID.dropFirst("app:".count)),
            let app = NSRunningApplication(processIdentifier: pid)
        {
            coffee.caffeinate(whileRunning: app)
        }
        hidePalette(restoreFocus: false)
    }
}
