import Foundation

/// A video-call link found on an event, with the provider named for the row's action.
struct MeetingLink: Equatable, Sendable {
    let provider: String
    let urlString: String
}

/// Foundation-only and pure: meeting-link detection and the schedule rows' date/time language.
/// The clock, calendar and locale are injected; `Tools/calendar-schedule-test.swift` compiles this.
enum CalendarScheduleEngine {
    /// Known conference hosts, matched against every URL an event carries.
    private static let providers: [(host: String, name: String)] = [
        ("zoom.us", "Zoom"),
        ("meet.google.com", "Google Meet"),
        ("teams.microsoft.com", "Microsoft Teams"),
        ("teams.live.com", "Microsoft Teams"),
        ("webex.com", "Webex"),
        ("whereby.com", "Whereby"),
        ("meet.jit.si", "Jitsi"),
        ("facetime.apple.com", "FaceTime"),
    ]

    private static let urlPattern = try! NSRegularExpression(
        pattern: #"https?://[^\s<>"'\)]+"#)

    /// The event's first conference link: its own URL field wins, then the location, then the notes.
    static func meetingLink(
        urlString: String?, location: String?, notes: String?
    ) -> MeetingLink? {
        for field in [urlString, location, notes] {
            guard let field, !field.isEmpty else { continue }
            for candidate in urls(in: field) {
                if let link = classify(candidate) { return link }
            }
        }
        return nil
    }

    static func matches(query: String, title: String, calendarTitle: String, location: String?) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || [title, calendarTitle, location ?? ""].contains { $0.localizedCaseInsensitiveContains(query) }
    }

    static func googleCalendarDestination(
        urlString: String?, notes: String?, start: Date, timeZoneIdentifier: String?, calendar: Calendar
    ) -> ScheduleCalendarDestination {
        for field in [urlString, notes] {
            guard let field else { continue }
            for candidate in urls(in: field) {
                let address = candidate.replacingOccurrences(of: "&amp;", with: "&")
                guard let url = URL(string: address), url.scheme == "https",
                      let host = url.host?.lowercased(), ["calendar.google.com", "www.google.com"].contains(host),
                      url.user == nil, url.password == nil,
                      url.path.hasPrefix("/calendar/") else { continue }
                let parts = url.path.split(separator: "/")
                let hasEventID = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                    .contains { $0.name == "eid" && $0.value?.isEmpty == false } == true
                let hasEventPath = parts.firstIndex(of: "eventedit").map { $0 + 1 < parts.count } ?? false
                if hasEventID || hasEventPath {
                    return ScheduleCalendarDestination(url: url, opensEvent: true)
                }
            }
        }
        // EventKit identifiers are not Google event IDs; never manufacture an event link from one.
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? calendar.timeZone
        let date = gregorian.dateComponents([.year, .month, .day], from: start)
        var components = URLComponents(string: "https://calendar.google.com/calendar/r/day/\(date.year!)/\(date.month!)/\(date.day!)")!
        components.queryItems = [URLQueryItem(name: "ctz", value: gregorian.timeZone.identifier)]
        return ScheduleCalendarDestination(url: components.url!, opensEvent: false)
    }

    private static func urls(in text: String) -> [String] {
        let range = NSRange(location: 0, length: (text as NSString).length)
        return urlPattern.matches(in: text, range: range).map {
            (text as NSString).substring(with: $0.range)
        }
    }

    private static func classify(_ urlString: String) -> MeetingLink? {
        guard let host = URL(string: urlString)?.host?.lowercased() else { return nil }
        for provider in providers
        where host == provider.host || host.hasSuffix("." + provider.host) {
            return MeetingLink(provider: provider.name, urlString: urlString)
        }
        return nil
    }

    /// "Today", "Tomorrow", or the weekday with its date — the row's place in the week at a glance.
    static func dayLabel(
        for date: Date, now: Date, calendar: Calendar, locale: Locale = .current
    ) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
            calendar.isDate(date, inSameDayAs: tomorrow)
        {
            return "Tomorrow"
        }
        var style = Date.FormatStyle(locale: locale)
            .weekday(.abbreviated).month(.abbreviated).day()
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }

    /// "2:00 – 2:30 PM" for a timed event, "All day" otherwise.
    static func timeLabel(
        start: Date, end: Date, isAllDay: Bool, calendar: Calendar, locale: Locale = .current
    ) -> String {
        guard !isAllDay else { return "All day" }
        var style = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale)
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return start.formatted(style) + " – " + end.formatted(style)
    }
}

struct ScheduleTimeZone: Equatable, Sendable {
    let name: String
    let identifier: String
}

struct ScheduleEventTime: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let dayOffset: Int
    let date: String
    let time: String
    let isPrimary: Bool
}

extension CalendarScheduleEngine {
    static func detailTimes(
        start: Date, end: Date, isAllDay: Bool, eventTimeZoneIdentifier: String?,
        cities: [ScheduleTimeZone], calendar: Calendar, locale: Locale = .current
    ) -> [ScheduleEventTime] {
        let eventZone = eventTimeZoneIdentifier.flatMap(TimeZone.init(identifier:))
        let primary = isAllDay ? calendar.timeZone : eventZone ?? calendar.timeZone
        let primaryName = eventZone == nil ? "Local Time"
            : primary.identifier.split(separator: "/").last.map { String($0).replacingOccurrences(of: "_", with: " ") } ?? "Event Time"
        var zones: [(String, TimeZone)] = [(primaryName, primary)]
        var seen = Set([offsetKey(primary, start: start, end: end)])
        if !isAllDay {
            for city in cities {
                guard zones.count < 4 else { break }
                guard let zone = TimeZone(identifier: city.identifier),
                      seen.insert(offsetKey(zone, start: start, end: end)).inserted else { continue }
                zones.append((city.name, zone))
            }
        }
        return zones.enumerated().map { index, entry in
            let (name, zone) = entry
            var zoned = calendar
            zoned.timeZone = zone
            var dateStyle = Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale)
            dateStyle.calendar = zoned
            dateStyle.timeZone = zone
            // All-day end dates are exclusive and must not display an extra calendar day.
            let displayedEnd = isAllDay && end > start ? end.addingTimeInterval(-1) : end
            let date = zoned.isDate(start, inSameDayAs: displayedEnd)
                ? start.formatted(dateStyle)
                : start.formatted(dateStyle) + " – " + displayedEnd.formatted(dateStyle)
            var reference = calendar
            reference.timeZone = primary
            var neutral = calendar
            neutral.timeZone = TimeZone(secondsFromGMT: 0)!
            let sourceDay = neutral.date(from: reference.dateComponents([.era, .year, .month, .day], from: start))!
            let targetDay = neutral.date(from: zoned.dateComponents([.era, .year, .month, .day], from: start))!
            let dayOffset = neutral.dateComponents([.day], from: sourceDay, to: targetDay).day ?? 0
            return ScheduleEventTime(id: zone.identifier, name: name,
                dayOffset: dayOffset, date: date,
                time: timeLabel(start: start, end: end, isAllDay: isAllDay, calendar: zoned, locale: locale),
                isPrimary: index == 0)
        }
    }

    private static func offsetKey(_ zone: TimeZone, start: Date, end: Date) -> String {
        // Equal offsets at both endpoints produce duplicate displayed times, including IANA aliases.
        "\(zone.secondsFromGMT(for: start))/\(zone.secondsFromGMT(for: end))"
    }

}

struct ScheduleCalendarDestination: Equatable, Sendable {
    let url: URL
    let opensEvent: Bool
    var title: String { opensEvent ? "Open in Google Calendar" : "Open Date in Google Calendar" }
}
