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

        var utcCalendar = Calendar(identifier: .gregorian)
        let utc = TimeZone(secondsFromGMT: 0)!
        utcCalendar.timeZone = utc
        let clockDate = utcCalendar.date(from: DateComponents(
            year: 2026, month: 8, day: 13, hour: 3, minute: 15, second: 30))!
        let clockAngles = DashboardWidgetsEngine.clockAngles(
            at: clockDate, calendar: utcCalendar, timeZone: utc)
        check(
            approximatelyEqual(clockAngles.hour, 97.75)
                && approximatelyEqual(clockAngles.minute, 93)
                && approximatelyEqual(clockAngles.second, 180),
            "analog clock hands should include minute and second progress")
        let shanghaiAngles = DashboardWidgetsEngine.clockAngles(
            at: clockDate, calendar: utcCalendar, timeZone: fallbackTimeZone)
        check(
            approximatelyEqual(shanghaiAngles.hour, 337.75),
            "analog clock hands should honor the selected time zone")

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

        print(failures == 0 ? "Dashboard widgets tests passed" : "\(failures) test(s) failed")
        exit(failures == 0 ? 0 : 1)
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    private static func approximatelyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) < 0.000_001
    }
}
