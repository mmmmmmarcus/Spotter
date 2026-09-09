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

/// A parsed `8pm in london` query: a wall-clock time plus the words that should name a city.
struct WorldClockConversionQuery: Equatable, Sendable {
    let hour: Int
    let minute: Int
    /// The city words as typed (folded to lowercase); empty when the query stopped after the time.
    let cityPhrase: String
}

/// One converted instant, rendered in one zone. Same fields the saved-city rows show.
struct WorldClockConversionRow: Equatable, Sendable {
    let id: String
    let name: String
    let timeZoneIdentifier: String
    let time: String
    let date: String
    /// The row standing in for the Mac's own zone when no configured city already covers it.
    let isLocal: Bool
}

struct WorldClockConversion: Equatable, Sendable {
    let instant: Date
    let sourceCity: String
    let sourceTimeZoneIdentifier: String
    /// Formatted from `instant`, not from the digits typed — a time inside a spring-forward gap
    /// resolves to the instant that exists, and the headline must say which one that is.
    let sourceTime: String
    let sourceDate: String
    let rows: [WorldClockConversionRow]
    /// Section header: `8:00 PM in London · Sep 9, 2026`.
    let headline: String
}

/// What the World Clock screen's one query field is being asked for.
enum WorldClockScreenIntent: Equatable, Sendable {
    /// No leading clock time: the field keeps searching the city catalog.
    case citySearch
    case conversion(WorldClockConversion)
    /// A leading clock time whose city words name nothing in the catalog (empty when none typed).
    case unresolvedCity(phrase: String)
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

    // MARK: - Time conversion

    static let conversionRowPrefix = "convert:"
    static let localConversionRowID = "convert:#local"

    /// Parse-first rule for the screen's single field: a query that *starts* with a clock time is a
    /// conversion, anything else stays a city search. A bare number is never a time — `10 downing`
    /// must keep searching — so the hour needs `am`/`pm` or a `:` to count.
    static func parseConversion(_ raw: String) -> WorldClockConversionQuery? {
        guard raw.count <= 256 else { return nil }
        let tokens = conversionTokens(raw)
        guard let first = tokens.first else { return nil }

        var hour: Int
        var minute = 0
        var consumed = 1
        switch first {
        case "noon": hour = 12
        case "midnight": hour = 0
        default:
            var digits = first
            var meridiem: String?
            if digits.hasSuffix("am") || digits.hasSuffix("pm") {
                meridiem = String(digits.suffix(2))
                digits = String(digits.dropLast(2))
            }
            guard let clock = parseWallClock(digits) else { return nil }
            hour = clock.hour
            minute = clock.minute
            if meridiem == nil, tokens.count > 1, tokens[1] == "am" || tokens[1] == "pm" {
                meridiem = tokens[1]
                consumed = 2
            }
            if let meridiem {
                guard (1...12).contains(hour) else { return nil }
                hour = meridiem == "pm" ? (hour % 12) + 12 : hour % 12
            } else {
                // No meridiem: only a `:` form reads as 24-hour; `8` alone stays ambiguous.
                guard clock.hadSeparator, (0...23).contains(hour) else { return nil }
            }
            guard (0...59).contains(minute) else { return nil }
        }

        var rest = tokens.dropFirst(consumed)
        if let connector = rest.first, connector == "in" || connector == "at" {
            rest = rest.dropFirst()
        }
        return WorldClockConversionQuery(
            hour: hour, minute: minute, cityPhrase: rest.joined(separator: " "))
    }

    /// The screen's whole read of its query: search, a resolved conversion, or a city it can't place.
    static func screenIntent(
        for raw: String, cities: [WorldClockCity], now: Date, calendar: Calendar = .current,
        locale: Locale = .current, localTimeZone: TimeZone
    ) -> WorldClockScreenIntent {
        guard let parsed = parseConversion(raw) else { return .citySearch }
        guard let location = locationsByAlias[normalized(parsed.cityPhrase)],
            let sourceZone = TimeZone(identifier: location.city.timeZoneIdentifier),
            let instant = instant(
                hour: parsed.hour, minute: parsed.minute, in: sourceZone, on: now,
                calendar: calendar)
        else { return .unresolvedCity(phrase: parsed.cityPhrase) }

        let source = formatted(
            instant, timeZone: sourceZone, calendar: calendar, locale: locale)
        var rows: [WorldClockConversionRow] = []
        for city in cities {
            guard let zone = TimeZone(identifier: city.timeZoneIdentifier) else { continue }
            let stamp = formatted(instant, timeZone: zone, calendar: calendar, locale: locale)
            rows.append(
                WorldClockConversionRow(
                    id: conversionRowPrefix + city.id, name: city.name,
                    timeZoneIdentifier: city.timeZoneIdentifier, time: stamp.time,
                    date: stamp.date, isLocal: false))
        }
        // The answer is useless without the zone the user is sitting in, so it is always present.
        if !cities.contains(where: { $0.timeZoneIdentifier == localTimeZone.identifier }) {
            let stamp = formatted(
                instant, timeZone: localTimeZone, calendar: calendar, locale: locale)
            rows.append(
                WorldClockConversionRow(
                    id: localConversionRowID, name: "Local Time",
                    timeZoneIdentifier: localTimeZone.identifier, time: stamp.time,
                    date: stamp.date, isLocal: true))
        }
        return .conversion(
            WorldClockConversion(
                instant: instant,
                sourceCity: location.city.name,
                sourceTimeZoneIdentifier: location.city.timeZoneIdentifier,
                sourceTime: source.time,
                sourceDate: source.date,
                rows: rows,
                headline: source.time + " in " + location.city.name + " · "
                    + shortDate(instant, timeZone: sourceZone, calendar: calendar, locale: locale)))
    }

    /// The instant of that wall-clock time on the zone's *own* current day — today there, never a
    /// silent roll to tomorrow. `date(from:)` consults the zone's real rules for that date, so the
    /// same digits in January and July are different instants wherever DST applies.
    static func instant(
        hour: Int, minute: Int, in zone: TimeZone, on now: Date, calendar: Calendar
    ) -> Date? {
        var zoned = calendar
        zoned.timeZone = zone
        var components = zoned.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return zoned.date(from: components)
    }

    /// `8:30`/`20:00`/`8`; `hadSeparator` is what lets the caller reject a bare hour.
    private static func parseWallClock(_ atom: String) -> (
        hour: Int, minute: Int, hadSeparator: Bool
    )? {
        guard !atom.isEmpty, atom.allSatisfy({ $0.isNumber || $0 == ":" }) else { return nil }
        let parts = atom.split(separator: ":", omittingEmptySubsequences: false)
        switch parts.count {
        case 1:
            guard parts[0].count <= 2, let hour = Int(parts[0]) else { return nil }
            return (hour, 0, false)
        case 2:
            guard parts[0].count <= 2, parts[1].count == 2, let hour = Int(parts[0]),
                let minute = Int(parts[1])
            else { return nil }
            return (hour, minute, true)
        default:
            return nil
        }
    }

    /// Case-folded tokens that keep `:` inside the clock atom, which `normalized` would split.
    private static func conversionTokens(_ raw: String) -> [String] {
        let folded = raw.folding(
            options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let cleaned = folded.map { $0.isLetter || $0.isNumber || $0 == ":" ? $0 : " " }
        return String(cleaned).split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    private static func shortDate(
        _ date: Date, timeZone: TimeZone, calendar: Calendar, locale: Locale
    ) -> String {
        var zonedCalendar = calendar
        zonedCalendar.timeZone = timeZone
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale)
        style.calendar = zonedCalendar
        style.timeZone = timeZone
        return date.formatted(style)
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
