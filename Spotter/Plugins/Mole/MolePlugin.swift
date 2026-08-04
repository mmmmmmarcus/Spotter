import AppKit
import Combine
import SwiftUI

extension PluginActionKey {
    static let openMoleStatus = standard(
        pluginID: .mole, actionID: "status", title: "Mole System Status")
    static let openMoleHistory = standard(
        pluginID: .mole, actionID: "history", title: "Mole Cleanup History")
}

@MainActor
enum MolePlugin {
    static func registration(core: AppCore) -> PluginRegistration {
        let screen = PluginPaletteScreenRegistration(
            placeholder: "Filter Mole results…",
            snapshot: { [weak core] query in
                guard let core else {
                    return PluginPaletteSnapshot(
                        sectionTitle: "Mole", items: [], emptyMessage: "Plugin unavailable")
                }
                return MoleResults.snapshot(manager: core.mole, query: query)
            },
            performPrimaryAction: { [weak core] itemID in
                core?.copyMoleRow(itemID: itemID)
            },
            actions: { [weak core] _ in
                guard let core else { return nil }
                return PopoverMenuContent(
                    header: "Mole",
                    items: [
                        PopoverMenuItem(
                            title: "Refresh", systemImage: "arrow.clockwise", shortcut: "⌘R"
                        ) { core.mole.reload() },
                        PopoverMenuItem(title: "System Status", systemImage: "waveform.path.ecg") {
                            core.mole.open(.status)
                        },
                        PopoverMenuItem(
                            title: "Cleanup History", systemImage: "clock.arrow.circlepath"
                        ) { core.mole.open(.history) },
                    ])
            },
            onClose: { [weak core] in core?.mole.stop() },
            observeChanges: { [weak core] invalidate in
                core?.mole.objectWillChange.sink { invalidate() } ?? AnyCancellable {}
            })

        return PluginRegistration(
            metadata: PluginMetadata(
                id: .mole,
                name: "Mole",
                summary: "Drive the Mole CLI: system health and cleanup history in the palette, deeper commands in Terminal.",
                systemImage: "chart.pie",
                tint: .green),
            defaultEnabled: false,
            shortcutActions: [
                PluginActionRegistration(key: .openMoleStatus) { core.openMole(.status) },
                PluginActionRegistration(key: .openMoleHistory) { core.openMole(.history) },
            ],
            launcherCommands: MoleCommand.allCases.map { command in
                PluginCommandRegistration(
                    id: command.commandID,
                    name: command.title,
                    systemImage: command.systemImage,
                    // Only the two rendered screens are primary; the TUI hand-offs ship hidden so the launcher stays compact.
                    defaultVisible: command.rendersInPalette
                ) { core.runMole(command) }
            },
            paletteScreen: screen,
            onDisable: { [weak core] in
                core?.mole.stop()
                if core?.palette.mode == .plugin(.mole) {
                    core?.palette.prepare(mode: .launcher)
                }
            },
            settingsView: { AnyView(MoleSettingsView()) })
    }
}

/// Turns manager state into palette rows. Pure mapping — no I/O — so the screen stays a snapshot.
@MainActor
enum MoleResults {
    static func snapshot(manager: MoleManager, query: String) -> PluginPaletteSnapshot {
        let section = manager.screen == .status ? "Mole · System Status" : "Mole · Cleanup History"
        switch manager.state {
        case .idle:
            return PluginPaletteSnapshot(
                sectionTitle: section, items: [], emptyMessage: "Loading Mole…")
        case .loading:
            return PluginPaletteSnapshot(
                sectionTitle: section, items: [], isLoading: true,
                loadingMessage: "Asking Mole…", emptyMessage: "Asking Mole…")
        case .failed(let message):
            return PluginPaletteSnapshot(
                sectionTitle: section, items: [], errorMessage: message, emptyMessage: message)
        case .status(let status):
            var items = [
                PluginPaletteItem(
                    id: "health",
                    title: "Health Score \(status.healthScore)",
                    subtitle: status.healthMessage,
                    icon: .symbol("heart.text.square"),
                    accessories: [.init(systemImage: "gauge", text: "\(status.healthScore)/100")],
                    primaryActionTitle: "Copy Value")
            ]
            items += status.rows.map { row in
                PluginPaletteItem(
                    id: "row:" + row.title,
                    title: row.title,
                    subtitle: row.detail.isEmpty ? nil : row.detail,
                    icon: .symbol("circle.fill"),
                    accessories: [.init(systemImage: "number", text: row.value)],
                    primaryActionTitle: "Copy Value")
            }
            return PluginPaletteSnapshot(
                sectionTitle: section, items: filtered(items, query: query),
                emptyMessage: "No matching status rows")
        case .history(let entries):
            guard !entries.isEmpty else {
                return PluginPaletteSnapshot(
                    sectionTitle: section, items: [],
                    emptyMessage: "No cleanup history yet — run Mole Clean to create some.")
            }
            let items = entries.enumerated().map { index, entry in
                PluginPaletteItem(
                    id: "history:\(index)",
                    title: "\(entry.command.capitalized) · \(entry.size)",
                    subtitle: "\(entry.startedAt) · \(entry.items) items"
                        + (entry.failedTasks > 0 ? " · \(entry.failedTasks) failed" : ""),
                    icon: .symbol("clock.arrow.circlepath"),
                    primaryActionTitle: "Copy Summary")
            }
            return PluginPaletteSnapshot(
                sectionTitle: section, items: filtered(items, query: query),
                emptyMessage: "No matching history")
        }
    }

    static func copyText(manager: MoleManager, itemID: String) -> String? {
        switch manager.state {
        case .status(let status):
            if itemID == "health" { return "\(status.healthScore) (\(status.healthMessage))" }
            let title = String(itemID.dropFirst("row:".count))
            return status.rows.first { $0.title == title }.map { "\($0.title): \($0.value)" }
        case .history(let entries):
            let index = Int(itemID.dropFirst("history:".count)) ?? -1
            guard entries.indices.contains(index) else { return nil }
            let entry = entries[index]
            return "\(entry.command) \(entry.startedAt): \(entry.items) items, \(entry.size)"
        case .idle, .loading, .failed:
            return nil
        }
    }

    private static func filtered(_ items: [PluginPaletteItem], query: String)
        -> [PluginPaletteItem]
    {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }
        return items.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
                || $0.subtitle?.localizedCaseInsensitiveContains(trimmed) == true
        }
    }
}

extension AppCore {
    func openMole(_ screen: MoleManager.Screen) {
        guard plugins.isEnabled(.mole) else { return }
        mole.open(screen)
        palette.prepare(mode: .plugin(.mole))
        showPalette(mode: .plugin(.mole))
    }

    func runMole(_ command: MoleCommand) {
        guard plugins.isEnabled(.mole) else { return }
        if command.rendersInPalette {
            openMole(command == .status ? .status : .history)
            return
        }
        // A TUI needs a real terminal; hide first so the palette isn't left floating over it.
        hidePalette(restoreFocus: false)
        mole.runInTerminal(command)
    }

    func copyMoleRow(itemID: String) {
        guard let text = MoleResults.copyText(manager: mole, itemID: itemID) else { return }
        hidePalette(restoreFocus: false)
        Paster.copyPlainText(text)
    }
}
