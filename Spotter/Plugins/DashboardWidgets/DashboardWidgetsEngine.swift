import Foundation

/// `allCases` order is the first-run strip order, and the fallback position of any widget a saved
/// arrangement predates.
enum DashboardWidgetKind: String, CaseIterable, Equatable, Hashable, Sendable {
    case clock
    case uptime
    case deviceBattery = "device-battery"
    case nextEvent = "next-event"
    case fileInfo = "file-info"

    var title: String {
        switch self {
        case .clock: return "Clock"
        case .uptime: return "Uptime"
        case .deviceBattery: return "Device Battery"
        case .nextEvent: return "Calendar"
        case .fileInfo: return "File Info"
        }
    }

    var systemImage: String {
        switch self {
        case .clock: return "clock"
        case .uptime: return "timer"
        case .deviceBattery: return "battery.100percent"
        case .nextEvent: return "calendar"
        case .fileInfo: return "info.circle"
        }
    }

    /// What the arrangement pane says a widget shows, so the list explains itself without a preview.
    var summary: String {
        switch self {
        case .clock: return "An analog face, with the date and the day's weather in its corners."
        case .uptime: return "How long today's session has run, with key and click counts."
        case .deviceBattery:
            return "Levels for connected mice, keyboards and trackpads. Hidden while nothing "
                + "connected reports one."
        case .nextEvent: return "The next event on the calendar account you choose."
        case .fileInfo:
            return "The kind and size of whatever is selected in the Finder, read when the Finder "
                + "is the app you came from."
        }
    }

    /// False for a widget whose switch is a consent act owned by its own store — the arrangement
    /// pane must route those through the store (and its dialog), never through `enabledWidgets`.
    var ownsEnabledState: Bool { self != .uptime }
}

struct DashboardWidgetPreferences: Equatable, Sendable {
    var enabledWidgets: Set<DashboardWidgetKind>
    /// Every kind exactly once, in strip order. Kept complete so a widget turned off keeps its place.
    var widgetOrder: [DashboardWidgetKind]
    var calendarSourceIdentifier: String?
    var includesAllDayEvents: Bool
    var clockTimeZoneIdentifier: String?

    static let defaults = DashboardWidgetPreferences(
        enabledWidgets: Set(DashboardWidgetKind.allCases.filter(\.ownsEnabledState)),
        widgetOrder: DashboardWidgetKind.allCases,
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

    /// A saved arrangement, repaired: unknown raw values and duplicates drop out, and any kind the
    /// saved order predates lands at the end. The result always holds every kind exactly once, so
    /// the strip and the arrangement list can index it without a second existence check.
    static func widgetOrder(from rawValues: [String]?) -> [DashboardWidgetKind] {
        guard let rawValues else { return DashboardWidgetKind.allCases }
        var ordered: [DashboardWidgetKind] = []
        var seen: Set<DashboardWidgetKind> = []
        for kind in rawValues.compactMap(DashboardWidgetKind.init(rawValue:)) where seen.insert(kind).inserted {
            ordered.append(kind)
        }
        ordered.append(contentsOf: DashboardWidgetKind.allCases.filter { !seen.contains($0) })
        return ordered
    }

    /// Moves one widget to sit at `destination` in the *current* list, the way a dragged row reads —
    /// not SwiftUI's `move(fromOffsets:toOffset:)` index, which shifts by one for a downward move.
    static func reorder(
        _ order: [DashboardWidgetKind], moving kind: DashboardWidgetKind, to destination: Int
    ) -> [DashboardWidgetKind] {
        guard let source = order.firstIndex(of: kind), destination >= 0, destination < order.count,
            source != destination
        else { return order }
        var order = order
        order.remove(at: source)
        order.insert(kind, at: destination)
        return order
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
