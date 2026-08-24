import Foundation

@main
@MainActor
struct UptimeTests {
    private static var failures = 0

    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let dayStart = date("2026-08-14 09:15", calendar)
        let dayEnd = date("2026-08-14 18:45", calendar)
        let nextMorning = date("2026-08-15 07:30", calendar)

        check(
            UptimeEngine.carriedOverSessionStart(dayStart, now: dayEnd, calendar: calendar)
                == dayStart,
            "a start stamped earlier the same day should carry over")
        check(
            UptimeEngine.carriedOverSessionStart(
                dayEnd, now: nextMorning, calendar: calendar) == nil,
            "yesterday's start should not survive midnight")
        check(
            UptimeEngine.carriedOverSessionStart(nil, now: dayEnd, calendar: calendar)
                == nil,
            "a day with no activity yet should have no start")
        check(
            UptimeEngine.carriedOverSessionStart(
                dayEnd, now: dayStart, calendar: calendar) == nil,
            "a start in the future should be dropped rather than report a negative session")

        let tallies = UptimeInputCounts(keys: 4182, clicks: 861)
        check(
            UptimeEngine.carriedOverCounts(
                tallies, countedDay: dayStart, now: dayEnd, calendar: calendar) == tallies,
            "counts should survive a relaunch on the same day")
        check(
            UptimeEngine.carriedOverCounts(
                tallies, countedDay: dayEnd, now: nextMorning, calendar: calendar) == .zero,
            "counts should zero on a new day")
        check(
            UptimeEngine.carriedOverCounts(
                tallies, countedDay: nil, now: dayEnd, calendar: calendar) == .zero,
            "counts with no recorded day should not be trusted")

        check(
            UptimeEngine.formattedElapsed(from: dayStart, to: dayEnd) == "9h 30m",
            "elapsed time should read as whole hours and minutes")
        check(
            UptimeEngine.formattedElapsed(
                from: dayStart, to: dayStart.addingTimeInterval(2_099)) == "34m",
            "under an hour should drop the hour component and floor the minute")
        check(
            UptimeEngine.formattedElapsed(from: dayEnd, to: dayStart) == "0m",
            "a backwards interval should floor at zero rather than go negative")

        check(
            UptimeEngine.formattedCount(0) == "0"
                && UptimeEngine.formattedCount(861) == "861"
                && UptimeEngine.formattedCount(4182) == "4,182"
                && UptimeEngine.formattedCount(1_234_567) == "1,234,567",
            "counts should group in threes independently of the Mac's locale")

        check(
            UptimeEngine.keysLabel(480) == "480 keys pressed"
                && UptimeEngine.clicksLabel(128) == "128 mouse clicks",
            "tallies should spell out what they counted")
        check(
            UptimeEngine.keysLabel(1) == "1 key pressed"
                && UptimeEngine.clicksLabel(1) == "1 mouse click",
            "the day's first key or click should read in the singular")
        check(
            UptimeEngine.keysLabel(0) == "0 keys pressed"
                && UptimeEngine.clicksLabel(12_345) == "12,345 mouse clicks",
            "zero should stay plural and a large tally should stay grouped")

        print(failures == 0 ? "All uptime tests passed." : "\(failures) uptime tests FAILED.")
        exit(failures == 0 ? 0 : 1)
    }

    private static func check(_ condition: Bool, _ label: String) {
        if condition {
            print("✓ \(label)")
        } else {
            failures += 1
            print("✗ \(label)")
        }
    }

    private static func date(_ value: String, _ calendar: Calendar) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: value)!
    }
}
