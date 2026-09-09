import Foundation

@main
@MainActor
struct WorldClockTests {
    static var passed = 0
    static var failed = 0

    static func main() {
        let locale = Locale(identifier: "en_US_POSIX")
        let calendar = Calendar(identifier: .gregorian)
        let instant = Date(timeIntervalSince1970: 1_775_304_000)
        let localTimeZone = TimeZone(secondsFromGMT: 0)!

        let sf = WorldClockEngine.evaluate(
            "SF time now", now: instant, calendar: calendar, locale: locale,
            localTimeZone: localTimeZone)
        expect(sf?.city == "San Francisco", "SF alias resolves to San Francisco")
        expect(sf?.timeZoneIdentifier == "America/Los_Angeles", "SF uses Pacific time")
        expect(compact(sf?.time) == "5:00AM", "SF observes daylight saving time")
        expect(compact(sf?.localTime) == "12:00PM", "query includes injected local system time")

        let tokyo = WorldClockEngine.evaluate(
            "what time is it in Tokyo?", now: instant, calendar: calendar, locale: locale,
            localTimeZone: localTimeZone)
        expect(tokyo?.city == "Tokyo", "natural-language prefix resolves")
        expect(compact(tokyo?.time) == "9:00PM", "Tokyo formats the injected instant")

        let tokyoPlusOne = WorldClockEngine.evaluate(
            "time in Tokyo", now: instant.addingTimeInterval(3_600), calendar: calendar,
            locale: locale, localTimeZone: localTimeZone)
        expect(compact(tokyoPlusOne?.time) == "10:00PM", "one-hour adjustment advances target time")
        expect(compact(tokyoPlusOne?.localTime) == "1:00PM", "one-hour adjustment advances local time")

        let shanghai = WorldClockEngine.evaluate(
            "上海时间", now: instant, calendar: calendar, locale: locale,
            localTimeZone: localTimeZone)
        expect(shanghai?.city == "Shanghai", "Chinese time suffix resolves")
        expect(compact(shanghai?.time) == "8:00PM", "Shanghai formats the injected instant")

        let saoPaulo = WorldClockEngine.evaluate(
            "São Paulo time", now: instant, calendar: calendar, locale: locale,
            localTimeZone: localTimeZone)
        expect(
            saoPaulo?.timeZoneIdentifier == "America/Sao_Paulo",
            "IANA city index is diacritic-insensitive")

        expect(
            WorldClockEngine.evaluate(
                "San Francisco", now: instant, localTimeZone: localTimeZone) == nil,
            "city-only app searches are not claimed")
        expect(
            WorldClockEngine.evaluate(
                "staff time", now: instant, localTimeZone: localTimeZone) == nil,
            "short aliases match whole location phrases")
        expect(
            WorldClockEngine.evaluate("time", now: instant, localTimeZone: localTimeZone) == nil,
            "a location is required")

        expect(
            WorldClockEngine.defaultCities.map(\.name)
                == ["London", "Shanghai", "San Francisco"],
            "launcher defaults use the requested city order")
        expect(
            WorldClockEngine.searchCities("sing").first?.name == "Singapore",
            "city catalog search prioritizes name prefixes")
        expect(
            WorldClockEngine.searchCities("SF").first?.name == "San Francisco",
            "city catalog search includes common aliases")

        let suiteName = "WorldClockTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WorldClockStore(defaults: defaults, now: { instant })
        expect(store.cities.map(\.name) == ["London", "Shanghai", "San Francisco"], "store seeds defaults")
        let tokyoCity = WorldClockEngine.searchCities("Tokyo").first!
        store.add(tokyoCity)
        store.remove(id: WorldClockEngine.defaultCities[0].id)
        let restored = WorldClockStore(defaults: defaults, now: { instant })
        expect(restored.cities.map(\.name) == ["Shanghai", "San Francisco", "Tokyo"], "city edits persist in order")

        let zoneTab = """
            # comment line
            JP\t+353916+1394441\tAsia/Tokyo
            GB\t+513030-0000731\tEurope/London\tsome comment
            bad line without tabs
            """
        let countries = WorldClockEngine.countryCodes(fromZoneTab: zoneTab)
        expect(countries["Asia/Tokyo"] == "JP", "zone.tab rows map zone to country")
        expect(countries["Europe/London"] == "GB", "a trailing comment column is ignored")
        expect(countries.count == 2, "comments and malformed rows are dropped")
        expect(WorldClockEngine.flagEmoji(countryCode: "JP") == "🇯🇵", "a country code becomes its flag")
        expect(WorldClockEngine.flagEmoji(countryCode: "gb") == "🇬🇧", "lowercase codes are accepted")
        expect(WorldClockEngine.flagEmoji(countryCode: "J") == nil, "a one-letter code is rejected")
        expect(WorldClockEngine.flagEmoji(countryCode: "J2") == nil, "a non-letter code is rejected")

        conversionParsing()
        conversionResolution()
        conversionDST()

        print("World Clock: \(passed) passed, \(failed) failed")
        if failed > 0 { exit(1) }
    }

    // MARK: - Time conversion

    private static let gregorian: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    private static let posix = Locale(identifier: "en_US_POSIX")

    /// A wall-clock instant in a named zone, so the tests can pin a "now" without magic epochs.
    private static func moment(
        _ zoneID: String, _ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0
    ) -> Date {
        var calendar = gregorian
        calendar.timeZone = TimeZone(identifier: zoneID)!
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components)!
    }

    private static func conversion(
        _ query: String, now: Date, cities: [WorldClockCity] = WorldClockEngine.defaultCities,
        local: TimeZone = TimeZone(secondsFromGMT: 0)!
    ) -> WorldClockConversion? {
        guard case .conversion(let conversion) = WorldClockEngine.screenIntent(
            for: query, cities: cities, now: now, calendar: gregorian, locale: posix,
            localTimeZone: local)
        else { return nil }
        return conversion
    }

    private static func time(_ conversion: WorldClockConversion?, _ city: String) -> String? {
        compact(conversion?.rows.first { $0.name == city }?.time)
    }

    private static func conversionParsing() {
        func parsed(_ query: String) -> WorldClockConversionQuery? {
            WorldClockEngine.parseConversion(query)
        }
        expect(
            parsed("8pm in london") == .init(hour: 20, minute: 0, cityPhrase: "london"),
            "`8pm in london` parses to 20:00 plus a city phrase")
        expect(
            parsed("8 pm london") == .init(hour: 20, minute: 0, cityPhrase: "london"),
            "a detached meridiem and no connector parse the same")
        expect(
            parsed("8PM  London") == .init(hour: 20, minute: 0, cityPhrase: "london"),
            "case and extra spacing are folded")
        expect(
            parsed("20:00 in tokyo") == .init(hour: 20, minute: 0, cityPhrase: "tokyo"),
            "a 24-hour clock parses without a meridiem")
        expect(
            parsed("8:30pm in new york") == .init(hour: 20, minute: 30, cityPhrase: "new york"),
            "minutes and a multi-word city survive")
        expect(
            parsed("8:30 pm new york") == .init(hour: 20, minute: 30, cityPhrase: "new york"),
            "minutes with a detached meridiem parse")
        expect(
            parsed("9am at sydney") == .init(hour: 9, minute: 0, cityPhrase: "sydney"),
            "`at` is accepted as a connector")
        expect(
            parsed("12am in tokyo") == .init(hour: 0, minute: 0, cityPhrase: "tokyo"),
            "12am is midnight")
        expect(
            parsed("12pm in tokyo") == .init(hour: 12, minute: 0, cityPhrase: "tokyo"),
            "12pm is noon")
        expect(
            parsed("noon in tokyo") == .init(hour: 12, minute: 0, cityPhrase: "tokyo"),
            "`noon` is a clock time")
        expect(
            parsed("midnight in tokyo") == .init(hour: 0, minute: 0, cityPhrase: "tokyo"),
            "`midnight` is a clock time")
        expect(
            parsed("0:15 in london") == .init(hour: 0, minute: 15, cityPhrase: "london"),
            "an early 24-hour time parses")
        expect(
            parsed("8pm") == .init(hour: 20, minute: 0, cityPhrase: ""),
            "a time with no city still parses, with an empty phrase")

        expect(parsed("london") == nil, "a bare city name stays a city search")
        expect(parsed("") == nil, "an empty query is not a conversion")
        expect(parsed("8") == nil, "a bare hour is too ambiguous to be a time")
        expect(parsed("8 london") == nil, "a bare hour before a city is still not a time")
        expect(parsed("10 downing") == nil, "a leading number never swallows a search")
        expect(parsed("2000 in tokyo") == nil, "four bare digits are not a 24-hour clock")
        expect(parsed("25:00 in tokyo") == nil, "an out-of-range hour is rejected")
        expect(parsed("13pm in tokyo") == nil, "a meridiem hour above 12 is rejected")
        expect(parsed("8:99pm in tokyo") == nil, "an out-of-range minute is rejected")
        expect(parsed("8:5 in london") == nil, "a one-digit minute is rejected")
        expect(parsed("time in london") == nil, "the inline-query phrasing is not a conversion")
        expect(parsed("sao paulo") == nil, "a two-word city name stays a city search")
    }

    private static func conversionResolution() {
        // 15 January 2026, 20:00 in London — a date with no DST anywhere in the default list.
        let now = moment("Europe/London", 2026, 1, 15, 9)
        let converted = conversion("8pm in london", now: now)
        expect(converted?.sourceCity == "London", "the source city resolves through the catalog")
        expect(compact(converted?.sourceTime) == "8:00PM", "the source keeps the typed time")
        expect(
            converted?.sourceDate == "Thursday, January 15, 2026",
            "the source row names the date it is showing")
        expect(
            spaced(converted?.headline) == "8:00 PM in London · Jan 15, 2026",
            "the section header states the time, the city and the date")
        expect(time(converted, "London") == "8:00PM", "a configured source city shows the typed time")
        expect(time(converted, "Shanghai") == "4:00AM", "Shanghai is next morning")
        expect(time(converted, "San Francisco") == "12:00PM", "San Francisco is the same midday")
        expect(
            converted?.rows.first { $0.name == "Shanghai" }?.date
                == "Friday, January 16, 2026",
            "a row that crosses midnight states its own later date")
        expect(
            converted?.rows.map(\.name) == ["London", "Shanghai", "San Francisco", "Local Time"],
            "rows follow the saved order, then the Mac's own zone")
        expect(converted?.rows.last?.isLocal == true, "the appended row is flagged as local")
        expect(
            converted?.rows.last?.id == WorldClockEngine.localConversionRowID,
            "the local row carries the shared identifier")
        expect(
            converted?.rows.first?.id
                == WorldClockEngine.conversionRowPrefix + WorldClockEngine.defaultCities[0].id,
            "a city row's identifier is its catalog id behind the conversion prefix")

        let localCovered = conversion(
            "8pm in london", now: now, local: TimeZone(identifier: "Europe/London")!)
        expect(
            localCovered?.rows.map(\.name) == ["London", "Shanghai", "San Francisco"],
            "no local row is appended when a configured city already covers that zone")

        let noCities = conversion("8pm in london", now: now, cities: [])
        expect(
            noCities?.rows.map(\.name) == ["Local Time"],
            "with no configured cities the answer is still the local one")

        expect(
            WorldClockEngine.screenIntent(
                for: "8pm in atlantis", cities: [], now: now, calendar: gregorian, locale: posix,
                localTimeZone: TimeZone(secondsFromGMT: 0)!)
                == .unresolvedCity(phrase: "atlantis"),
            "an unknown city is reported, never guessed")
        expect(
            WorldClockEngine.screenIntent(
                for: "8pm", cities: [], now: now, calendar: gregorian, locale: posix,
                localTimeZone: TimeZone(secondsFromGMT: 0)!)
                == .unresolvedCity(phrase: ""),
            "a time with no city asks for one")
        expect(
            WorldClockEngine.screenIntent(
                for: "8pm in london tomorrow", cities: [], now: now, calendar: gregorian,
                locale: posix, localTimeZone: TimeZone(secondsFromGMT: 0)!)
                == .unresolvedCity(phrase: "london tomorrow"),
            "trailing words are not silently ignored")
        expect(
            WorldClockEngine.screenIntent(
                for: "london", cities: [], now: now, calendar: gregorian, locale: posix,
                localTimeZone: TimeZone(secondsFromGMT: 0)!) == .citySearch,
            "a city name leaves the field searching")

        // Chosen moment: today in the source city, even once that instant has passed.
        let lateInLondon = moment("Europe/London", 2026, 1, 15, 23, 30)
        let past = conversion("8pm in london", now: lateInLondon)
        expect(
            past?.sourceDate == "Thursday, January 15, 2026",
            "a time that has already passed stays today, never tomorrow")
        expect(
            past.map { $0.instant < lateInLondon } == true,
            "the chosen instant is genuinely in the past")

        // "Today" is the source city's own day, not the Mac's.
        let londonEvening = moment("Europe/London", 2026, 1, 15, 23, 0)
        let tokyo = conversion("8pm in tokyo", now: londonEvening, cities: [])
        expect(
            tokyo?.sourceDate == "Friday, January 16, 2026",
            "the date comes from the source city's calendar, not the local one")
        expect(time(tokyo, "Local Time") == "11:00AM", "the same instant reads back in GMT")
    }

    private static func conversionDST() {
        let london = WorldClockEngine.searchCities("London").first!
        let sydney = WorldClockEngine.searchCities("Sydney").first!
        let saoPaulo = WorldClockEngine.searchCities("Sao Paulo").first!
        let newYork = WorldClockEngine.searchCities("New York").first!

        // Same digits, two sides of a transition: 8pm London is 20:00 UTC in January, 19:00 in July.
        let winter = conversion(
            "8pm in london", now: moment("Europe/London", 2026, 1, 15, 12), cities: [london])
        let summer = conversion(
            "8pm in london", now: moment("Europe/London", 2026, 7, 15, 12), cities: [london])
        expect(time(winter, "Local Time") == "8:00PM", "London in January is GMT")
        expect(time(summer, "Local Time") == "7:00PM", "London in July is BST — one hour off UTC")
        expect(
            winter?.instant != summer?.instant,
            "the same wall-clock time is a different instant across a transition")

        // Southern hemisphere: Sydney's DST calendar is inverted, so January is the +11 side.
        let sydneySummer = conversion(
            "8pm in sydney", now: moment("Australia/Sydney", 2026, 1, 15, 12), cities: [sydney])
        let sydneyWinter = conversion(
            "8pm in sydney", now: moment("Australia/Sydney", 2026, 7, 15, 12), cities: [sydney])
        expect(time(sydneySummer, "Local Time") == "9:00AM", "Sydney in January is AEDT (+11)")
        expect(time(sydneyWinter, "Local Time") == "10:00AM", "Sydney in July is AEST (+10)")

        // A zone whose rules changed: Brazil observed DST in January 2018 and abolished it by 2020.
        let brazil2018 = conversion(
            "8pm in sao paulo", now: moment("America/Sao_Paulo", 2018, 1, 15, 12),
            cities: [saoPaulo])
        let brazil2020 = conversion(
            "8pm in sao paulo", now: moment("America/Sao_Paulo", 2020, 1, 15, 12),
            cities: [saoPaulo])
        expect(time(brazil2018, "Local Time") == "10:00PM", "São Paulo was UTC−2 in January 2018")
        expect(
            time(brazil2020, "Local Time") == "11:00PM",
            "São Paulo is UTC−3 in January 2020 — historic rules, not a fixed offset")

        // A wall-clock time inside a spring-forward gap resolves to the instant that exists,
        // and the headline reports that instant rather than the digits typed.
        let gap = conversion(
            "2:30am in new york", now: moment("America/New_York", 2026, 3, 8, 12),
            cities: [newYork])
        expect(compact(gap?.sourceTime) == "3:30AM", "a skipped wall-clock time reports what exists")
        expect(time(gap, "New York") == "3:30AM", "the New York row agrees with the headline")

        // The repeated hour after a fall-back resolves to its first (still-daylight) occurrence.
        let repeated = conversion(
            "1:30am in new york", now: moment("America/New_York", 2026, 11, 1, 12),
            cities: [newYork])
        expect(
            time(repeated, "Local Time") == "5:30AM",
            "an ambiguous repeated hour takes the earlier occurrence")

        // Transitions are read per city, not applied globally: one instant, two DST states.
        let mixed = conversion(
            "8pm in london", now: moment("Europe/London", 2026, 7, 15, 12),
            cities: [london, sydney])
        expect(time(mixed, "London") == "8:00PM", "the source city keeps the typed time in summer")
        expect(
            time(mixed, "Sydney") == "5:00AM",
            "Sydney reads the same instant on standard time while London is on DST")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passed += 1
        } else {
            failed += 1
            print("FAIL: \(message)")
        }
    }

    private static func compact(_ value: String?) -> String? {
        value.map { String($0.filter { !$0.isWhitespace }) }
    }

    /// Formatted times separate the meridiem with a narrow no-break space; compare on plain ones.
    private static func spaced(_ value: String?) -> String? {
        value.map { String($0.map { $0.isWhitespace ? " " : $0 }) }
    }
}
