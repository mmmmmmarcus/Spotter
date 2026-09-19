import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

extension PluginActionKey {
    static let openCalendarSchedule = standard(
        pluginID: .calendarSchedule, actionID: "open", title: "Schedule")
}

/// The calendar canvas and widget share account preferences and calendar authorization.
@MainActor
enum CalendarSchedulePlugin {
    static func registration(core: AppCore) -> PluginRegistration {
        let open: () -> Void = { [weak core] in core?.openCalendarSchedule() }
        let screen = PluginPaletteScreenRegistration(
            placeholder: "Search events…",
            canvas: { [weak core] context in
                guard let core, core.dashboardWidgets.calendarAccess.canRead else { return nil }
                return AnyView(CalendarScheduleView(
                    model: core.calendarSchedule, dashboard: core.dashboardWidgets, context: context))
            },
            handleBack: { [weak core] in
                guard let model = core?.calendarSchedule, model.detailID != nil else { return false }
                model.detailID = nil
                return true
            },
            snapshot: { [weak core] query in
                guard let core else {
                    return PluginPaletteSnapshot(
                        sectionTitle: "Schedule", items: [], emptyMessage: "Plugin unavailable")
                }
                return snapshot(store: core.dashboardWidgets, model: core.calendarSchedule, query: query)
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
                if let core { core.calendarSchedule.open(dashboard: core.dashboardWidgets) }
            },
            onClose: { [weak core] in core?.calendarSchedule.close() },
            observeChanges: { [weak core] invalidate in
                guard let core else { return AnyCancellable {} }
                return Publishers.Merge(core.dashboardWidgets.objectWillChange,
                                        core.calendarSchedule.objectWillChange).sink { invalidate() }
            })
        return PluginRegistration(
            metadata: PluginMetadata(
                id: .calendarSchedule,
                name: "Schedule",
                summary:
                    "Browse your week or month inside the launcher.",
                systemImage: "calendar",
                tint: .red),
            shortcutActions: [PluginActionRegistration(key: .openCalendarSchedule, perform: open)],
            launcherCommands: [
                PluginCommandRegistration(
                    id: "command:calendar-schedule", name: "Schedule",
                    systemImage: "calendar", actionKey: .openCalendarSchedule, perform: open)
            ],
            paletteScreen: screen,
            settingsView: {
                AnyView(CalendarScheduleSettingsView(store: core.dashboardWidgets))
            })
    }

    /// A recurring event reuses one identifier across occurrences, so rows are keyed by identifier plus start time.
    static func rowID(for event: DashboardEvent) -> String {
        event.id + "|" + String(event.startDate.timeIntervalSince1970)
    }

    static func dayID(_ date: Date) -> String { "day:" + String(date.timeIntervalSince1970) }

    static func event(store: CalendarScheduleStore, itemID: String) -> DashboardEvent? {
        let eventID = positions(model: store, query: "").first { $0.id == itemID }?.eventID ?? itemID
        return store.events.first { rowID(for: $0) == eventID }
    }

    static func positions(model: CalendarScheduleStore, query: String) -> [ScheduleEventPosition] {
        let events = model.matching(query)
        return ScheduleNavigation.ordered(model.days.flatMap { day in
            events.compactMap { event in
                guard let block = ScheduleLayout.block(
                    id: rowID(for: event), start: event.startDate, end: event.endDate,
                    day: day, calendar: model.calendar) else { return nil }
                return ScheduleEventPosition(eventID: block.id, day: day,
                    startMinute: event.isAllDay ? 0 : block.startMinute, isAllDay: event.isAllDay)
            }
        })
    }

    private static func snapshot(
        store: DashboardWidgetsStore, model: CalendarScheduleStore, query: String
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

        let now = Date()
        let calendar = model.calendar
        if model.mode == .month, model.detailID == nil {
            return PluginPaletteSnapshot(sectionTitle: "Schedule", items: model.days.map { day in
                PluginPaletteItem(id: dayID(day), title: day.formatted(date: .complete, time: .omitted),
                                  subtitle: "", icon: .symbol("calendar"), primaryActionTitle: "View Week")
            }, emptyMessage: "No events this month.")
        }
        let byID = Dictionary(model.events.map { (rowID(for: $0), $0) }, uniquingKeysWith: { first, _ in first })
        let visible: [(id: String, eventID: String)] = model.detailID.map { [(id: $0, eventID: $0)] }
            ?? positions(model: model, query: query).map { (id: $0.id, eventID: $0.eventID) }
        let items = visible.compactMap { position -> PluginPaletteItem? in
            guard let event = byID[position.eventID] else { return nil }
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
                id: position.id,
                title: event.title,
                subtitle: subtitleParts.joined(separator: " · "),
                icon: link == nil
                    ? .tintedSymbol("calendar", tint: .red)
                    : .tintedSymbol("video.fill", tint: .green),
                accessories: accessories,
                primaryActionTitle: model.detailID == nil ? "View Event" : "Back to Schedule")
        }
        return PluginPaletteSnapshot(
            sectionTitle: "Schedule", items: items,
            isLoading: model.isLoading, emptyMessage: "No events in this period.")
    }

    private static func menu(core: AppCore, itemID: String) -> PopoverMenuContent? {
        guard let event = event(store: core.calendarSchedule, itemID: itemID) else { return nil }
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
    func handleCalendarScheduleKey(_ event: NSEvent) -> Bool {
        guard palette.mode == .plugin(.calendarSchedule), dashboardWidgets.calendarAccess.canRead else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if modifiers == .command {
            switch event.charactersIgnoringModifiers {
            case "[": calendarSchedule.move(-1)
            case "]": calendarSchedule.move(1)
            default: return false
            }
            palette.selection = 0
            return true
        }
        guard modifiers.isEmpty, calendarSchedule.detailID == nil else { return false }
        let direction: ScheduleDirection
        switch Int(event.keyCode) {
        case kVK_UpArrow: direction = .up
        case kVK_DownArrow: direction = .down
        case kVK_LeftArrow: direction = .left
        case kVK_RightArrow: direction = .right
        default: return false
        }
        let items = plugins.paletteSnapshot(for: .calendarSchedule, query: palette.query)?.items ?? []
        guard !items.isEmpty else { return true }
        let selection = min(max(palette.selection, 0), items.count - 1)
        if calendarSchedule.mode == .month {
            if let next = ScheduleNavigation.monthNeighbor(
                from: selection, direction: direction, count: items.count) {
                palette.selection = next
            }
        } else {
            let selectedID = items[selection].id
            let positions = CalendarSchedulePlugin.positions(model: calendarSchedule, query: palette.query)
            if let next = ScheduleNavigation.neighbor(in: positions, selectedID: selectedID, direction: direction),
               let index = items.firstIndex(where: { $0.id == next }) {
                palette.selection = index
            }
        }
        return true
    }

    func openCalendarSchedule() {
        showPalette(mode: .plugin(.calendarSchedule))
    }

    /// An explicit event action for opening the system Calendar app.
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
        switch itemID {
        case "request-access":
            dashboardWidgets.requestCalendarAccess()
        case "open-settings":
            hidePalette(restoreFocus: false)
            Permissions.openCalendarSettings()
        default:
            if let day = calendarSchedule.days.first(where: { CalendarSchedulePlugin.dayID($0) == itemID }) {
                calendarSchedule.showWeek(containing: day)
                return
            }
            guard let event = CalendarSchedulePlugin.event(
                store: calendarSchedule, itemID: itemID)
            else { return }
            calendarSchedule.detailID = calendarSchedule.detailID == nil
                ? CalendarSchedulePlugin.rowID(for: event) : nil
        }
    }
}
