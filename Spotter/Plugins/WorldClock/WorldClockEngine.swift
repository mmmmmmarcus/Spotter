import Foundation

struct WorldClockResult: Equatable, Sendable {
    let city: String
    let timeZoneIdentifier: String
    let time: String
    let date: String
}

/// Foundation-only local-time lookup. The clock and calendar are injected so tests never read time.
enum WorldClockEngine {
    private struct Location: Sendable {
        let city: String
        let timeZoneIdentifier: String
        let aliases: [String]
    }

    private static let commonLocations: [Location] = [
        Location(
            city: "San Francisco", timeZoneIdentifier: "America/Los_Angeles",
            aliases: ["sf", "san francisco", "bay area"]),
        Location(
            city: "Los Angeles", timeZoneIdentifier: "America/Los_Angeles",
            aliases: ["la", "los angeles"]),
        Location(
            city: "New York", timeZoneIdentifier: "America/New_York",
            aliases: ["nyc", "new york"]),
        Location(city: "London", timeZoneIdentifier: "Europe/London", aliases: ["london"]),
        Location(city: "Paris", timeZoneIdentifier: "Europe/Paris", aliases: ["paris"]),
        Location(city: "Berlin", timeZoneIdentifier: "Europe/Berlin", aliases: ["berlin"]),
        Location(city: "Tokyo", timeZoneIdentifier: "Asia/Tokyo", aliases: ["tokyo"]),
        Location(
            city: "Shanghai", timeZoneIdentifier: "Asia/Shanghai",
            aliases: ["shanghai", "上海"]),
        Location(
            city: "Beijing", timeZoneIdentifier: "Asia/Shanghai",
            aliases: ["beijing", "北京"]),
        Location(
            city: "Hong Kong", timeZoneIdentifier: "Asia/Hong_Kong",
            aliases: ["hk", "hong kong", "香港"]),
        Location(
            city: "Singapore", timeZoneIdentifier: "Asia/Singapore",
            aliases: ["sg", "singapore"]),
        Location(city: "Sydney", timeZoneIdentifier: "Australia/Sydney", aliases: ["sydney"]),
        Location(city: "Melbourne", timeZoneIdentifier: "Australia/Melbourne", aliases: ["melbourne"]),
        Location(city: "Dubai", timeZoneIdentifier: "Asia/Dubai", aliases: ["dubai"]),
        Location(city: "Mumbai", timeZoneIdentifier: "Asia/Kolkata", aliases: ["mumbai", "bombay"]),
        Location(city: "Delhi", timeZoneIdentifier: "Asia/Kolkata", aliases: ["delhi", "new delhi"]),
        Location(city: "Toronto", timeZoneIdentifier: "America/Toronto", aliases: ["toronto"]),
        Location(city: "Vancouver", timeZoneIdentifier: "America/Vancouver", aliases: ["vancouver"]),
        Location(city: "Chicago", timeZoneIdentifier: "America/Chicago", aliases: ["chicago"]),
        Location(city: "Honolulu", timeZoneIdentifier: "Pacific/Honolulu", aliases: ["honolulu"]),
    ]

    /// Common aliases win; the generated tail makes every city-shaped IANA identifier available.
    private static let locationsByAlias: [String: Location] = {
        var result: [String: Location] = [:]
        for location in commonLocations {
            for alias in location.aliases { result[normalized(alias)] = location }
        }
        for identifier in TimeZone.knownTimeZoneIdentifiers {
            let parts = identifier.split(separator: "/")
            guard parts.count >= 2, parts[0] != "Etc", parts[0] != "SystemV",
                let rawCity = parts.last
            else { continue }
            let alias = normalized(String(rawCity).replacingOccurrences(of: "_", with: " "))
            guard !alias.isEmpty, result[alias] == nil else { continue }
            let city = alias.split(separator: " ").map { $0.capitalized }.joined(separator: " ")
            result[alias] = Location(city: city, timeZoneIdentifier: identifier, aliases: [alias])
        }
        return result
    }()

    static func evaluate(
        _ raw: String, now: Date = Date(), calendar: Calendar = .current,
        locale: Locale = .current
    ) -> WorldClockResult? {
        let query = normalized(raw)
        guard query.count <= 256, requestsTime(query), let location = matchLocation(in: query),
            let timeZone = TimeZone(identifier: location.timeZoneIdentifier)
        else { return nil }

        var zonedCalendar = calendar
        zonedCalendar.timeZone = timeZone
        var timeStyle = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale)
        timeStyle.calendar = zonedCalendar
        timeStyle.timeZone = timeZone
        var dateStyle = Date.FormatStyle(date: .complete, time: .omitted, locale: locale)
        dateStyle.calendar = zonedCalendar
        dateStyle.timeZone = timeZone
        let time = now.formatted(timeStyle)
        let date = now.formatted(dateStyle)
        return WorldClockResult(
            city: location.city,
            timeZoneIdentifier: location.timeZoneIdentifier,
            time: time,
            date: date)
    }

    private static func requestsTime(_ query: String) -> Bool {
        query == "time" || query.contains(" time") || query.hasPrefix("time ")
            || query.contains("时间")
    }

    private static func matchLocation(in query: String) -> Location? {
        let withoutCJKTime = query.replacingOccurrences(of: "时间", with: " ")
        let ignored: Set<Substring> = [
            "current", "in", "is", "it", "now", "please", "the", "time", "what", "what's",
        ]
        let location = withoutCJKTime.split(separator: " ").filter { !ignored.contains($0) }
            .joined(separator: " ")
        return locationsByAlias[location]
    }

    private static func normalized(_ raw: String) -> String {
        let characters = raw.folding(
            options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "’", with: "'")
            .map { $0.isLetter || $0.isNumber || $0 == "'" ? $0 : " " }
        return String(characters).split(whereSeparator: { $0.isWhitespace })
            .map { String($0) }.joined(separator: " ")
    }
}

struct WorldClockQueryProvider: PluginQueryProvider {
    func evaluate(_ query: String, now: Date, calendar: Calendar) -> PluginQueryResult? {
        guard let result = WorldClockEngine.evaluate(query, now: now, calendar: calendar) else {
            return nil
        }
        return PluginQueryResult(
            pluginID: .worldClock,
            sectionTitle: "World Clock",
            expression: result.city,
            sourceBadge: result.timeZoneIdentifier,
            targetBadge: result.date,
            display: result.time,
            copyText: result.time,
            actionTitle: "Copy Time")
    }
}
