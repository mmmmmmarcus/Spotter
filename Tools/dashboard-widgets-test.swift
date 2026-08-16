import Foundation

@main
@MainActor
struct DashboardWidgetsTests {
    private static var failures = 0

    static func main() {
        check(
            DashboardWidgetsEngine.widgetKinds(from: nil)
                == Set(DashboardWidgetKind.allCases),
            "missing widget preferences should preserve the every-widget default")
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
        // Half a second later the second hand has moved 3°, so a faster redraw sweeps it rather than ticking.
        let halfSecondLater = DashboardWidgetsEngine.clockHandAngles(
            for: Date(timeIntervalSince1970: 21 * 3600 + 45 * 60 + 15.5), timeZone: utc)
        check(near(halfSecondLater.second, 93), "a half second should advance the second hand 3°")
        check(
            near(halfSecondLater.minute, 271.55) && near(halfSecondLater.hour, 292.6291666),
            "the sub-second fraction should carry into the minute and hour hands")

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
            weatherCode: 95, isDay: true, fetchedAt: Date(timeIntervalSince1970: 0),
            lowCelsius: 26, highCelsius: 33)
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

        let celsiusEnds = DashboardWeatherEngine.formattedBarEnds(
            lowCelsius: 26, highCelsius: 33, unit: .celsius)
        check(
            celsiusEnds?.low == "26°" && celsiusEnds?.high == "33°",
            "a complete daily block should caption both ends of the bar")
        let fahrenheitEnds = DashboardWeatherEngine.formattedBarEnds(
            lowCelsius: 0, highCelsius: 100, unit: .fahrenheit)
        check(
            fahrenheitEnds?.low == "32°" && fahrenheitEnds?.high == "212°",
            "the ends should convert from the stored Celsius like the reading does")
        check(
            DashboardWeatherEngine.formattedBarEnds(
                lowCelsius: 26, highCelsius: nil, unit: .celsius) == nil
                && DashboardWeatherEngine.formattedBarEnds(
                    lowCelsius: nil, highCelsius: 33, unit: .celsius) == nil,
            "half a range should caption neither end rather than one")

        check(
            DashboardWeatherEngine.temperatureBarPosition(celsius: -10) == 0
                && DashboardWeatherEngine.temperatureBarPosition(celsius: 40) == 1,
            "the bar's ends should sit at the ends of the scale")
        check(
            abs(DashboardWeatherEngine.temperatureBarPosition(celsius: 15) - 0.5) < 0.0001,
            "the scale's own midpoint should land halfway along the bar")
        check(
            DashboardWeatherEngine.temperatureBarPosition(celsius: -40) == 0
                && DashboardWeatherEngine.temperatureBarPosition(celsius: 90) == 1,
            "a reading beyond the scale should clamp to an end rather than slide off the track")
        check(
            abs(DashboardWeatherEngine.temperatureBarMiddlePosition - 0.6) < 0.0001,
            "green should sit where 20°C falls on the scale")

        let forecast = DashboardWeatherEngine.forecastURL(latitude: 23.11667, longitude: 113.25)
        check(
            forecast?.host() == "api.open-meteo.com"
                && forecast?.absoluteString.contains("latitude=23.11667") == true,
            "the forecast URL should carry the chosen coordinates")
        check(
            forecast?.absoluteString.contains("daily=temperature_2m_max,temperature_2m_min") == true
                || forecast?.absoluteString.contains(
                    "daily=temperature_2m_max%2Ctemperature_2m_min") == true,
            "the forecast URL should ask for today's high and low")
        check(
            forecast?.absoluteString.contains("timezone=auto") == true,
            "the daily range should be the city's own day, not UTC's")
        check(
            DashboardWeatherEngine.geocodingURL(query: "  ") == nil,
            "a blank search should never become a request")
        check(
            DashboardWeatherEngine.geocodingURL(query: "São Paulo")?
                .absoluteString.contains("name=S%C3%A3o%20Paulo") == true,
            "a search term should be percent-encoded")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let dayStart = date("2026-08-14 09:15", calendar)
        let dayEnd = date("2026-08-14 18:45", calendar)
        let nextMorning = date("2026-08-15 07:30", calendar)

        check(
            DashboardUptimeEngine.carriedOverSessionStart(dayStart, now: dayEnd, calendar: calendar)
                == dayStart,
            "a start stamped earlier the same day should carry over")
        check(
            DashboardUptimeEngine.carriedOverSessionStart(
                dayEnd, now: nextMorning, calendar: calendar) == nil,
            "yesterday's start should not survive midnight")
        check(
            DashboardUptimeEngine.carriedOverSessionStart(nil, now: dayEnd, calendar: calendar)
                == nil,
            "a day with no activity yet should have no start")
        check(
            DashboardUptimeEngine.carriedOverSessionStart(
                dayEnd, now: dayStart, calendar: calendar) == nil,
            "a start in the future should be dropped rather than report a negative session")

        let tallies = DashboardInputCounts(keys: 4182, clicks: 861)
        check(
            DashboardUptimeEngine.carriedOverCounts(
                tallies, countedDay: dayStart, now: dayEnd, calendar: calendar) == tallies,
            "counts should survive a relaunch on the same day")
        check(
            DashboardUptimeEngine.carriedOverCounts(
                tallies, countedDay: dayEnd, now: nextMorning, calendar: calendar) == .zero,
            "counts should zero on a new day")
        check(
            DashboardUptimeEngine.carriedOverCounts(
                tallies, countedDay: nil, now: dayEnd, calendar: calendar) == .zero,
            "counts with no recorded day should not be trusted")

        check(
            DashboardUptimeEngine.formattedElapsed(from: dayStart, to: dayEnd) == "9h 30m",
            "elapsed time should read as whole hours and minutes")
        check(
            DashboardUptimeEngine.formattedElapsed(
                from: dayStart, to: dayStart.addingTimeInterval(2_099)) == "34m",
            "under an hour should drop the hour component and floor the minute")
        check(
            DashboardUptimeEngine.formattedElapsed(from: dayEnd, to: dayStart) == "0m",
            "a backwards interval should floor at zero rather than go negative")

        check(
            DashboardUptimeEngine.formattedCount(0) == "0"
                && DashboardUptimeEngine.formattedCount(861) == "861"
                && DashboardUptimeEngine.formattedCount(4182) == "4,182"
                && DashboardUptimeEngine.formattedCount(1_234_567) == "1,234,567",
            "counts should group in threes independently of the Mac's locale")

        check(
            DashboardUptimeEngine.keysLabel(480) == "480 keys pressed"
                && DashboardUptimeEngine.clicksLabel(128) == "128 mouse clicks",
            "tallies should spell out what they counted")
        check(
            DashboardUptimeEngine.keysLabel(1) == "1 key pressed"
                && DashboardUptimeEngine.clicksLabel(1) == "1 mouse click",
            "the day's first key or click should read in the singular")
        check(
            DashboardUptimeEngine.keysLabel(0) == "0 keys pressed"
                && DashboardUptimeEngine.clicksLabel(12_345) == "12,345 mouse clicks",
            "zero should stay plural and a large tally should stay grouped")

        check(
            DashboardDeviceBatteryEngine.kind(forProductName: "Marcus’s Magic Mouse") == .mouse
                && DashboardDeviceBatteryEngine.kind(forProductName: "Magic Trackpad") == .trackpad
                && DashboardDeviceBatteryEngine.kind(forProductName: "Magic Keyboard") == .keyboard,
            "an owner-prefixed Apple product name should still resolve to its category")
        check(
            DashboardDeviceBatteryEngine.kind(forProductName: "MX Master 3S") == .other
                && DashboardDeviceBatteryEngine.kind(forProductName: "") == .other,
            "an unrecognized or missing product name should fall back to the generic kind")
        check(
            DashboardDeviceBatteryEngine.label(for: battery("Marcus’s Magic Mouse", 40)) == "Mouse"
                && DashboardDeviceBatteryEngine.label(for: battery("MX Master 3S", 40))
                    == "MX Master 3S",
            "a known category should shorten to its noun and anything else should keep its name")

        check(
            DashboardDeviceBatteryEngine.percentLabel(97) == "97%"
                && DashboardDeviceBatteryEngine.percentLabel(140) == "100%"
                && DashboardDeviceBatteryEngine.percentLabel(-3) == "0%",
            "a level outside 0–100 should clamp rather than be reported as read")
        check(
            DashboardDeviceBatteryEngine.isLow(19) && !DashboardDeviceBatteryEngine.isLow(20),
            "the low threshold should be exclusive")
        check(
            DashboardDeviceBatteryEngine.gaugeFraction(0) == 0
                && DashboardDeviceBatteryEngine.gaugeFraction(50) == 0.5
                && DashboardDeviceBatteryEngine.gaugeFraction(140) == 1,
            "the arc should sweep the clamped level as a fraction of the ring")

        check(
            !DashboardDeviceBatteryEngine.isOnExternalPower(statusFlags: 0)
                && DashboardDeviceBatteryEngine.isOnExternalPower(statusFlags: 5),
            "the flags a battery-powered and a cabled device report should read as they were observed")
        check(
            !DashboardDeviceBatteryEngine.isOnExternalPower(statusFlags: 6),
            "the undocumented upper bits alone should not claim external power")
        check(
            DashboardDeviceBatteryEngine.accessibilityLabel(
                for: [battery("Magic Trackpad", 100, charging: true)])
                == "Battery: Trackpad 100 percent, charging",
            "a charging device should say so where the bolt can't be read")

        let mouse = battery("Marcus’s Magic Mouse", 97)
        let trackpad = battery("Magic Trackpad", 100)
        let keyboard = battery("Magic Keyboard", 12)
        check(
            DashboardDeviceBatteryEngine.ordered([trackpad, mouse, keyboard]).map(\.percent)
                == [12, 97, 100],
            "devices should order by level so the emptiest headlines the card")
        check(
            DashboardDeviceBatteryEngine.ordered([
                battery("Magic Trackpad", 50, id: "b"), battery("Magic Trackpad", 50, id: "a"),
            ]).map(\.id) == ["a", "b"],
            "devices at the same level should hold a stable order between scans")

        let extra = battery("MX Master 3S", 88, id: "extra")
        let second = battery("Magic Keyboard", 60, id: "second")
        check(
            DashboardDeviceBatteryEngine.gaugeSlots(for: [], limit: 4) == [],
            "no devices should produce no gauges")
        check(
            DashboardDeviceBatteryEngine.gaugeSlots(for: [keyboard, mouse, trackpad], limit: 4)
                == [.device(keyboard), .device(mouse), .device(trackpad)],
            "devices within the limit should each get their own gauge")
        check(
            DashboardDeviceBatteryEngine.gaugeSlots(
                for: [keyboard, mouse, trackpad, extra, second], limit: 4)
                == [.device(keyboard), .device(mouse), .device(trackpad), .overflow(2)],
            "devices past the grid should be counted in the last slot rather than dropped")

        check(
            DashboardDeviceBatteryEngine.gaugeColumns(slotCount: 1) == 1
                && DashboardDeviceBatteryEngine.gaugeColumns(slotCount: 2) == 2
                && DashboardDeviceBatteryEngine.gaugeColumns(slotCount: 4) == 2,
            "a lone gauge should take the whole square and the rest should pair into two columns")
        check(
            DashboardDeviceBatteryEngine.gaugeRows(
                for: [.device(keyboard), .device(mouse), .device(trackpad)], columns: 2)
                == [[.device(keyboard), .device(mouse)], [.device(trackpad)]],
            "an odd count should leave the last row short rather than rebalancing")
        check(
            DashboardDeviceBatteryEngine.gaugeRows(for: [.device(keyboard)], columns: 0) == [],
            "a zero column count should produce no rows rather than loop")

        check(
            DashboardDeviceBatteryEngine.gaugeDiameter(
                slotCount: 1, interior: 96, spacing: 8) == 96,
            "a lone gauge should fill the square's interior")
        check(
            DashboardDeviceBatteryEngine.gaugeDiameter(
                slotCount: 4, interior: 96, spacing: 8) == 44,
            "a full grid should split the interior evenly around its gap")
        check(
            DashboardDeviceBatteryEngine.gaugeDiameter(
                slotCount: 3, interior: 96, spacing: 8) == 44,
            "three gauges should size to their two rows, not to the row that holds one")
        check(
            DashboardDeviceBatteryEngine.gaugeDiameter(
                slotCount: 0, interior: 96, spacing: 8) == 0,
            "no slots should ask for no diameter")

        check(
            DashboardDeviceBatteryEngine.accessibilityLabel(for: [keyboard, mouse])
                == "Battery: Keyboard 12 percent, Mouse 97 percent",
            "the card should read out every device it shows")
        check(
            DashboardDeviceBatteryEngine.accessibilityLabel(for: []) == "No device batteries",
            "an empty reading should not announce a level")

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

    private static func battery(
        _ productName: String, _ percent: Int, id: String = "id", charging: Bool = false
    ) -> DeviceBattery {
        DeviceBattery(
            id: id, productName: productName,
            kind: DashboardDeviceBatteryEngine.kind(forProductName: productName), percent: percent,
            isCharging: charging)
    }

    private static func date(_ stamp: String, _ calendar: Calendar) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: stamp)!
    }
}
