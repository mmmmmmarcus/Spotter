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

        print("World Clock: \(passed) passed, \(failed) failed")
        if failed > 0 { exit(1) }
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
}
