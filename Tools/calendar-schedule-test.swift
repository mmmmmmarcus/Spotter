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
        var layoutCalendar = Calendar(identifier: .gregorian)
        layoutCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        layoutCalendar.firstWeekday = 2
        func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
            layoutCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
        }
        let leap = ScheduleLayout.days(containing: date(2024, 2, 15), mode: .month, calendar: layoutCalendar)
        check("month grid has six complete weeks", leap.count == 42)
        check("month starts on the configured weekday", layoutCalendar.component(.weekday, from: leap[0]) == 2)
        check("leap day is present", leap.contains(date(2024, 2, 29)))
        check("month grid includes boundary days", leap.first! < date(2024, 2, 1) && leap.last! >= date(2024, 3, 1))
        check("January 31 advances to February instead of skipping a month",
              ScheduleLayout.moved(date(2024, 1, 31), mode: .month, by: 1, calendar: layoutCalendar) == date(2024, 2, 1))
        let dst = ScheduleLayout.days(containing: date(2024, 3, 10), mode: .week, calendar: layoutCalendar)
        check("DST week still contains seven local dates", dst.count == 7)
        check("days start at local midnight across DST", dst.allSatisfy { layoutCalendar.component(.hour, from: $0) == 0 })
        let springDay = date(2024, 3, 10)
        let springWeek = date(2024, 3, 4)
        let springEnd = ScheduleLayout.moved(springDay, mode: .week, by: 1, calendar: layoutCalendar)
        check("week navigation uses calendar arithmetic across DST",
              springEnd == date(2024, 3, 11) && springEnd.timeIntervalSince(springWeek) == 167 * 3600)
        let midnight = date(2026, 9, 18)
        let current = date(2026, 9, 18, 12, 30)
        let currentWeek = ScheduleLayout.days(containing: current, mode: .week, calendar: layoutCalendar)
        func initialMinute(_ entries: [(start: Date, end: Date, isAllDay: Bool)],
                           days: [Date]? = nil, now: Date? = nil) -> Double {
            ScheduleLayout.initialScrollMinute(days: days ?? currentWeek, events: entries,
                now: now ?? current, calendar: layoutCalendar)
        }
        let active = (start: date(2026, 9, 18, 12), end: date(2026, 9, 18, 13), isAllDay: false)
        check("an empty week centers 10 AM", initialMinute([]) == 600)
        check("an ongoing timed event centers the current time", initialMinute([active]) == 750)
        check("an event counts from its exact start", initialMinute([active], now: active.start) == 720)
        check("an event no longer counts at its exact end", initialMinute([active], now: active.end) == 600)
        check("future events leave the viewport at 10 AM",
              initialMinute([active], now: date(2026, 9, 18, 11)) == 600)
        check("all-day events do not pull the time grid away from 10 AM",
              initialMinute([(midnight, date(2026, 9, 19), true)]) == 600)
        check("other weeks center 10 AM even with stale active events",
              initialMinute([active], days: [date(2026, 9, 25)]) == 600)
        check("an overnight event centers the current time after midnight",
              initialMinute([(date(2026, 9, 17, 23), date(2026, 9, 18, 2), false)],
                            now: date(2026, 9, 18, 1)) == 60)
        check("initial positioning follows local wall time across DST",
              initialMinute([(springDay, date(2024, 3, 11), false)], days: dst,
                            now: date(2024, 3, 10, 9)) == 540)
        check("past dates fade for the full time grid",
              ScheduleLayout.elapsedMinutes(on: date(2026, 9, 17), now: current, calendar: layoutCalendar) == 1440)
        check("today fades only through the current local minute",
              ScheduleLayout.elapsedMinutes(on: midnight, now: current, calendar: layoutCalendar) == 750)
        check("future dates remain fully visible",
              ScheduleLayout.elapsedMinutes(on: date(2026, 9, 19), now: current, calendar: layoutCalendar) == 0)
        check("midnight starts with no elapsed region",
              ScheduleLayout.elapsedMinutes(on: midnight, now: midnight, calendar: layoutCalendar) == 0)
        check("DST elapsed region follows wall-clock grid coordinates",
              ScheduleLayout.elapsedMinutes(on: springDay, now: date(2024, 3, 10, 9), calendar: layoutCalendar) == 540)
        check("a completed short DST day still fades all 24 visual hours",
              ScheduleLayout.elapsedMinutes(on: springDay, now: date(2024, 3, 11), calendar: layoutCalendar) == 1440)
        check("event ending at midnight does not occupy the following day",
              !ScheduleLayout.overlaps(start: date(2026, 9, 17, 23), end: midnight, day: midnight, calendar: layoutCalendar))
        let overnight = ScheduleLayout.block(id: "night", start: date(2026, 9, 17, 23),
            end: date(2026, 9, 18, 1), day: midnight, calendar: layoutCalendar)!
        check("overnight event is clipped to each day", overnight.startMinute == 0 && overnight.endMinute == 60)
        let late = ScheduleLayout.block(id: "late", start: date(2026, 9, 17, 23, 55),
            end: midnight, day: date(2026, 9, 17), calendar: layoutCalendar)!
        check("a late event keeps its true start", late.startMinute == 1435)
        let blocks = ScheduleLayout.columns([
            ScheduleTimeBlock(id: "a", startMinute: 540, endMinute: 600),
            ScheduleTimeBlock(id: "b", startMinute: 570, endMinute: 630),
            ScheduleTimeBlock(id: "c", startMinute: 600, endMinute: 660),
            ScheduleTimeBlock(id: "d", startMinute: 660, endMinute: 720)])
        check("overlapping events occupy separate columns", blocks[0].column != blocks[1].column)
        check("a completed column is reused", blocks[0].column == blocks[2].column)
        check("overlap groups share their maximum column count", blocks.prefix(3).allSatisfy { $0.columnCount == 2 })
        check("a subsequent nonoverlapping event gets full width", blocks[3].columnCount == 1)
        let morning = ScheduleLayout.block(id: "spring", start: date(2024, 3, 10, 9),
            end: date(2024, 3, 10, 10), day: springDay, calendar: layoutCalendar)!
        check("timed events align with local wall-clock hours after DST", morning.startMinute == 540)

        func position(_ id: String, _ day: Int, _ hour: Int, allDay: Bool = false) -> ScheduleEventPosition {
            ScheduleEventPosition(eventID: id, day: date(2026, 9, day),
                                  startMinute: Double(hour * 60), isAllDay: allDay)
        }
        let mondayAllDay = position("all", 14, 0, allDay: true)
        let mondayEarly = position("early", 14, 9)
        let mondayLate = position("late", 14, 15)
        let tuesdayEarly = position("tue-early", 15, 10)
        let tuesdayLate = position("tue-late", 15, 16)
        let thursday = position("thu", 17, 14)
        let navigation = [thursday, tuesdayLate, mondayLate, mondayAllDay, tuesdayEarly, mondayEarly]
        func neighbor(_ item: ScheduleEventPosition, _ direction: ScheduleDirection) -> String? {
            ScheduleNavigation.neighbor(in: navigation, selectedID: item.id, direction: direction)
        }
        check("Down moves to the next event in the same day", neighbor(mondayEarly, .down) == mondayLate.id)
        check("Up moves to the previous event in the same day", neighbor(mondayLate, .up) == mondayEarly.id)
        check("Up reaches the all-day lane before timed events", neighbor(mondayEarly, .up) == mondayAllDay.id)
        check("Down leaves the all-day lane for timed events", neighbor(mondayAllDay, .down) == mondayEarly.id)
        check("Down at the last event never crosses into another day", neighbor(mondayLate, .down) == mondayLate.id)
        check("Up at the first event stays in place", neighbor(mondayAllDay, .up) == mondayAllDay.id)
        check("Right chooses a nearby time on the next populated day", neighbor(mondayLate, .right) == tuesdayLate.id)
        check("Left chooses a nearby time on the previous populated day", neighbor(tuesdayEarly, .left) == mondayEarly.id)
        check("horizontal navigation skips days without matching events", neighbor(tuesdayLate, .right) == thursday.id)
        check("horizontal navigation never pages at the visible boundary", neighbor(thursday, .right) == thursday.id)
        check("empty query results have no navigation destination",
              ScheduleNavigation.neighbor(in: [], selectedID: nil, direction: .down) == nil)
        check("a removed selection starts at the first visible event",
              ScheduleNavigation.neighbor(in: navigation, selectedID: "missing", direction: .right) == mondayAllDay.id)
        check("filtered navigation cannot target a hidden event",
              ScheduleNavigation.neighbor(in: [mondayLate, thursday], selectedID: mondayLate.id, direction: .right) == thursday.id)
        let allDayTuesday = position("all-tue", 15, 0, allDay: true)
        check("horizontal navigation prefers the same all-day lane",
              ScheduleNavigation.neighbor(in: [mondayAllDay, tuesdayEarly, allDayTuesday],
                  selectedID: mondayAllDay.id, direction: .right) == allDayTuesday.id)
        let spanningMonday = position("spanning", 14, 0, allDay: true)
        let spanningTuesday = position("spanning", 15, 0, allDay: true)
        check("multi-day event placements have distinct selection identities", spanningMonday.id != spanningTuesday.id)
        check("a multi-day event can be selected in the next day's column",
              ScheduleNavigation.neighbor(in: [spanningMonday, spanningTuesday],
                  selectedID: spanningMonday.id, direction: .right) == spanningTuesday.id)
        check("month Down moves one grid row", ScheduleNavigation.monthNeighbor(from: 10, direction: .down, count: 42) == 17)
        check("month Up moves one grid row", ScheduleNavigation.monthNeighbor(from: 10, direction: .up, count: 42) == 3)
        check("month Right moves one date", ScheduleNavigation.monthNeighbor(from: 10, direction: .right, count: 42) == 11)
        check("month Left moves one date", ScheduleNavigation.monthNeighbor(from: 10, direction: .left, count: 42) == 9)
        check("month top edge does not change weekday", ScheduleNavigation.monthNeighbor(from: 3, direction: .up, count: 42) == 3)
        check("month last cell does not page", ScheduleNavigation.monthNeighbor(from: 41, direction: .right, count: 42) == 41)
        check("empty month grid does not create a selection", ScheduleNavigation.monthNeighbor(from: 0, direction: .down, count: 0) == nil)

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
