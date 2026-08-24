import Combine
import EventKit
import Foundation

enum DashboardCalendarAccess: Equatable, Sendable {
    case notDetermined
    case denied
    case restricted
    case writeOnly
    case fullAccess

    var canRead: Bool { self == .fullAccess }
}

@MainActor
final class DashboardWidgetsStore: ObservableObject {
    private enum Keys {
        static let widgetOrder = "dashboard-widgets.widget-order"
        static let calendarSource = "dashboard-widgets.calendar-source"
        static let includesAllDayEvents = "dashboard-widgets.includes-all-day-events"
        static let clockTimeZone = "dashboard-widgets.clock-time-zone"
    }

    @Published private(set) var preferences: DashboardWidgetPreferences
    @Published private(set) var calendarAccess: DashboardCalendarAccess
    @Published private(set) var calendarAccounts: [DashboardCalendarAccount] = []
    @Published private(set) var nextEvent: DashboardEvent?
    @Published private(set) var isRequestingCalendarAccess = false

    private let defaults: UserDefaults
    private let eventStore: EKEventStore
    private var refreshTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard, eventStore: EKEventStore = EKEventStore()) {
        self.defaults = defaults
        self.eventStore = eventStore
        calendarAccess = Self.currentCalendarAccess()
        preferences = DashboardWidgetPreferences(
            widgetOrder: DashboardWidgetsEngine.widgetOrder(
                from: defaults.stringArray(forKey: Keys.widgetOrder)),
            calendarSourceIdentifier: defaults.string(forKey: Keys.calendarSource)?.nilIfEmpty,
            includesAllDayEvents: defaults.object(forKey: Keys.includesAllDayEvents) == nil
                || defaults.bool(forKey: Keys.includesAllDayEvents),
            clockTimeZoneIdentifier: defaults.string(forKey: Keys.clockTimeZone)?.nilIfEmpty)
    }

    var clockTimeZone: TimeZone {
        DashboardWidgetsEngine.resolvedTimeZone(
            identifier: preferences.clockTimeZoneIdentifier, fallback: .autoupdatingCurrent)
    }

    /// Strip order, complete and repaired — every kind exactly once, whether shown or not.
    var orderedWidgets: [DashboardWidgetKind] { preferences.widgetOrder }

    /// Places `widget` at `destination` in the current order — see `DashboardWidgetsEngine.reorder`.
    func moveWidget(_ widget: DashboardWidgetKind, to destination: Int) {
        var updated = preferences
        updated.widgetOrder = DashboardWidgetsEngine.reorder(
            preferences.widgetOrder, moving: widget, to: destination)
        updatePreferences(updated)
    }

    func setCalendarSourceIdentifier(_ identifier: String?) {
        var updated = preferences
        updated.calendarSourceIdentifier = identifier?.nilIfEmpty
        updatePreferences(updated)
    }

    func setIncludesAllDayEvents(_ included: Bool) {
        var updated = preferences
        updated.includesAllDayEvents = included
        updatePreferences(updated)
    }

    func setClockTimeZoneIdentifier(_ identifier: String?) {
        var updated = preferences
        updated.clockTimeZoneIdentifier = TimeZone(identifier: identifier ?? "") == nil
            ? nil : identifier
        updatePreferences(updated)
    }

    @discardableResult
    func applyPreferences(
        widgetOrderRawValues: [String]?, calendarSourceIdentifier: String?,
        includesAllDayEvents: Bool?, clockTimeZoneIdentifier: String?
    ) -> Int {
        var updated = preferences
        var count = 0
        if let widgetOrderRawValues {
            updated.widgetOrder = DashboardWidgetsEngine.widgetOrder(from: widgetOrderRawValues)
            count += 1
        }
        if let calendarSourceIdentifier {
            updated.calendarSourceIdentifier = calendarSourceIdentifier.nilIfEmpty
            count += 1
        }
        if let includesAllDayEvents {
            updated.includesAllDayEvents = includesAllDayEvents
            count += 1
        }
        if let clockTimeZoneIdentifier {
            updated.clockTimeZoneIdentifier = TimeZone(identifier: clockTimeZoneIdentifier) == nil
                ? nil : clockTimeZoneIdentifier
            count += 1
        }
        updatePreferences(updated)
        return count
    }

    func start() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    break
                }
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refresh() {
        refreshCalendar()
    }

    func requestCalendarAccess() {
        guard !isRequestingCalendarAccess,
            calendarAccess == .notDetermined || calendarAccess == .writeOnly
        else { return }
        isRequestingCalendarAccess = true
        Task { [weak self] in
            guard let self else { return }
            defer { isRequestingCalendarAccess = false }
            do {
                _ = try await eventStore.requestFullAccessToEvents()
            } catch {
                AppLog.error(
                    "DashboardWidgets",
                    "Calendar access request failed: \(error.localizedDescription)")
            }
            refreshCalendarAuthorization()
        }
    }

    func refreshCalendarAuthorization() {
        let current = Self.currentCalendarAccess()
        guard current != calendarAccess else { return }
        calendarAccess = current
        refreshCalendar()
    }

    private func refreshCalendar(now: Date = Date(), calendar: Calendar = .current) {
        calendarAccess = Self.currentCalendarAccess()
        guard calendarAccess.canRead else {
            calendarAccounts = []
            nextEvent = nil
            return
        }
        let calendars = eventStore.calendars(for: .event)
        calendarAccounts = Self.calendarAccounts(from: calendars)
        guard
            let horizon = calendar.date(byAdding: .year, value: 1, to: now)
        else {
            nextEvent = nil
            return
        }
        let effectiveSourceIdentifier = DashboardWidgetsEngine.effectiveCalendarSourceIdentifier(
            selected: preferences.calendarSourceIdentifier,
            availableIdentifiers: Set(calendarAccounts.map(\DashboardCalendarAccount.id)))
        let selectedCalendars = effectiveSourceIdentifier.map { identifier in
            calendars.filter { $0.source?.sourceIdentifier == identifier }
        }
        let predicateCalendars = selectedCalendars?.isEmpty == false ? selectedCalendars : nil
        let predicate = eventStore.predicateForEvents(
            withStart: now, end: horizon, calendars: predicateCalendars)
        let events = eventStore.events(matching: predicate)
            .filter {
                $0.status != .canceled && $0.endDate > now
                    && DashboardWidgetsEngine.shouldIncludeCalendarEvent(
                        isAllDay: $0.isAllDay,
                        sourceIdentifier: $0.calendar.source?.sourceIdentifier ?? "",
                        selectedSourceIdentifier: effectiveSourceIdentifier,
                        includesAllDayEvents: preferences.includesAllDayEvents)
            }
        guard let event = events
            .filter({ $0.startDate < horizon })
            .min(by: { $0.startDate < $1.startDate })
        else {
            nextEvent = nil
            return
        }
        nextEvent = DashboardEvent(
            id: event.eventIdentifier ?? UUID().uuidString,
            title: event.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? "Untitled event",
            startDate: event.startDate, endDate: event.endDate, isAllDay: event.isAllDay,
            calendarTitle: event.calendar.title,
            location: event.location?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty)
    }

    private static func currentCalendarAccess() -> DashboardCalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .restricted: return .restricted
        case .writeOnly: return .writeOnly
        case .fullAccess, .authorized: return .fullAccess
        @unknown default: return .restricted
        }
    }

    private static func calendarAccounts(from calendars: [EKCalendar]) -> [DashboardCalendarAccount] {
        var accounts: [String: DashboardCalendarAccount] = [:]
        for calendar in calendars {
            guard let source = calendar.source else { continue }
            guard !source.sourceIdentifier.isEmpty else { continue }
            accounts[source.sourceIdentifier] = DashboardCalendarAccount(
                id: source.sourceIdentifier, title: source.title)
        }
        return accounts.values.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private func updatePreferences(_ updated: DashboardWidgetPreferences) {
        guard updated != preferences else { return }
        preferences = updated
        defaults.set(
            updated.widgetOrder.map(\DashboardWidgetKind.rawValue), forKey: Keys.widgetOrder)
        defaults.set(updated.calendarSourceIdentifier ?? "", forKey: Keys.calendarSource)
        defaults.set(updated.includesAllDayEvents, forKey: Keys.includesAllDayEvents)
        defaults.set(updated.clockTimeZoneIdentifier ?? "", forKey: Keys.clockTimeZone)
        Task { [weak self] in self?.refresh() }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
