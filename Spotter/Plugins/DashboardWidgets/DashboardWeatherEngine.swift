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

/// A place chosen from a search, or the fixed default below. Spotter never reads the Mac's location.
struct WeatherCity: Codable, Equatable, Identifiable, Sendable {
    let id: Int
    let name: String
    let latitude: Double
    let longitude: Double
    let country: String?
    let region: String?

    /// "Guangzhou, Guangdong, China" — enough to tell same-named places apart in the picker.
    var detailLabel: String {
        [region, country].compactMap { $0?.nilIfBlank }.joined(separator: ", ")
    }

    /// Shown until the user picks their own. A fixed place, not a guess at where this Mac is —
    /// deriving one from the locale or time zone would be location inference by another name.
    /// The identifier is Open-Meteo's, so searching Tokyo marks this row as already selected.
    static let `default` = WeatherCity(
        id: 1_850_147, name: "Tokyo", latitude: 35.6895, longitude: 139.69171,
        country: "Japan", region: "Tokyo")
}

/// One rendered weather state: an SF Symbol and the short phrase beneath it.
struct WeatherCondition: Equatable, Sendable {
    let symbolName: String
    let description: String
}

struct WeatherSnapshot: Codable, Equatable, Sendable {
    let cityID: Int
    let cityName: String
    /// Always Celsius on disk and in flight; the view converts for display.
    let temperatureCelsius: Double
    let weatherCode: Int
    let isDay: Bool
    let fetchedAt: Date
    /// Today's low and high, in the city's own day. Optional on purpose: a file cached before the
    /// daily fetch existed still decodes, and the provider may answer without a daily block.
    var lowCelsius: Double?
    var highCelsius: Double?
}

enum DashboardWeatherEngine {
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

    /// The temperature bar's fixed ends and its green midpoint, in Celsius. An absolute scale rather
    /// than today's range: the same temperature always sits at the same point, so the marker reads as
    /// "how hot is it" without the ends having to be read. Defined in Celsius whatever the display
    /// unit, since the position is a physical fact and converting would move the dot for no reason.
    static let barMinimumCelsius = -10.0
    static let barMiddleCelsius = 20.0
    static let barMaximumCelsius = 40.0

    /// Where a reading sits along the bar, 0 (cold end) to 1 (hot end). Clamped, so a record-breaking
    /// reading parks the marker at an end instead of sliding off the track.
    static func temperatureBarPosition(celsius: Double) -> Double {
        let span = barMaximumCelsius - barMinimumCelsius
        return min(1, max(0, (celsius - barMinimumCelsius) / span))
    }

    /// The green stop's location, derived from the same scale so the gradient can't drift from it.
    static var temperatureBarMiddlePosition: Double {
        temperatureBarPosition(celsius: barMiddleCelsius)
    }

    static func resolvedUnit(from rawValue: String?) -> WeatherUnit {
        WeatherUnit(rawValue: rawValue ?? "") ?? .celsius
    }

    /// A snapshot for a city the user has since changed is stale beyond refreshing — the card must not
    /// caption a new city with the previous city's reading.
    static func isSnapshot(_ snapshot: WeatherSnapshot, current city: WeatherCity) -> Bool {
        snapshot.cityID == city.id
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
            // `auto` rather than UTC so "today" is the city's own day — a UTC range would roll over
            // mid-afternoon in Asia. It is derived from the coordinates already in this URL, so
            // nothing further about this Mac leaves it.
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        return components?.url
    }

    /// Nil for a blank query, so an empty search field can never become a request.
    static func geocodingURL(query: String) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        components?.queryItems = [
            URLQueryItem(name: "name", value: trimmed),
            URLQueryItem(name: "count", value: "8"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json"),
        ]
        return components?.url
    }
}

extension String {
    fileprivate var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
