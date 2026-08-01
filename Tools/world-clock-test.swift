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

        let sf = WorldClockEngine.evaluate(
            "SF time now", now: instant, calendar: calendar, locale: locale)
        expect(sf?.city == "San Francisco", "SF alias resolves to San Francisco")
        expect(sf?.timeZoneIdentifier == "America/Los_Angeles", "SF uses Pacific time")
        expect(compact(sf?.time) == "5:00AM", "SF observes daylight saving time")

        let tokyo = WorldClockEngine.evaluate(
            "what time is it in Tokyo?", now: instant, calendar: calendar, locale: locale)
        expect(tokyo?.city == "Tokyo", "natural-language prefix resolves")
        expect(compact(tokyo?.time) == "9:00PM", "Tokyo formats the injected instant")

        let shanghai = WorldClockEngine.evaluate(
            "上海时间", now: instant, calendar: calendar, locale: locale)
        expect(shanghai?.city == "Shanghai", "Chinese time suffix resolves")
        expect(compact(shanghai?.time) == "8:00PM", "Shanghai formats the injected instant")

        let saoPaulo = WorldClockEngine.evaluate(
            "São Paulo time", now: instant, calendar: calendar, locale: locale)
        expect(
            saoPaulo?.timeZoneIdentifier == "America/Sao_Paulo",
            "IANA city index is diacritic-insensitive")

        expect(
            WorldClockEngine.evaluate("San Francisco", now: instant) == nil,
            "city-only app searches are not claimed")
        expect(
            WorldClockEngine.evaluate("staff time", now: instant) == nil,
            "short aliases match whole location phrases")
        expect(
            WorldClockEngine.evaluate("time", now: instant) == nil,
            "a location is required")

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
