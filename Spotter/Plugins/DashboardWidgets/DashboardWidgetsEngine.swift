import Foundation

enum DashboardWidgetKind: String, CaseIterable, Equatable, Hashable, Sendable {
    case clock
    case deviceBattery = "device-battery"
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

/// Analog clock hand rotations in degrees clockwise from 12 o'clock.
struct ClockHandAngles: Equatable, Sendable {
    var hour: Double
    var minute: Double
    var second: Double
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

    /// Hands sweep continuously — the hour hand advances with the minutes, the minute hand with the seconds — so the face never shows the top-of-hour snap of a components-only clock.
    /// The second itself carries its fraction, so a caller redrawing faster than 1 Hz gets a gliding second hand rather than a tick.
    static func clockHandAngles(
        for date: Date, timeZone: TimeZone,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> ClockHandAngles {
        var calendar = calendar
        calendar.timeZone = timeZone
        let components = calendar.dateComponents(
            [.hour, .minute, .second, .nanosecond], from: date)
        let hour = Double(components.hour ?? 0)
        let minute = Double(components.minute ?? 0)
        let second =
            Double(components.second ?? 0) + Double(components.nanosecond ?? 0) / 1_000_000_000
        return ClockHandAngles(
            hour: (hour.truncatingRemainder(dividingBy: 12) + minute / 60 + second / 3600) * 30,
            minute: (minute + second / 60) * 6,
            second: second * 6)
    }
}
