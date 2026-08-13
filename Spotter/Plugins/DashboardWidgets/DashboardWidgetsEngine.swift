import Foundation

enum DashboardWidgetKind: String, CaseIterable, Equatable, Hashable, Sendable {
    case clock
    case nextEvent = "next-event"
}

struct DashboardWidgetPreferences: Equatable, Sendable {
    var enabledWidgets: Set<DashboardWidgetKind>
    var calendarSourceIdentifier: String?
    var includesAllDayEvents: Bool
    var clockTimeZoneIdentifier: String?

    static let defaults = DashboardWidgetPreferences(
        enabledWidgets: Set(DashboardWidgetKind.allCases),
        calendarSourceIdentifier: nil,
        includesAllDayEvents: true,
        clockTimeZoneIdentifier: nil)
}

struct DashboardCalendarAccount: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
}

struct DashboardEvent: Equatable, Sendable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarTitle: String
    let location: String?
}

enum DashboardWidgetsEngine {
    static func widgetKinds(from rawValues: [String]?) -> Set<DashboardWidgetKind> {
        guard let rawValues else { return DashboardWidgetPreferences.defaults.enabledWidgets }
        return Set(rawValues.compactMap(DashboardWidgetKind.init(rawValue:)))
    }

    static func resolvedTimeZone(identifier: String?, fallback: TimeZone) -> TimeZone {
        guard let identifier, let timeZone = TimeZone(identifier: identifier) else {
            return fallback
        }
        return timeZone
    }

    static func effectiveCalendarSourceIdentifier(
        selected: String?, availableIdentifiers: Set<String>
    ) -> String? {
        guard let selected, availableIdentifiers.contains(selected) else { return nil }
        return selected
    }

    static func shouldIncludeCalendarEvent(
        isAllDay: Bool, sourceIdentifier: String, selectedSourceIdentifier: String?,
        includesAllDayEvents: Bool
    ) -> Bool {
        if isAllDay && !includesAllDayEvents { return false }
        guard let selectedSourceIdentifier else { return true }
        return sourceIdentifier == selectedSourceIdentifier
    }
}
