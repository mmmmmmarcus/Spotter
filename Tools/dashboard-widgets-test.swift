import Foundation

@main
@MainActor
struct DashboardWidgetsTests {
    private static var failures = 0

    static func main() {
        check(
            DashboardWidgetsEngine.widgetKinds(from: nil)
                == Set(DashboardWidgetKind.allCases),
            "missing widget preferences should preserve the two-widget default")
        check(
            DashboardWidgetsEngine.widgetKinds(from: []) == [],
            "an explicitly empty widget selection should remain empty")
        check(
            DashboardWidgetsEngine.widgetKinds(
                from: ["clock", "codex", "claude-code", "future-widget"])
                == [.clock],
            "removed and unknown widget identifiers should be ignored")

        let fallbackTimeZone = TimeZone(identifier: "Asia/Shanghai")!
        check(
            DashboardWidgetsEngine.resolvedTimeZone(identifier: "America/New_York", fallback: fallbackTimeZone)
                .identifier == "America/New_York",
            "a selected clock time zone should resolve")
        check(
            DashboardWidgetsEngine.resolvedTimeZone(identifier: "Missing/Zone", fallback: fallbackTimeZone)
                == fallbackTimeZone,
            "an unavailable clock time zone should fall back safely")
        check(
            DashboardWidgetsEngine.effectiveCalendarSourceIdentifier(
                selected: "icloud", availableIdentifiers: ["icloud", "exchange"]) == "icloud",
            "an available calendar account should remain selected")
        check(
            DashboardWidgetsEngine.effectiveCalendarSourceIdentifier(
                selected: "removed", availableIdentifiers: ["icloud", "exchange"]) == nil,
            "an unavailable calendar account should fall back to all accounts")

        check(
            DashboardWidgetsEngine.shouldIncludeCalendarEvent(
                isAllDay: false, sourceIdentifier: "icloud", selectedSourceIdentifier: nil,
                includesAllDayEvents: true),
            "all accounts should accept a timed event")
        check(
            !DashboardWidgetsEngine.shouldIncludeCalendarEvent(
                isAllDay: true, sourceIdentifier: "icloud", selectedSourceIdentifier: nil,
                includesAllDayEvents: false),
            "the all-day preference should exclude all-day events")
        check(
            !DashboardWidgetsEngine.shouldIncludeCalendarEvent(
                isAllDay: false, sourceIdentifier: "exchange",
                selectedSourceIdentifier: "icloud", includesAllDayEvents: true),
            "a selected calendar account should exclude other accounts")
        check(
            DashboardWidgetsEngine.shouldIncludeCalendarEvent(
                isAllDay: false, sourceIdentifier: "icloud",
                selectedSourceIdentifier: "icloud", includesAllDayEvents: true),
            "a selected calendar account should include its own events")

        let utc = TimeZone(identifier: "UTC")!
        // 1970-01-01 12:00:00 UTC — every hand straight up.
        let noon = DashboardWidgetsEngine.clockHandAngles(
            for: Date(timeIntervalSince1970: 43200), timeZone: utc)
        check(noon == ClockHandAngles(hour: 0, minute: 0, second: 0),
            "noon should point every hand at 12")

        // 21:45:15 UTC — the hour hand rides the minutes, the minute hand the seconds.
        let evening = DashboardWidgetsEngine.clockHandAngles(
            for: Date(timeIntervalSince1970: 21 * 3600 + 45 * 60 + 15), timeZone: utc)
        check(near(evening.hour, 292.625), "21:45:15 hour hand should sit at 292.625°")
        check(near(evening.minute, 271.5), "21:45:15 minute hand should sit at 271.5°")
        check(near(evening.second, 90), "21:45:15 second hand should sit at 90°")

        // The same instant three hours west lands the hour hand a quarter turn back.
        let shifted = DashboardWidgetsEngine.clockHandAngles(
            for: Date(timeIntervalSince1970: 21 * 3600 + 45 * 60 + 15),
            timeZone: TimeZone(secondsFromGMT: -3 * 3600)!)
        check(near(shifted.hour, 202.625), "the clock should follow the selected time zone")
        check(near(shifted.minute, evening.minute) && near(shifted.second, evening.second),
            "a whole-hour zone offset should move only the hour hand")

        // Weather: WMO 4677 mapping, including the day/night symbol split and the unknown-code floor.
        check(
            DashboardWeatherEngine.condition(forWeatherCode: 0, isDay: true).symbolName
                == "sun.max.fill",
            "a clear day should render the sun")
        check(
            DashboardWeatherEngine.condition(forWeatherCode: 0, isDay: false).symbolName
                == "moon.stars.fill",
            "a clear night should render the moon")
        check(
            DashboardWeatherEngine.condition(forWeatherCode: 95, isDay: true).description
                == "Thunderstorm",
            "code 95 should read as a thunderstorm")
        check(
            DashboardWeatherEngine.condition(forWeatherCode: 99, isDay: true).description
                == "Thunderstorm with Hail",
            "code 99 should name the hail")
        check(
            DashboardWeatherEngine.condition(forWeatherCode: 65, isDay: true).symbolName
                == "cloud.heavyrain.fill",
            "heavy rain should escalate the symbol")
        check(
            DashboardWeatherEngine.condition(forWeatherCode: 3, isDay: true)
                == DashboardWeatherEngine.condition(forWeatherCode: 3, isDay: false),
            "overcast should not vary by day or night")
        check(
            DashboardWeatherEngine.condition(forWeatherCode: 7777, isDay: true).description
                == "Unknown",
            "an unrecognized code should still render a card")

        check(
            DashboardWeatherEngine.formattedTemperature(celsius: 28.4, unit: .celsius) == "28°",
            "a Celsius reading should render whole degrees")
        check(
            DashboardWeatherEngine.formattedTemperature(celsius: 100, unit: .fahrenheit) == "212°",
            "Fahrenheit should convert from the stored Celsius")
        check(
            DashboardWeatherEngine.formattedTemperature(celsius: -0.4, unit: .celsius) == "0°",
            "a rounding artifact should never print as -0°")
        check(
            DashboardWeatherEngine.resolvedUnit(from: nil) == .celsius
                && DashboardWeatherEngine.resolvedUnit(from: "nonsense") == .celsius
                && DashboardWeatherEngine.resolvedUnit(from: "fahrenheit") == .fahrenheit,
            "an unknown unit should fall back to Celsius")

        let guangzhou = WeatherCity(
            id: 1809858, name: "Guangzhou", latitude: 23.11667, longitude: 113.25,
            country: "China", region: "Guangdong")
        check(
            guangzhou.detailLabel == "Guangdong, China",
            "a city should describe itself by region and country")
        let reading = WeatherSnapshot(
            cityID: guangzhou.id, cityName: guangzhou.name, temperatureCelsius: 28,
            weatherCode: 95, isDay: true, fetchedAt: Date(timeIntervalSince1970: 0))
        check(
            DashboardWeatherEngine.isSnapshot(reading, current: guangzhou),
            "a reading should match the city it was fetched for")
        check(
            !DashboardWeatherEngine.isSnapshot(reading, current: .default),
            "changing the city should invalidate the previous city's reading")

        // An unset city resolves to a fixed place, never one inferred from the Mac.
        check(
            WeatherCity.default.name == "Tokyo" && WeatherCity.default.country == "Japan",
            "the default city should be Tokyo, Japan")
        check(
            DashboardWeatherEngine.forecastURL(
                latitude: WeatherCity.default.latitude,
                longitude: WeatherCity.default.longitude) != nil,
            "the default city should produce a usable forecast URL")

        let forecast = DashboardWeatherEngine.forecastURL(latitude: 23.11667, longitude: 113.25)
        check(
            forecast?.host() == "api.open-meteo.com"
                && forecast?.absoluteString.contains("latitude=23.11667") == true,
            "the forecast URL should carry the chosen coordinates")
        check(
            DashboardWeatherEngine.geocodingURL(query: "  ") == nil,
            "a blank search should never become a request")
        check(
            DashboardWeatherEngine.geocodingURL(query: "São Paulo")?
                .absoluteString.contains("name=S%C3%A3o%20Paulo") == true,
            "a search term should be percent-encoded")

        print(failures == 0 ? "Dashboard widgets tests passed" : "\(failures) test(s) failed")
        exit(failures == 0 ? 0 : 1)
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    private static func near(_ value: Double, _ expected: Double) -> Bool {
        abs(value - expected) < 0.0001
    }
}
