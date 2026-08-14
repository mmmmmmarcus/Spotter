import Foundation

@main
@MainActor
struct DashboardWidgetsTests {
    private static var failures = 0

    static func main() {
        check(
            DashboardWidgetsEngine.widgetKinds(from: nil)
                == Set(DashboardWidgetKind.allCases),
            "missing widget preferences should preserve the two-widget default")
        check(
            DashboardWidgetsEngine.widgetKinds(from: []) == [],
            "an explicitly empty widget selection should remain empty")
        check(
            DashboardWidgetsEngine.widgetKinds(
                from: ["clock", "codex", "claude-code", "future-widget"])
                == [.clock],
            "removed and unknown widget identifiers should be ignored")

        let fallbackTimeZone = TimeZone(identifier: "Asia/Shanghai")!
        check(
            DashboardWidgetsEngine.resolvedTimeZone(identifier: "America/New_York", fallback: fallbackTimeZone)
                .identifier == "America/New_York",
            "a selected clock time zone should resolve")
        check(
            DashboardWidgetsEngine.resolvedTimeZone(identifier: "Missing/Zone", fallback: fallbackTimeZone)
                == fallbackTimeZone,
            "an unavailable clock time zone should fall back safely")
        check(
            DashboardWidgetsEngine.effectiveCalendarSourceIdentifier(
                selected: "icloud", availableIdentifiers: ["icloud", "exchange"]) == "icloud",
            "an available calendar account should remain selected")
        check(
            DashboardWidgetsEngine.effectiveCalendarSourceIdentifier(
                selected: "removed", availableIdentifiers: ["icloud", "exchange"]) == nil,
            "an unavailable calendar account should fall back to all accounts")

        check(
            DashboardWidgetsEngine.shouldIncludeCalendarEvent(
                isAllDay: false, sourceIdentifier: "icloud", selectedSourceIdentifier: nil,
                includesAllDayEvents: true),
            "all accounts should accept a timed event")
        check(
            !DashboardWidgetsEngine.shouldIncludeCalendarEvent(
                isAllDay: true, sourceIdentifier: "icloud", selectedSourceIdentifier: nil,
                includesAllDayEvents: false),
            "the all-day preference should exclude all-day events")
        check(
            !DashboardWidgetsEngine.shouldIncludeCalendarEvent(
                isAllDay: false, sourceIdentifier: "exchange",
                selectedSourceIdentifier: "icloud", includesAllDayEvents: true),
            "a selected calendar account should exclude other accounts")
        check(
            DashboardWidgetsEngine.shouldIncludeCalendarEvent(
                isAllDay: false, sourceIdentifier: "icloud",
                selectedSourceIdentifier: "icloud", includesAllDayEvents: true),
            "a selected calendar account should include its own events")

        let utc = TimeZone(identifier: "UTC")!
        // 1970-01-01 12:00:00 UTC — every hand straight up.
        let noon = DashboardWidgetsEngine.clockHandAngles(
            for: Date(timeIntervalSince1970: 43200), timeZone: utc)
        check(noon == ClockHandAngles(hour: 0, minute: 0, second: 0),
            "noon should point every hand at 12")

        // 21:45:15 UTC — the hour hand rides the minutes, the minute hand the seconds.
        let evening = DashboardWidgetsEngine.clockHandAngles(
            for: Date(timeIntervalSince1970: 21 * 3600 + 45 * 60 + 15), timeZone: utc)
        check(near(evening.hour, 292.625), "21:45:15 hour hand should sit at 292.625°")
        check(near(evening.minute, 271.5), "21:45:15 minute hand should sit at 271.5°")
        check(near(evening.second, 90), "21:45:15 second hand should sit at 90°")

        // The same instant three hours west lands the hour hand a quarter turn back.
        let shifted = DashboardWidgetsEngine.clockHandAngles(
            for: Date(timeIntervalSince1970: 21 * 3600 + 45 * 60 + 15),
            timeZone: TimeZone(secondsFromGMT: -3 * 3600)!)
        check(near(shifted.hour, 202.625), "the clock should follow the selected time zone")
        check(near(shifted.minute, evening.minute) && near(shifted.second, evening.second),
            "a whole-hour zone offset should move only the hour hand")

        print(failures == 0 ? "Dashboard widgets tests passed" : "\(failures) test(s) failed")
        exit(failures == 0 ? 0 : 1)
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    private static func near(_ value: Double, _ expected: Double) -> Bool {
        abs(value - expected) < 0.0001
    }
}
