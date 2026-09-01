// Compile with `Spotter/Plugins/CalendarSchedule/CalendarScheduleEngine.swift`; see docs/development.md.
import Foundation

@main
@MainActor
enum CalendarScheduleTests {
    static var failures = 0

    static func check(_ message: String, _ condition: @autoclosure () -> Bool) {
        if condition() {
            print("PASS  \(message)")
        } else {
            failures += 1
            print("FAIL  \(message)")
        }
    }

    static func main() {
        let zoom = CalendarScheduleEngine.meetingLink(
            urlString: "https://us02web.zoom.us/j/123?pwd=abc", location: nil, notes: nil)
        check("a Zoom URL field is a Zoom meeting", zoom?.provider == "Zoom")
        check(
            "the link keeps its exact URL",
            zoom?.urlString == "https://us02web.zoom.us/j/123?pwd=abc")

        let meet = CalendarScheduleEngine.meetingLink(
            urlString: nil, location: "https://meet.google.com/abc-defg-hij", notes: nil)
        check("a Meet link in the location is found", meet?.provider == "Google Meet")

        let teams = CalendarScheduleEngine.meetingLink(
            urlString: nil, location: "Conference Room 4",
            notes: "Join here: <https://teams.microsoft.com/l/meetup-join/xyz> — agenda attached")
        check("a Teams link buried in the notes is found", teams?.provider == "Microsoft Teams")
        check(
            "angle brackets do not ride into the URL",
            teams?.urlString == "https://teams.microsoft.com/l/meetup-join/xyz")

        check(
            "the URL field wins over the notes",
            CalendarScheduleEngine.meetingLink(
                urlString: "https://zoom.us/j/1", location: nil,
                notes: "https://meet.google.com/x")?.provider == "Zoom")
        check(
            "an ordinary website is not a meeting",
            CalendarScheduleEngine.meetingLink(
                urlString: "https://example.com/agenda", location: "HQ", notes: "Bring slides")
                == nil)
        check(
            "a lookalike host is not a meeting",
            CalendarScheduleEngine.meetingLink(
                urlString: "https://notzoom.usurper.com/j/1", location: nil, notes: nil) == nil)
        check(
            "a subdomain of a provider matches",
            CalendarScheduleEngine.meetingLink(
                urlString: "https://company.webex.com/meet/marcus", location: nil, notes: nil)?
                .provider == "Webex")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let locale = Locale(identifier: "en_US")
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 9))!
        let today = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 15))!
        let tomorrow = calendar.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: 8))!
        let friday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: 8))!
        check(
            "the same day is Today",
            CalendarScheduleEngine.dayLabel(
                for: today, now: now, calendar: calendar, locale: locale) == "Today")
        check(
            "the next day is Tomorrow",
            CalendarScheduleEngine.dayLabel(
                for: tomorrow, now: now, calendar: calendar, locale: locale) == "Tomorrow")
        check(
            "a later day names its weekday and date",
            CalendarScheduleEngine.dayLabel(
                for: friday, now: now, calendar: calendar, locale: locale)
                .contains("Fri"))

        let end = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 15, minute: 30))!
        let timed = CalendarScheduleEngine.timeLabel(
            start: today, end: end, isAllDay: false, calendar: calendar, locale: locale)
        check("a timed event spans start to end", timed.contains("3:00") && timed.contains("3:30"))
        check(
            "an all-day event says so",
            CalendarScheduleEngine.timeLabel(
                start: today, end: end, isAllDay: true, calendar: calendar, locale: locale)
                == "All day")

        if failures > 0 {
            print("\n\(failures) failure(s)")
            exit(1)
        }
        print("\nAll calendar-schedule checks passed")
    }
}
