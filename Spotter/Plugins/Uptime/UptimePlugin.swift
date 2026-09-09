import Combine
import SwiftUI

extension PluginActionKey {
    static let openUptime = standard(pluginID: .uptime, actionID: "open", title: "Uptime")
}

@MainActor
enum UptimePlugin {
    /// Row identities, so the actions menu and the primary action can tell the three rows apart
    /// without matching on their titles.
    private enum Row {
        static let session = "uptime:session"
        static let keys = "uptime:keys"
        static let clicks = "uptime:clicks"
    }

    static func registration(core: AppCore) -> PluginRegistration {
        let open: () -> Void = { [weak core] in core?.openUptime() }
        let screen = PluginPaletteScreenRegistration(
            placeholder: "Today's session, keys and clicks…",
            snapshot: { [weak core] query in
                guard let core else {
                    return PluginPaletteSnapshot(
                        sectionTitle: "Uptime", items: [], emptyMessage: "Plugin unavailable")
                }
                return snapshot(store: core.uptime, query: query)
            },
            performPrimaryAction: { [weak core] itemID in
                core?.copyUptimeRow(id: itemID)
            },
            actions: { [weak core] itemID in
                guard let core else { return nil }
                return PopoverMenuContent(
                    header: "Uptime",
                    items: [
                        PopoverMenuItem(
                            title: "Copy", systemImage: "doc.on.doc", shortcut: "↵"
                        ) { core.copyUptimeRow(id: itemID) },
                        PopoverMenuItem(
                            title: "Reset Today", systemImage: "arrow.counterclockwise",
                            isDestructive: true
                        ) { core.confirmUptimeReset() },
                    ])
            },
            observeChanges: { [weak core] invalidate in
                // The tallies deliberately do not publish — they move at typing speed. The palette
                // re-reads them on its own; this only carries Accessibility-trust changes.
                core?.uptime.objectWillChange.sink { invalidate() } ?? AnyCancellable {}
            })
        return PluginRegistration(
            metadata: PluginMetadata(
                id: .uptime,
                name: "Uptime",
                summary: "How long today's session has run, with the day's key and click counts.",
                systemImage: "timer",
                tint: .green),
            // Counting keys needs the grant; clicks do not. The rows say so rather than reporting
            // a keyboard that looks idle.
            permissions: [.accessibility],
            shortcutActions: [PluginActionRegistration(key: .openUptime, perform: open)],
            launcherCommands: [
                PluginCommandRegistration(
                    id: "command:uptime", name: "Uptime", systemImage: "timer",
                    actionKey: .openUptime, perform: open)
            ],
            paletteScreen: screen,
            settingsView: { AnyView(UptimeSettingsView(store: core.uptime)) })
    }

    private static func snapshot(store: UptimeStore, query: String) -> PluginPaletteSnapshot {
        let now = Date()
        let snapshot = store.snapshot(now: now)
        let elapsed = snapshot.sessionStart
            .map { UptimeEngine.formattedElapsed(from: $0, to: now) } ?? "—"
        var items = [
            PluginPaletteItem(
                id: Row.session,
                title: "Session",
                subtitle: snapshot.sessionStart
                    .map { "Since " + $0.formatted(date: .omitted, time: .shortened) }
                    ?? "Nothing counted yet today",
                icon: .symbol("timer"),
                accessories: [PluginPaletteAccessory(systemImage: "clock.fill", text: elapsed)],
                primaryActionTitle: "Copy"),
            PluginPaletteItem(
                id: Row.keys,
                title: "Keys Pressed",
                subtitle: store.needsAccessibility
                    ? "Needs Accessibility — clicks still count without it."
                    : "Today, autorepeat excluded",
                icon: .symbol("keyboard"),
                accessories: [
                    PluginPaletteAccessory(
                        systemImage: "number", text: UptimeEngine.formattedCount(snapshot.counts.keys))
                ],
                primaryActionTitle: "Copy"),
            PluginPaletteItem(
                id: Row.clicks,
                title: "Mouse Clicks",
                subtitle: "Today",
                icon: .symbol("cursorarrow.click"),
                accessories: [
                    PluginPaletteAccessory(
                        systemImage: "number",
                        text: UptimeEngine.formattedCount(snapshot.counts.clicks))
                ],
                primaryActionTitle: "Copy"),
        ]
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            items = items.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
        }
        return PluginPaletteSnapshot(
            sectionTitle: "Today", items: items,
            emptyMessage: trimmed.isEmpty ? "Nothing counted yet today." : "No matching reading.")
    }

    /// The value each row copies, so the palette and the actions menu can't disagree about it.
    static func copyableValue(rowID: String, store: UptimeStore, now: Date = Date()) -> String? {
        let snapshot = store.snapshot(now: now)
        switch rowID {
        case Row.session:
            return snapshot.sessionStart.map { UptimeEngine.formattedElapsed(from: $0, to: now) }
        case Row.keys:
            return UptimeEngine.formattedCount(snapshot.counts.keys)
        case Row.clicks:
            return UptimeEngine.formattedCount(snapshot.counts.clicks)
        default:
            return nil
        }
    }
}

extension AppCore {
    func openUptime() {
        showPalette(mode: .plugin(.uptime))
    }

    func copyUptimeRow(id: String) {
        guard let value = UptimePlugin.copyableValue(rowID: id, store: uptime)
        else { return }
        hidePalette(restoreFocus: false)
        Paster.copyPlainText(value)
    }

    func confirmUptimeReset() {
        confirmInPalette(
            PaletteConfirmation(
                title: "Reset Today",
                message: "Clears today's key and click counts. The session start is kept.",
                actionTitle: "Reset"
            ) { [weak self] in
                self?.uptime.resetCounts()
            })
    }
}
