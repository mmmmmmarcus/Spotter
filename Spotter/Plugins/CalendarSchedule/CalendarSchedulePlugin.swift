import AppKit
import Combine
import SwiftUI

extension PluginActionKey {
    static let openCalendarSchedule = standard(
        pluginID: .calendarSchedule, actionID: "open", title: "My Schedule")
}

/// Calendar & meetings: the upcoming days as palette rows, with one keystroke into a meeting's
/// video call. The widget strip's calendar card and this screen are one feature — both read the
/// same `DashboardWidgetsStore` EventKit fetch, and this plugin's Settings pane owns the shared
/// calendar preferences (account, all-day events). Disabling the plugin removes the screen and
/// command only; the card keeps its reading, since widgets have no off switch.
@MainActor
enum CalendarSchedulePlugin {
    static func registration(core: AppCore) -> PluginRegistration {
        let open: () -> Void = { [weak core] in core?.openCalendarSchedule() }
        let screen = PluginPaletteScreenRegistration(
            placeholder: "Search upcoming events…",
            snapshot: { [weak core] query in
                guard let core else {
                    return PluginPaletteSnapshot(
                        sectionTitle: "Schedule", items: [], emptyMessage: "Plugin unavailable")
                }
                return snapshot(store: core.dashboardWidgets, query: query)
            },
            performPrimaryAction: { [weak core] itemID in
                core?.performCalendarScheduleRow(itemID: itemID)
            },
            actions: { [weak core] itemID in
                guard let core else { return nil }
                return menu(core: core, itemID: itemID)
            },
            onOpen: { [weak core] in
                core?.dashboardWidgets.start()
                core?.dashboardWidgets.refresh()
            },
            observeChanges: { [weak core] invalidate in
                core?.dashboardWidgets.objectWillChange.sink { invalidate() } ?? AnyCancellable {}
            })
        return PluginRegistration(
            metadata: PluginMetadata(
                id: .calendarSchedule,
                name: "Calendar",
                summary:
                    "See the days ahead in the launcher and jump straight into a meeting's video call.",
                systemImage: "calendar",
                tint: .red),
            defaultEnabled: true,
            shortcutActions: [PluginActionRegistration(key: .openCalendarSchedule, perform: open)],
            launcherCommands: [
                PluginCommandRegistration(
                    id: "command:calendar-schedule", name: "My Schedule",
                    systemImage: "calendar", actionKey: .openCalendarSchedule, perform: open)
            ],
            paletteScreen: screen,
            onDisable: { [weak core] in
                if core?.palette.mode == .plugin(.calendarSchedule) {
                    core?.palette.prepare(mode: .launcher)
                }
            },
            settingsView: {
                AnyView(CalendarScheduleSettingsView(store: core.dashboardWidgets))
            })
    }

    /// A recurring event reuses one identifier across occurrences, so rows are keyed by identifier plus start time.
    static func rowID(for event: DashboardEvent) -> String {
        event.id + "|" + String(event.startDate.timeIntervalSince1970)
    }

    static func event(store: DashboardWidgetsStore, itemID: String) -> DashboardEvent? {
        store.upcomingEvents.first { rowID(for: $0) == itemID }
    }

    private static func snapshot(
        store: DashboardWidgetsStore, query: String
    ) -> PluginPaletteSnapshot {
        switch store.calendarAccess {
        case .notDetermined, .writeOnly:
            return PluginPaletteSnapshot(
                sectionTitle: "Schedule",
                items: [
                    PluginPaletteItem(
                        id: "request-access",
                        title: "Allow Calendar Access",
                        subtitle:
                            "Spotter reads events on this Mac only; nothing leaves the machine.",
                        icon: .symbol("calendar.badge.plus"),
                        primaryActionTitle: "Allow")
                ],
                emptyMessage: "Calendar access has not been granted.")
        case .denied, .restricted:
            return PluginPaletteSnapshot(
                sectionTitle: "Schedule",
                items: [
                    PluginPaletteItem(
                        id: "open-settings",
                        title: "Calendar access is off",
                        subtitle: "Grant Full Calendar Access in System Settings → Privacy.",
                        icon: .symbol("exclamationmark.triangle"),
                        primaryActionTitle: "Open System Settings")
                ],
                emptyMessage: "Calendar access is off.")
        case .fullAccess:
            break
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()
        let calendar = Calendar.current
        let visible = store.upcomingEvents.filter { event in
            trimmed.isEmpty
                || event.title.localizedCaseInsensitiveContains(trimmed)
                || event.calendarTitle.localizedCaseInsensitiveContains(trimmed)
                || event.location?.localizedCaseInsensitiveContains(trimmed) == true
        }
        let items = visible.map { event -> PluginPaletteItem in
            let link = CalendarScheduleEngine.meetingLink(
                urlString: event.urlString, location: event.location, notes: event.notes)
            var subtitleParts = [
                CalendarScheduleEngine.dayLabel(for: event.startDate, now: now, calendar: calendar),
                CalendarScheduleEngine.timeLabel(
                    start: event.startDate, end: event.endDate, isAllDay: event.isAllDay,
                    calendar: calendar),
                event.calendarTitle,
            ]
            if let location = event.location, link == nil { subtitleParts.append(location) }
            var accessories: [PluginPaletteAccessory] = []
            if let link {
                accessories.append(
                    PluginPaletteAccessory(systemImage: "video.fill", text: link.provider))
            }
            return PluginPaletteItem(
                id: rowID(for: event),
                title: event.title,
                subtitle: subtitleParts.joined(separator: " · "),
                icon: link == nil
                    ? .tintedSymbol("calendar", tint: .red)
                    : .tintedSymbol("video.fill", tint: .green),
                accessories: accessories,
                primaryActionTitle: link == nil ? "Open Calendar" : "Join Meeting")
        }
        return PluginPaletteSnapshot(
            sectionTitle: "Schedule", items: items,
            emptyMessage: store.upcomingEvents.isEmpty
                ? "Nothing scheduled in the next two weeks."
                : "No matching event.")
    }

    private static func menu(core: AppCore, itemID: String) -> PopoverMenuContent? {
        guard let event = event(store: core.dashboardWidgets, itemID: itemID) else { return nil }
        let link = CalendarScheduleEngine.meetingLink(
            urlString: event.urlString, location: event.location, notes: event.notes)
        var items: [PopoverMenuItem] = []
        if let link {
            items.append(
                PopoverMenuItem(title: "Join \(link.provider)", systemImage: "video", shortcut: "↵") {
                    core.openCalendarMeetingLink(link.urlString)
                })
        }
        items.append(
            PopoverMenuItem(
                title: "Open Calendar", systemImage: "calendar",
                shortcut: link == nil ? "↵" : nil
            ) { core.openCalendarApp() })
        if let link {
            items.append(
                PopoverMenuItem(title: "Copy Meeting Link", systemImage: "doc.on.doc") {
                    core.hidePalette(restoreFocus: false)
                    Paster.copyPlainText(link.urlString)
                })
        }
        items.append(
            PopoverMenuItem(title: "Copy Event Title", systemImage: "textformat") {
                core.hidePalette(restoreFocus: false)
                Paster.copyPlainText(event.title)
            })
        return PopoverMenuContent(header: event.title, items: items)
    }
}

extension AppCore {
    func openCalendarSchedule() {
        guard plugins.isEnabled(.calendarSchedule) else { return }
        showPalette(mode: .plugin(.calendarSchedule))
    }

    /// Hides the palette and fronts Calendar; shared by the widget card's click and the schedule rows.
    func openCalendarApp() {
        hidePalette(restoreFocus: false)
        guard
            let url = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: "com.apple.iCal")
        else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func openCalendarMeetingLink(_ urlString: String) {
        hidePalette(restoreFocus: false)
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    func performCalendarScheduleRow(itemID: String) {
        guard plugins.isEnabled(.calendarSchedule) else { return }
        switch itemID {
        case "request-access":
            dashboardWidgets.requestCalendarAccess()
        case "open-settings":
            hidePalette(restoreFocus: false)
            Permissions.openCalendarSettings()
        default:
            guard let event = CalendarSchedulePlugin.event(
                store: dashboardWidgets, itemID: itemID)
            else { return }
            let link = CalendarScheduleEngine.meetingLink(
                urlString: event.urlString, location: event.location, notes: event.notes)
            if let link {
                openCalendarMeetingLink(link.urlString)
            } else {
                openCalendarApp()
            }
        }
    }
}
