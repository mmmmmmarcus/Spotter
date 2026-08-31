import Foundation

struct WorldClockCity: Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let timeZoneIdentifier: String

    init(name: String, timeZoneIdentifier: String) {
        id = timeZoneIdentifier + "#" + name
        self.name = name
        self.timeZoneIdentifier = timeZoneIdentifier
    }
}

struct WorldClockResult: Equatable, Sendable {
    let city: String
    let timeZoneIdentifier: String
    let time: String
    let date: String
    let localTimeZoneIdentifier: String
    let localTime: String
    let localDate: String
}

/// Foundation-only local-time lookup. The clock, calendar and local time zone are injected.
enum WorldClockEngine {
    private struct Location: Sendable {
        let city: WorldClockCity
        let aliases: [String]

        init(name: String, timeZoneIdentifier: String, aliases: [String]) {
            city = WorldClockCity(name: name, timeZoneIdentifier: timeZoneIdentifier)
            self.aliases = aliases
        }
    }

    private static let commonLocations: [Location] = [
        Location(
            name: "San Francisco", timeZoneIdentifier: "America/Los_Angeles",
            aliases: ["sf", "san francisco", "bay area"]),
        Location(
            name: "Los Angeles", timeZoneIdentifier: "America/Los_Angeles",
            aliases: ["la", "los angeles"]),
        Location(
            name: "New York", timeZoneIdentifier: "America/New_York",
            aliases: ["nyc", "new york"]),
        Location(name: "London", timeZoneIdentifier: "Europe/London", aliases: ["london"]),
        Location(name: "Paris", timeZoneIdentifier: "Europe/Paris", aliases: ["paris"]),
        Location(name: "Berlin", timeZoneIdentifier: "Europe/Berlin", aliases: ["berlin"]),
        Location(name: "Tokyo", timeZoneIdentifier: "Asia/Tokyo", aliases: ["tokyo"]),
        Location(
            name: "Shanghai", timeZoneIdentifier: "Asia/Shanghai",
            aliases: ["shanghai", "上海"]),
        Location(
            name: "Beijing", timeZoneIdentifier: "Asia/Shanghai",
            aliases: ["beijing", "北京"]),
        Location(
            name: "Hong Kong", timeZoneIdentifier: "Asia/Hong_Kong",
            aliases: ["hk", "hong kong", "香港"]),
        Location(
            name: "Singapore", timeZoneIdentifier: "Asia/Singapore",
            aliases: ["sg", "singapore"]),
        Location(name: "Sydney", timeZoneIdentifier: "Australia/Sydney", aliases: ["sydney"]),
        Location(
            name: "Melbourne", timeZoneIdentifier: "Australia/Melbourne",
            aliases: ["melbourne"]),
        Location(name: "Dubai", timeZoneIdentifier: "Asia/Dubai", aliases: ["dubai"]),
        Location(name: "Mumbai", timeZoneIdentifier: "Asia/Kolkata", aliases: ["mumbai", "bombay"]),
        Location(
            name: "Delhi", timeZoneIdentifier: "Asia/Kolkata",
            aliases: ["delhi", "new delhi"]),
        Location(name: "Toronto", timeZoneIdentifier: "America/Toronto", aliases: ["toronto"]),
        Location(
            name: "Vancouver", timeZoneIdentifier: "America/Vancouver",
            aliases: ["vancouver"]),
        Location(name: "Chicago", timeZoneIdentifier: "America/Chicago", aliases: ["chicago"]),
        Location(
            name: "Honolulu", timeZoneIdentifier: "Pacific/Honolulu", aliases: ["honolulu"]),
    ]

    private static let generatedLocations: [Location] = {
        let claimedAliases = Set(commonLocations.flatMap(\.aliases).map(normalized))
        return TimeZone.knownTimeZoneIdentifiers.compactMap { identifier in
            let parts = identifier.split(separator: "/")
            guard parts.count >= 2, parts[0] != "Etc", parts[0] != "SystemV",
                let rawCity = parts.last
            else { return nil }
            let alias = normalized(String(rawCity).replacingOccurrences(of: "_", with: " "))
            guard !alias.isEmpty, !claimedAliases.contains(alias) else { return nil }
            let name = alias.split(separator: " ").map { $0.capitalized }.joined(separator: " ")
            return Location(name: name, timeZoneIdentifier: identifier, aliases: [alias])
        }
        .sorted { $0.city.name.localizedStandardCompare($1.city.name) == .orderedAscending }
    }()

    private static let allLocations = commonLocations + generatedLocations

    private static let locationsByAlias: [String: Location] = {
        var result: [String: Location] = [:]
        for location in allLocations {
            for alias in location.aliases where result[normalized(alias)] == nil {
                result[normalized(alias)] = location
            }
        }
        return result
    }()

    private static let locationsByID = Dictionary(
        uniqueKeysWithValues: allLocations.map { ($0.city.id, $0) })

    static let availableCities = allLocations.map(\.city)

    static let defaultCities = ["London", "Shanghai", "San Francisco"].compactMap { name in
        availableCities.first { $0.name == name }
    }

    static func city(id: String) -> WorldClockCity? { locationsByID[id]?.city }

    static func searchCities(_ raw: String, excluding excluded: Set<String> = [])
        -> [WorldClockCity]
    {
        let query = normalized(raw)
        let candidates = allLocations.filter { !excluded.contains($0.city.id) }
        guard !query.isEmpty else { return candidates.map(\.city) }
        return candidates.filter { location in
            normalized(location.city.name).contains(query)
                || normalized(location.city.timeZoneIdentifier).contains(query)
                || location.aliases.contains { normalized($0).contains(query) }
        }
        .sorted { left, right in
            let leftPrefix = normalized(left.city.name).hasPrefix(query)
                || left.aliases.contains { normalized($0).hasPrefix(query) }
            let rightPrefix = normalized(right.city.name).hasPrefix(query)
                || right.aliases.contains { normalized($0).hasPrefix(query) }
            if leftPrefix != rightPrefix { return leftPrefix }
            return left.city.name.localizedStandardCompare(right.city.name) == .orderedAscending
        }
        .map(\.city)
    }

    static func evaluate(
        _ raw: String, now: Date = Date(), calendar: Calendar = .current,
        locale: Locale = .current, localTimeZone: TimeZone
    ) -> WorldClockResult? {
        let query = normalized(raw)
        guard query.count <= 256, requestsTime(query), let location = matchLocation(in: query)
        else { return nil }
        return result(
            for: location.city, now: now, calendar: calendar, locale: locale,
            localTimeZone: localTimeZone)
    }

    static func result(
        for city: WorldClockCity, now: Date, calendar: Calendar = .current,
        locale: Locale = .current, localTimeZone: TimeZone
    ) -> WorldClockResult? {
        guard let timeZone = TimeZone(identifier: city.timeZoneIdentifier) else { return nil }
        let remote = formatted(now, timeZone: timeZone, calendar: calendar, locale: locale)
        let local = formatted(now, timeZone: localTimeZone, calendar: calendar, locale: locale)
        return WorldClockResult(
            city: city.name,
            timeZoneIdentifier: city.timeZoneIdentifier,
            time: remote.time,
            date: remote.date,
            localTimeZoneIdentifier: localTimeZone.identifier,
            localTime: local.time,
            localDate: local.date)
    }

    private static func formatted(
        _ date: Date, timeZone: TimeZone, calendar: Calendar, locale: Locale
    ) -> (time: String, date: String) {
        var zonedCalendar = calendar
        zonedCalendar.timeZone = timeZone
        var timeStyle = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale)
        timeStyle.calendar = zonedCalendar
        timeStyle.timeZone = timeZone
        var dateStyle = Date.FormatStyle(date: .complete, time: .omitted, locale: locale)
        dateStyle.calendar = zonedCalendar
        dateStyle.timeZone = timeZone
        return (date.formatted(timeStyle), date.formatted(dateStyle))
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

    /// tz-database `zone.tab` text → ISO country code per canonical zone identifier. Pure parse for
    /// the harness; the store feeds it the system's own copy of the table.
    static func countryCodes(fromZoneTab text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard !line.hasPrefix("#") else { continue }
            let columns = line.split(separator: "\t")
            guard columns.count >= 3, columns[0].count == 2 else { continue }
            result[String(columns[2])] = String(columns[0])
        }
        return result
    }

    /// The two regional-indicator scalars that render as a country's flag emoji.
    static func flagEmoji(countryCode: String) -> String? {
        let code = countryCode.uppercased()
        guard code.count == 2, code.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        var flag = ""
        for scalar in code.unicodeScalars {
            guard let regional = Unicode.Scalar(0x1F1E6 + scalar.value - Unicode.Scalar("A").value)
            else { return nil }
            flag.unicodeScalars.append(regional)
        }
        return flag
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
        guard let result = WorldClockEngine.evaluate(
            query, now: now, calendar: calendar, localTimeZone: .autoupdatingCurrent)
        else { return nil }
        return PluginQueryResult(
            pluginID: .worldClock,
            sectionTitle: "World Clock",
            expression: result.city,
            sourceBadge: result.timeZoneIdentifier,
            targetBadge: result.date,
            display: result.time,
            copyText: result.time,
            actionTitle: "Copy Time",
            companion: PluginQueryCompanion(
                display: result.localTime, badge: "Local · " + result.localDate),
            supportsHourlyAdjustment: true)
    }
}
