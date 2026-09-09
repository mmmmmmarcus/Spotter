import Foundation

/// The unit the dashboard renders a temperature in. Readings are always fetched in Celsius and
/// converted here, so flipping the unit costs no request.
enum WeatherUnit: String, CaseIterable, Equatable, Sendable {
    case celsius
    case fahrenheit

    var label: String {
        switch self {
        case .celsius: return "Celsius (°C)"
        case .fahrenheit: return "Fahrenheit (°F)"
        }
    }
}

/// Where the answer to the one weather question stands. "Asked" and "granted" are two different
/// facts: a decline is an answer, so it must never be asked again, and it is not a grant.
enum WeatherConsentState: Equatable, Sendable {
    case unanswered
    case declined
    case granted
}

/// What macOS allows, as a plain value — a Foundation mirror of CoreLocation's status, so the pure
/// layer never sees a `CLLocationManager`.
enum WeatherLocationAuthorization: String, Equatable, Sendable {
    case notDetermined
    case denied
    case restricted
    case authorized
}

/// Where the reading is taken: one coarse fix from Location Services, at the precision a city
/// forecast needs and no finer. There is no manual city, so this is the only place weather has.
struct WeatherPlace: Codable, Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    /// The zone Open-Meteo names for these coordinates, learned from the forecast it already answers
    /// with `timezone=auto`. Nil until the first reading lands, which is what leaves an offline Mac
    /// on the clock zone it already had rather than stripping it of one.
    var timeZoneIdentifier: String? = nil
}

/// What Spotter may honestly say about where the weather is read. Removing manual entry removed the
/// only recourse, so every failure names itself: none of them falls back to somewhere else's
/// weather, which would be a wrong reading with no way to correct it.
enum WeatherLocationState: Equatable, Sendable {
    /// Permission is unanswered, or the first fix is still in flight.
    case waiting
    case located(WeatherPlace)
    case denied
    case restricted
    /// Allowed, but no fix — Location Services off system-wide, or the request failed.
    case unavailable
}

/// One rendered weather state: an SF Symbol and the short phrase beneath it.
struct WeatherCondition: Equatable, Sendable {
    let symbolName: String
    let description: String
}

struct WeatherSnapshot: Codable, Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    /// Always Celsius on disk and in flight; the view converts for display.
    let temperatureCelsius: Double
    let weatherCode: Int
    let isDay: Bool
    let fetchedAt: Date
    /// Today's low and high, in the located place's own day. Optional on purpose: the provider may
    /// answer without a daily block.
    var lowCelsius: Double?
    var highCelsius: Double?
    /// The zone the forecast named for these coordinates — the clock's, and what lets a relaunch
    /// keep the located zone without waiting on a fresh fix.
    var timeZoneIdentifier: String?

    var place: WeatherPlace {
        WeatherPlace(
            latitude: latitude, longitude: longitude, timeZoneIdentifier: timeZoneIdentifier)
    }
}

enum DashboardWeatherEngine {
    /// A grant counts as an answer on its own: it may arrive from a trusted settings file that
    /// carries no record of a dialog, and asking someone who is already opted in would be absurd.
    static func consentState(hasBeenAsked: Bool, isGranted: Bool) -> WeatherConsentState {
        if isGranted { return .granted }
        return hasBeenAsked ? .declined : .unanswered
    }

    /// The one-question rule: the dialog is raised only for someone who has never answered it.
    static func shouldPresentConsent(hasBeenAsked: Bool, isGranted: Bool) -> Bool {
        consentState(hasBeenAsked: hasBeenAsked, isGranted: isGranted) == .unanswered
    }

    /// WMO 4677, the code table Open-Meteo reports. Grouped the way a forecast reads rather than
    /// code-by-code: the intensity steps inside a family share a symbol and differ only in wording.
    static func condition(forWeatherCode code: Int, isDay: Bool) -> WeatherCondition {
        switch code {
        case 0:
            return WeatherCondition(
                symbolName: isDay ? "sun.max.fill" : "moon.stars.fill", description: "Clear")
        case 1:
            return WeatherCondition(
                symbolName: isDay ? "sun.max.fill" : "moon.stars.fill", description: "Mainly Clear")
        case 2:
            return WeatherCondition(
                symbolName: isDay ? "cloud.sun.fill" : "cloud.moon.fill",
                description: "Partly Cloudy")
        case 3:
            return WeatherCondition(symbolName: "cloud.fill", description: "Overcast")
        case 45:
            return WeatherCondition(symbolName: "cloud.fog.fill", description: "Fog")
        case 48:
            return WeatherCondition(symbolName: "cloud.fog.fill", description: "Rime Fog")
        case 51:
            return WeatherCondition(symbolName: "cloud.drizzle.fill", description: "Light Drizzle")
        case 53:
            return WeatherCondition(symbolName: "cloud.drizzle.fill", description: "Drizzle")
        case 55:
            return WeatherCondition(symbolName: "cloud.drizzle.fill", description: "Dense Drizzle")
        case 56, 57:
            return WeatherCondition(
                symbolName: "cloud.sleet.fill", description: "Freezing Drizzle")
        case 61:
            return WeatherCondition(symbolName: "cloud.rain.fill", description: "Light Rain")
        case 63:
            return WeatherCondition(symbolName: "cloud.rain.fill", description: "Rain")
        case 65:
            return WeatherCondition(symbolName: "cloud.heavyrain.fill", description: "Heavy Rain")
        case 66, 67:
            return WeatherCondition(symbolName: "cloud.sleet.fill", description: "Freezing Rain")
        case 71:
            return WeatherCondition(symbolName: "cloud.snow.fill", description: "Light Snow")
        case 73:
            return WeatherCondition(symbolName: "cloud.snow.fill", description: "Snow")
        case 75:
            return WeatherCondition(symbolName: "cloud.snow.fill", description: "Heavy Snow")
        case 77:
            return WeatherCondition(symbolName: "cloud.snow.fill", description: "Snow Grains")
        case 80:
            return WeatherCondition(
                symbolName: isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill",
                description: "Light Showers")
        case 81:
            return WeatherCondition(
                symbolName: isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill",
                description: "Showers")
        case 82:
            return WeatherCondition(
                symbolName: "cloud.heavyrain.fill", description: "Violent Showers")
        case 85, 86:
            return WeatherCondition(symbolName: "cloud.snow.fill", description: "Snow Showers")
        case 95:
            return WeatherCondition(symbolName: "cloud.bolt.rain.fill", description: "Thunderstorm")
        case 96, 99:
            return WeatherCondition(
                symbolName: "cloud.bolt.rain.fill", description: "Thunderstorm with Hail")
        default:
            // An unrecognized code still renders a card; inventing a condition would be worse than saying so.
            return WeatherCondition(symbolName: "cloud.fill", description: "Unknown")
        }
    }

    static func convert(celsius: Double, to unit: WeatherUnit) -> Double {
        switch unit {
        case .celsius: return celsius
        case .fahrenheit: return celsius * 9 / 5 + 32
        }
    }

    /// Whole degrees — the reference widget's readout, and a tenth of a degree is noise at this size.
    static func formattedTemperature(celsius: Double, unit: WeatherUnit) -> String {
        let value = convert(celsius: celsius, to: unit)
        // `-0°` is a rounding artifact, never something a forecast says.
        let rounded = value.rounded()
        return "\(Int(rounded == 0 ? 0 : rounded))°"
    }

    /// Today's low and high, captioning the two ends of the temperature bar. Nil when the reading
    /// predates the daily fetch — the bar loses both captions rather than being labelled at one end,
    /// which would read as the scale itself running from that number.
    static func formattedBarEnds(lowCelsius: Double?, highCelsius: Double?, unit: WeatherUnit)
        -> (low: String, high: String)?
    {
        guard let lowCelsius, let highCelsius else { return nil }
        return (
            formattedTemperature(celsius: lowCelsius, unit: unit),
            formattedTemperature(celsius: highCelsius, unit: unit)
        )
    }

    /// The fixed colour ramp the bar paints with: blue at `barMinimumCelsius`, green at
    /// `barMiddleCelsius`, red at `barMaximumCelsius`. Only the colours are absolute — the track
    /// spans today's range and shows the slice of this ramp that range covers, so a warm day starts
    /// orange rather than blue. Held in Celsius whatever the display unit, since the colour of a
    /// temperature is a physical fact and converting would repaint the bar for no reason.
    static let barMinimumCelsius = -10.0
    static let barMiddleCelsius = 20.0
    static let barMaximumCelsius = 40.0

    /// A range narrower than this is drawn this wide, centred on itself: a forecast whose low equals
    /// its high still needs a track with a direction rather than a division by zero.
    static let minimumBarSpanCelsius = 1.0

    /// Where a temperature falls on the ramp, 0 (blue end) to 1 (red end). Deliberately unclamped: a
    /// range sitting past either end still needs a direction for `rampWindow` to work from.
    static func temperatureRampLocation(celsius: Double) -> Double {
        (celsius - barMinimumCelsius) / (barMaximumCelsius - barMinimumCelsius)
    }

    /// The green stop's location, derived from the same scale so the gradient can't drift from it.
    static var temperatureRampMiddleLocation: Double {
        temperatureRampLocation(celsius: barMiddleCelsius)
    }

    /// Today's range as the bar actually draws it: ordered, and never narrower than
    /// `minimumBarSpanCelsius`. Only the geometry uses this — the captions still show the real low
    /// and high, since widening a flat day is a drawing concession, not a forecast.
    static func barRange(lowCelsius: Double, highCelsius: Double) -> (low: Double, high: Double) {
        let low = min(lowCelsius, highCelsius)
        let high = max(lowCelsius, highCelsius)
        guard high - low < minimumBarSpanCelsius else { return (low, high) }
        let middle = (low + high) / 2
        return (middle - minimumBarSpanCelsius / 2, middle + minimumBarSpanCelsius / 2)
    }

    /// Where the reading sits along today's range, 0 (low) to 1 (high). Clamped, so an afternoon that
    /// beat its own forecast parks the marker at an end instead of sliding off the track.
    static func markerPosition(celsius: Double, lowCelsius: Double, highCelsius: Double) -> Double {
        let range = barRange(lowCelsius: lowCelsius, highCelsius: highCelsius)
        return min(1, max(0, (celsius - range.low) / (range.high - range.low)))
    }

    /// The gradient's start and end in the track's own unit space, placed so the visible track shows
    /// exactly the ramp slice today's range covers. Both land outside 0...1 whenever the day covers
    /// less than the whole ramp, and that is the mechanism rather than a bug: it pushes the ramp's own
    /// ends off the track so only the slice between them is on screen. A range past either end of the
    /// ramp puts the whole track beyond the last stop, which paints it that end's flat colour.
    static func rampWindow(lowCelsius: Double, highCelsius: Double) -> (start: Double, end: Double) {
        let range = barRange(lowCelsius: lowCelsius, highCelsius: highCelsius)
        let low = temperatureRampLocation(celsius: range.low)
        // Never zero: `barRange` guarantees the span, so this can't divide by zero.
        let span = temperatureRampLocation(celsius: range.high) - low
        return (-low / span, (1 - low) / span)
    }

    /// The one state machine behind everything the card and the Settings row say: what macOS allows,
    /// and whether a fix has landed. A refusal is never softened into a reading from somewhere else —
    /// there is no city to fall back to any more, and a stale coordinate is not evidence of where
    /// this Mac is now.
    static func locationState(
        authorization: WeatherLocationAuthorization, place: WeatherPlace?, hasFailedFix: Bool
    ) -> WeatherLocationState {
        switch authorization {
        case .restricted: return .restricted
        case .denied: return .denied
        case .notDetermined: return .waiting
        case .authorized:
            guard let place else { return hasFailedFix ? .unavailable : .waiting }
            return .located(place)
        }
    }

    /// Only a located Mac has weather to draw, so this gates both the request and the complications.
    static func isLocated(_ state: WeatherLocationState) -> Bool {
        if case .located = state { return true }
        return false
    }

    static func place(from state: WeatherLocationState) -> WeatherPlace? {
        if case .located(let place) = state { return place }
        return nil
    }

    /// The glyph the clock face wears in place of a condition when there is no location to read.
    static let locationIssueSymbol = "location.slash"

    /// What the card says when it cannot report weather at all — nil while there is nothing wrong to
    /// report, so a face that simply hasn't been located yet stays a plain clock rather than an
    /// alarm. Both the tooltip and the spoken label read this.
    static func cardIssue(for state: WeatherLocationState) -> String? {
        switch state {
        case .located, .waiting: return nil
        case .denied, .restricted, .unavailable: return locationStatusMessage(for: state)
        }
    }

    /// The Settings row's own line. A located Mac states the coordinates it reads at, rounded to the
    /// precision actually requested; every other state states the failure and where to fix it.
    static func locationStatusMessage(for state: WeatherLocationState) -> String {
        switch state {
        case .waiting:
            return "Locating this Mac…"
        case .located(let place):
            return "Current location · \(formattedCoordinates(place))"
        case .denied:
            return "Location unavailable — Spotter is not allowed to use this Mac's location. "
                + "Allow it in System Settings ▸ Privacy & Security ▸ Location Services."
        case .restricted:
            return "Location unavailable — this Mac's policy blocks Location Services, so there is "
                + "nothing to allow."
        case .unavailable:
            return "Location unavailable — Spotter is allowed to use this Mac's location but could "
                + "not get a fix. Check that Location Services is on in System Settings ▸ Privacy "
                + "& Security."
        }
    }

    /// A restricted Mac has nothing for the button to open, so it is offered the sentence only.
    static func opensLocationSettings(for state: WeatherLocationState) -> Bool {
        switch state {
        case .denied, .unavailable: return true
        case .waiting, .located, .restricted: return false
        }
    }

    /// The one location line, as the pane's opening section states it: where the weather is read,
    /// and what the clock is running on. The clock half is always answered — a Mac that cannot be
    /// located keeps its saved zone or the system's, never a blank face.
    static func locationSummary(
        state: WeatherLocationState, clockTimeZoneIdentifier: String?,
        systemTimeZoneIdentifier: String
    ) -> String {
        let clock = DashboardWidgetsEngine.clockSummary(
            clockTimeZoneIdentifier: clockTimeZoneIdentifier,
            systemTimeZoneIdentifier: systemTimeZoneIdentifier)
        return "\(locationStatusMessage(for: state)) · clock on \(clock)"
    }

    /// One decimal place, which is about 11 km — the honest way to show a fix that was deliberately
    /// requested coarse, rather than printing digits the reading does not have.
    static func formattedCoordinates(_ place: WeatherPlace) -> String {
        let latitude = String(
            format: "%.1f°%@", abs(place.latitude), place.latitude >= 0 ? "N" : "S")
        let longitude = String(
            format: "%.1f°%@", abs(place.longitude), place.longitude >= 0 ? "E" : "W")
        return "\(latitude), \(longitude)"
    }

    /// Great-circle kilometres, for deciding whether a reading still belongs to where this Mac is.
    static func distanceKilometers(from: WeatherPlace, to: WeatherPlace) -> Double {
        let earthRadius = 6371.0
        let radians = Double.pi / 180
        let deltaLatitude = (to.latitude - from.latitude) * radians
        let deltaLongitude = (to.longitude - from.longitude) * radians
        let a =
            pow(sin(deltaLatitude / 2), 2) + cos(from.latitude * radians)
            * cos(to.latitude * radians) * pow(sin(deltaLongitude / 2), 2)
        return 2 * earthRadius * atan2(sqrt(a), sqrt(max(0, 1 - a)))
    }

    /// How far a fix may drift before the cached reading stops being this Mac's weather. Wide enough
    /// that the jitter of a coarse fix never throws a good reading away, tight enough that a flight
    /// does.
    static let placeChangeKilometers = 25.0

    /// A reading taken somewhere the Mac no longer is must not caption the new place — the card
    /// would then be exactly the wrong thing it can no longer be corrected from.
    static func isSnapshot(_ snapshot: WeatherSnapshot, current place: WeatherPlace) -> Bool {
        distanceKilometers(from: snapshot.place, to: place) <= placeChangeKilometers
    }

    /// The clock time zone the located place sets, or nil when it names none Spotter can resolve —
    /// an unusable or absent identifier must never overwrite a working clock setting.
    static func clockTimeZoneIdentifier(for place: WeatherPlace) -> String? {
        guard let identifier = place.timeZoneIdentifier, TimeZone(identifier: identifier) != nil
        else { return nil }
        return identifier
    }

    static func resolvedUnit(from rawValue: String?) -> WeatherUnit {
        WeatherUnit(rawValue: rawValue ?? "") ?? .celsius
    }

    static func forecastURL(latitude: Double, longitude: Double) -> URL? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "temperature_unit", value: "celsius"),
            // `auto` rather than UTC so "today" is the located place's own day — a UTC range would
            // roll over mid-afternoon in Asia. It is derived from the coordinates already in this
            // URL, so nothing further about this Mac leaves it, and its answer is what the clock
            // then runs on.
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        return components?.url
    }
}
