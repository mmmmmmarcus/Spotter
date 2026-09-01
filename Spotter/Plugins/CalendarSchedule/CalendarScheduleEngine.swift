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
