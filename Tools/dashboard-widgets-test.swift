import Foundation

@main
@MainActor
struct DashboardWidgetsTests {
    private static var failures = 0

    static func main() {
        check(
            DashboardWidgetsEngine.widgetKinds(from: nil)
                == Set(DashboardWidgetKind.allCases.filter(\.ownsEnabledState)),
            "missing widget preferences should preserve the default set")
        check(
            !DashboardWidgetKind.uptime.ownsEnabledState,
            "uptime's switch is a consent act owned by its own store")
        check(
            DashboardWidgetKind.allCases.filter { $0 != .uptime }.allSatisfy(\.ownsEnabledState),
            "every other widget's switch is plain visibility")
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
            DashboardWeatherEngine.temperatureRampLocation(celsius: -10) == 0
                && DashboardWeatherEngine.temperatureRampLocation(celsius: 40) == 1,
            "the ramp's ends should sit at the ends of the colour scale")
        check(
            abs(DashboardWeatherEngine.temperatureRampMiddleLocation - 0.6) < 0.0001,
            "green should sit where 20°C falls on the ramp")
        check(
            DashboardWeatherEngine.temperatureRampLocation(celsius: 90) > 1
                && DashboardWeatherEngine.temperatureRampLocation(celsius: -40) < 0,
            "the ramp location stays unclamped, so a range past an end still has a direction")

        check(
            DashboardWeatherEngine.markerPosition(celsius: 25, lowCelsius: 25, highCelsius: 33) == 0
                && DashboardWeatherEngine.markerPosition(
                    celsius: 33, lowCelsius: 25, highCelsius: 33) == 1,
            "the marker should sit at the ends of today's own range, not the ramp's")
        check(
            abs(
                DashboardWeatherEngine.markerPosition(
                    celsius: 29, lowCelsius: 25, highCelsius: 33) - 0.5) < 0.0001,
            "the middle of today's range should land halfway along the track")
        check(
            DashboardWeatherEngine.markerPosition(celsius: 36, lowCelsius: 25, highCelsius: 33) == 1
                && DashboardWeatherEngine.markerPosition(
                    celsius: 20, lowCelsius: 25, highCelsius: 33) == 0,
            "a reading that beat its own forecast should clamp to an end, not leave the track")
        check(
            DashboardWeatherEngine.markerPosition(celsius: 30, lowCelsius: 30, highCelsius: 30)
                == 0.5,
            "a flat forecast should centre the marker rather than divide by zero")

        let flat = DashboardWeatherEngine.barRange(lowCelsius: 30, highCelsius: 30)
        check(
            flat.high - flat.low == DashboardWeatherEngine.minimumBarSpanCelsius
                && abs((flat.low + flat.high) / 2 - 30) < 0.0001,
            "a range narrower than the floor should widen around its own middle")
        let reversed = DashboardWeatherEngine.barRange(lowCelsius: 33, highCelsius: 25)
        check(
            reversed.low == 25 && reversed.high == 33,
            "a range arriving the wrong way round should be ordered before it is drawn")

        // The window maps the track's 0...1 onto exactly the ramp slice the day covers: solving the
        // gradient at each end must give back the ramp locations of today's low and high.
        let window = DashboardWeatherEngine.rampWindow(lowCelsius: 25, highCelsius: 33)
        let atStart = window.start
        let atEnd = window.end
        func rampLocation(atTrack x: Double) -> Double { (x - atStart) / (atEnd - atStart) }
        check(
            abs(
                rampLocation(atTrack: 0)
                    - DashboardWeatherEngine.temperatureRampLocation(celsius: 25)) < 0.0001,
            "the track's left edge should paint the colour of today's low")
        check(
            abs(
                rampLocation(atTrack: 1)
                    - DashboardWeatherEngine.temperatureRampLocation(celsius: 33)) < 0.0001,
            "the track's right edge should paint the colour of today's high")
        check(
            rampLocation(atTrack: 0) > DashboardWeatherEngine.temperatureRampMiddleLocation,
            "a warm day should start past green rather than at the ramp's blue end")
        // Both ends beyond the ramp's hot stop, which paints the whole track that flat colour.
        let scorching = DashboardWeatherEngine.rampWindow(lowCelsius: 42, highCelsius: 46)
        func scorchingLocation(atTrack x: Double) -> Double {
            (x - scorching.start) / (scorching.end - scorching.start)
        }
        check(
            scorchingLocation(atTrack: 0) > 1 && scorchingLocation(atTrack: 1) > 1,
            "a day past the ramp's hot end should sit entirely beyond it, painting a flat red")

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
        // The grid is always `limit` slots, so a device keeps its position as others come and go
        // rather than the whole card re-centring under the same reading.
        check(
            DashboardDeviceBatteryEngine.gaugeSlots(for: [], limit: 4)
                == [.empty(0), .empty(1), .empty(2), .empty(3)],
            "no devices should still hold the grid's four slots")
        check(
            DashboardDeviceBatteryEngine.gaugeSlots(for: [keyboard, mouse, trackpad], limit: 4)
                == [.device(keyboard), .device(mouse), .device(trackpad), .empty(3)],
            "devices within the limit should each get their own gauge, the rest left empty")
        check(
            DashboardDeviceBatteryEngine.gaugeSlots(for: [keyboard], limit: 4).count == 4,
            "one device should not grow to fill the card")
        check(
            DashboardDeviceBatteryEngine.gaugeSlots(for: [keyboard, mouse, trackpad, extra], limit: 4)
                == [.device(keyboard), .device(mouse), .device(trackpad), .device(extra)],
            "a full grid should carry no empty slot")
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

        // Arrangement: a saved order is repaired rather than trusted, and always covers every kind.
        check(
            DashboardWidgetsEngine.widgetOrder(from: nil) == DashboardWidgetKind.allCases,
            "no saved arrangement should fall back to the catalog order")
        check(
            DashboardWidgetsEngine.widgetOrder(from: ["file-info", "clock"]).prefix(2)
                == [.fileInfo, .clock],
            "a saved arrangement should lead with what it named")
        check(
            Set(DashboardWidgetsEngine.widgetOrder(from: ["file-info"]))
                == Set(DashboardWidgetKind.allCases),
            "a partial arrangement should still cover every widget")
        check(
            DashboardWidgetsEngine.widgetOrder(from: ["clock", "clock", "nonsense"]).count
                == DashboardWidgetKind.allCases.count,
            "duplicates and unknown identifiers should not change the widget count")
        check(
            DashboardWidgetsEngine.widgetOrder(from: ["clock", "clock"]).filter { $0 == .clock }
                .count == 1,
            "a duplicate should be kept only once")

        let order: [DashboardWidgetKind] = [.clock, .uptime, .deviceBattery, .nextEvent, .fileInfo]
        check(
            DashboardWidgetsEngine.reorder(order, moving: .fileInfo, to: 0).first == .fileInfo,
            "moving to the front should put the widget first")
        check(
            DashboardWidgetsEngine.reorder(order, moving: .clock, to: 4).last == .clock,
            "moving to the end should put the widget last")
        check(
            DashboardWidgetsEngine.reorder(order, moving: .clock, to: 1)
                == [.uptime, .clock, .deviceBattery, .nextEvent, .fileInfo],
            "a downward move should land where the dragged row was dropped")
        check(
            DashboardWidgetsEngine.reorder(order, moving: .clock, to: 0) == order,
            "moving onto its own position should change nothing")
        check(
            DashboardWidgetsEngine.reorder(order, moving: .clock, to: 9) == order,
            "an out-of-range destination should change nothing")
        check(
            Set(DashboardWidgetsEngine.reorder(order, moving: .nextEvent, to: 2)) == Set(order),
            "reordering should never add or drop a widget")

        // File Info: what the square says about a Finder selection.
        check(DashboardFileInfoSnapshot().isEmpty, "no selection should read as empty")
        // The card stays on the strip with nothing selected, so the empty snapshot still has lines
        // to draw — it names its source and says there is no selection.
        check(
            DashboardFileInfoSnapshot().kindLine == "Finder",
            "an empty snapshot should name where it reads from")
        check(
            DashboardFileInfoSnapshot().nameLine == "No selection",
            "an empty snapshot should say so rather than go blank")
        check(
            DashboardFileInfoSnapshot().sizeLine.isEmpty,
            "an empty snapshot should have no size to state")
        check(
            DashboardFileInfoSnapshot().iconPath == nil,
            "an empty snapshot should have no file icon, so the card rests on a generic glyph")

        let png = fileItem("Shot.png", kind: "PNG image", bytes: 1_500_000)
        let shot = DashboardFileInfoSnapshot(items: [png])
        check(shot.kindLine == "PNG image", "one file should lead with its kind")
        check(shot.nameLine == "Shot.png", "one file should be named by its filename")
        check(shot.sizeLine.contains("MB"), "one file should state its size")
        check(shot.iconPath == "/tmp/Shot.png", "the icon should come from the item")

        let folder = DashboardFileInfoSnapshot(items: [folderItem("Docs", children: 12)])
        check(folder.sizeLine == "12 items", "a folder should be counted rather than weighed")
        check(
            DashboardFileInfoSnapshot(items: [folderItem("Docs", children: 1)]).sizeLine == "1 item",
            "a single child should be singular")
        check(
            DashboardFileInfoSnapshot(items: [folderItem("Locked", children: nil)]).sizeLine.isEmpty,
            "an unreadable folder should drop the size line rather than guess")

        let app = DashboardFileInfoSnapshot(items: [
            fileItem("Spotter", kind: "Application", bytes: 12_000_000, path: "/Applications/Spotter.app")
        ])
        check(app.kindLine == "Application", "a package should state its kind")
        check(app.sizeLine.contains("MB"), "a package should be weighed like a file")

        let many = DashboardFileInfoSnapshot(items: [
            fileItem("a.png", kind: "PNG image", bytes: 1_000_000),
            fileItem("b.png", kind: "PNG image", bytes: 2_000_000),
        ])
        check(many.kindLine == "Selection", "several items have no one kind to lead with")
        check(many.nameLine == "2 items", "several items should be named by their count")
        check(
            many.sizeLine == DashboardFileInfoSummary.size(bytes: 3_000_000),
            "several items should sum to one size")
        check(many.iconPath == "/tmp/a.png", "several items should borrow the first icon")

        let mixed = DashboardFileInfoSnapshot(items: [
            fileItem("a.png", kind: "PNG image", bytes: 1_000_000),
            folderItem("Docs", children: 3), folderItem("More", children: 4),
        ])
        check(
            mixed.sizeLine == DashboardFileInfoSummary.size(bytes: 1_000_000) + " · 2 folders",
            "a mixed total should name the folders it could not cover")
        check(
            DashboardFileInfoSnapshot(items: [
                fileItem("a.png", kind: "PNG image", bytes: 1), folderItem("Docs", children: 3),
            ]).sizeLine.hasSuffix("· 1 folder"),
            "one uncovered folder should be singular")
        check(
            DashboardFileInfoSnapshot(items: [
                folderItem("A", children: 1), folderItem("B", children: 2),
            ]).sizeLine == "2 folders",
            "an all-folder selection should state only the folder count")
        check(
            !mixed.accessibilityLabel.isEmpty && mixed.accessibilityLabel.contains(","),
            "the three lines should be spoken as one sentence")

        check(DashboardFileInfoSummary.size(bytes: 512).contains("512"), "bytes should stay bytes")
        check(DashboardFileInfoSummary.size(bytes: 1_000).contains("KB"), "kilobytes are file-style")
        check(
            DashboardFileInfoSummary.size(bytes: 5_000_000_000).contains("GB"),
            "gigabytes are file-style")
        check(
            DashboardFileInfoSummary.size(bytes: -5) == DashboardFileInfoSummary.size(bytes: 0),
            "a negative size can only be a bad read, so it floors at zero")

        print(failures == 0 ? "Dashboard widgets tests passed" : "\(failures) test(s) failed")
        exit(failures == 0 ? 0 : 1)
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    private static func fileItem(
        _ name: String, kind: String, bytes: Int64, path: String? = nil
    ) -> DashboardFileInfoItem {
        DashboardFileInfoItem(
            path: path ?? "/tmp/\(name)", name: name, kind: kind, byteCount: bytes,
            childCount: nil)
    }

    private static func folderItem(_ name: String, children: Int?) -> DashboardFileInfoItem {
        DashboardFileInfoItem(
            path: "/tmp/\(name)", name: name, kind: "Folder", byteCount: nil,
            childCount: children)
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
