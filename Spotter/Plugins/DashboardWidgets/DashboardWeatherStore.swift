import Combine
import Foundation

/// Downloads and caches the reading the dashboard weather widget renders. Network and disk live here;
/// `DashboardWeatherEngine` stays pure and is handed finished values.
///
/// This reaches the network, so it is gated on explicit consent — off until the user accepts the
/// dialog in Settings. Every path that could reach the network or surface a reading re-checks
/// `isEnabled` rather than trusting a caller. Modeled on `CurrencyRateStore`; keep the shapes aligned.
@MainActor
final class DashboardWeatherStore: ObservableObject {
    /// Open-Meteo (`open-meteo.com`) — no key, no account, free for non-commercial use. Only the
    /// coordinates of the city the user picked leave the Mac; Spotter never reads the system location.
    static let provider = "Open-Meteo"
    static let providerURL = URL(string: "https://open-meteo.com")!
    /// Conditions move far faster than exchange rates, but half-hourly is as often as this feed
    /// meaningfully changes — the age is measured from the persisted snapshot, so relaunching
    /// Spotter repeatedly doesn't re-fetch.
    static let refreshInterval: TimeInterval = 30 * 60
    /// Shorter retry so a machine that was offline at launch picks a reading up after it reconnects.
    private static let retryInterval: TimeInterval = 5 * 60

    /// Explicit user consent, persisted locally and mirrored by the trusted settings-sync file.
    @Published private(set) var isEnabled: Bool
    /// The newest reading, or nil when none has landed — and always nil while consent is withheld.
    @Published private(set) var snapshot: WeatherSnapshot?
    /// Never absent: an unset city reads as `WeatherCity.default` rather than hiding the card.
    @Published private(set) var city: WeatherCity
    @Published private(set) var unit: WeatherUnit
    @Published private(set) var isSearching = false
    @Published private(set) var searchResults: [WeatherCity] = []

    private enum Keys {
        static let consent = "dashboard-widgets.weather-enabled"
        static let city = "dashboard-widgets.weather-city"
        static let unit = "dashboard-widgets.weather-unit"
    }

    private let defaults: UserDefaults
    private let fileURL: URL
    private var pump: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Absent reads as false, which is the only safe default for a network feature.
        isEnabled = defaults.bool(forKey: Keys.consent)
        unit = DashboardWeatherEngine.resolvedUnit(from: defaults.string(forKey: Keys.unit))
        city =
            (defaults.data(forKey: Keys.city)
            .flatMap { try? JSONDecoder().decode(WeatherCity.self, from: $0) })
            ?? .default

        let bundleID = Bundle.main.bundleIdentifier ?? "com.spotter.app1"
        let base = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("weather.json")

        // Guard 1 — a disabled feature doesn't even read back a snapshot left on disk.
        guard isEnabled, let data = try? Data(contentsOf: fileURL) else { return }
        let cached = try? JSONDecoder().decode(WeatherSnapshot.self, from: data)
        // Guard 2 — the read path: a reading for a city the user has since changed never renders.
        snapshot = cached.flatMap { DashboardWeatherEngine.isSnapshot($0, current: city) ? $0 : nil }
    }

    /// What the widget may render: nil whenever consent is withheld.
    var reading: WeatherSnapshot? { isEnabled ? snapshot : nil }

    /// Starts the refresh loop: fetch whenever the cached reading is older than `refreshInterval`,
    /// otherwise sleep exactly until it expires. Guard 3 — no consent, no loop, so
    /// `AppCore.start()` can call this unconditionally.
    func start() {
        guard isEnabled else { return }
        // Replace rather than bail on a live pump: a loop that has already exited still leaves a
        // non-nil task behind, and a `pump == nil` guard would let that dead task block every restart.
        pump?.cancel()
        pump = Task { [weak self] in
            while !Task.isCancelled, let self, self.isEnabled {
                // Clamped: a reading stamped in the future (clock skew, an edited cache file) must
                // not park the loop for longer than one interval.
                let age = max(
                    0, self.snapshot.map { Date().timeIntervalSince($0.fetchedAt) } ?? .infinity)
                guard age >= Self.refreshInterval else {
                    try? await Task.sleep(for: .seconds(Self.refreshInterval - age))
                    continue
                }
                let ok = await self.fetchAndStore()
                try? await Task.sleep(for: .seconds(ok ? Self.refreshInterval : Self.retryInterval))
            }
        }
    }

    /// The Settings toggle's only entry point, called after the user accepts the consent dialog.
    /// Disabling tears the loop down, drops the reading and deletes the cached file — opting out
    /// shouldn't leave downloaded data behind. The chosen city is a plain preference, so it stays.
    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: Keys.consent)
        if enabled {
            start()
        } else {
            pump?.cancel()
            pump = nil
            searchTask?.cancel()
            searchTask = nil
            searchResults = []
            isSearching = false
            snapshot = nil
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    func setCity(_ city: WeatherCity) {
        guard city != self.city else { return }
        self.city = city
        if let data = try? JSONEncoder().encode(city) {
            defaults.set(data, forKey: Keys.city)
        } else {
            defaults.removeObject(forKey: Keys.city)
        }
        // The previous city's reading must never caption the new one.
        snapshot = nil
        try? FileManager.default.removeItem(at: fileURL)
        pump?.cancel()
        pump = nil
        start()
    }

    /// Unit is display-only — readings are stored in Celsius, so a flip needs no request.
    func setUnit(_ unit: WeatherUnit) {
        guard unit != self.unit else { return }
        self.unit = unit
        defaults.set(unit.rawValue, forKey: Keys.unit)
    }

    /// Restores consent, city and unit from a trusted backup or sync file. Trusting such a file is
    /// itself the consent act, so this may switch the feature on — the same rule the other
    /// consent-gated stores follow. Returns how many fields were touched, for the import summary.
    @discardableResult
    func applyPreferences(enabled: Bool?, cityData: Data?, unitRawValue: String?) -> Int {
        var count = 0
        if let unitRawValue {
            setUnit(DashboardWeatherEngine.resolvedUnit(from: unitRawValue))
            count += 1
        }
        if let cityData {
            // Empty data is how an older backup recorded "no city"; that restores as the default.
            setCity(
                (try? JSONDecoder().decode(WeatherCity.self, from: cityData)) ?? .default)
            count += 1
        }
        if let enabled {
            setEnabled(enabled)
            count += 1
        }
        return count
    }

    /// Encoded city for a backup snapshot.
    var encodedCity: Data {
        (try? JSONEncoder().encode(city)) ?? Data()
    }

    /// Manual "Update Now" from Settings. Returns whether a fresh reading landed, so the pane can say
    /// the fetch failed instead of leaving the button to spring back with nothing changed.
    func refreshNow() async -> Bool {
        guard isEnabled else { return false }
        return await fetchAndStore()
    }

    /// Debounced city lookup for the Settings picker. Guard — a search is a network request too, so
    /// it is refused without consent rather than quietly geocoding what the user types.
    func search(_ query: String) {
        searchTask?.cancel()
        guard isEnabled, let url = DashboardWeatherEngine.geocodingURL(query: query) else {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self, self.isEnabled else { return }
            let found = (try? await Self.geocode(url: url)) ?? []
            // Re-checked after the await: consent can be withdrawn while the request is in flight.
            guard !Task.isCancelled, self.isEnabled else { return }
            self.searchResults = found
            self.isSearching = false
        }
    }

    func clearSearch() {
        searchTask?.cancel()
        searchTask = nil
        searchResults = []
        isSearching = false
    }

    private func fetchAndStore() async -> Bool {
        // Guard 4 — re-checked at the network boundary itself: the pump may have been sleeping when
        // the user revoked consent, and this is the last line before a request goes out.
        // Held locally so the post-await check compares against the city this request was built for.
        let city = self.city
        guard isEnabled,
            let url = DashboardWeatherEngine.forecastURL(
                latitude: city.latitude, longitude: city.longitude),
            let current = try? await Self.fetch(url: url)
        else { return false }
        // Re-check after the await: consent can be withdrawn, or the city changed, while the request
        // is in flight — a late response must not resurrect the feature or mislabel a new city.
        guard isEnabled, self.city.id == city.id else { return false }

        let fetched = WeatherSnapshot(
            cityID: city.id, cityName: city.name, temperatureCelsius: current.temperature,
            weatherCode: current.weatherCode, isDay: current.isDay, fetchedAt: Date(),
            lowCelsius: current.lowCelsius, highCelsius: current.highCelsius)
        snapshot = fetched
        if let data = try? JSONEncoder().encode(fetched) {
            try? data.write(to: fileURL, options: .atomic)
        }
        return true
    }

    /// Deliberately not `URLSession.shared`: a cacheable response would leave a second copy in the
    /// on-disk `URLCache` that `setEnabled(false)` never deletes. Cacheless, so revoking consent
    /// really does leave nothing behind.
    private nonisolated static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    /// Off-main by way of `URLSession`'s async API; only plain values cross back.
    private nonisolated static func fetch(url: URL) async throws -> CurrentWeather {
        let data = try await get(url)
        let decoded = try JSONDecoder().decode(ForecastResponse.self, from: data)
        guard decoded.current.temperature2m.isFinite else { throw URLError(.cannotParseResponse) }
        // The range is a nice-to-have, not the reading: a missing or non-finite daily block leaves the
        // card's bar without its end captions rather than failing the whole fetch.
        return CurrentWeather(
            temperature: decoded.current.temperature2m,
            weatherCode: decoded.current.weatherCode,
            isDay: decoded.current.isDay == 1,
            lowCelsius: decoded.daily?.temperature2mMin.first.flatMap { $0.isFinite ? $0 : nil },
            highCelsius: decoded.daily?.temperature2mMax.first.flatMap { $0.isFinite ? $0 : nil })
    }

    private nonisolated static func geocode(url: URL) async throws -> [WeatherCity] {
        let data = try await get(url)
        let decoded = try JSONDecoder().decode(GeocodingResponse.self, from: data)
        return (decoded.results ?? []).map {
            WeatherCity(
                id: $0.id, name: $0.name, latitude: $0.latitude, longitude: $0.longitude,
                country: $0.country, region: $0.admin1)
        }
    }

    private nonisolated static func get(_ url: URL) async throws -> Data {
        let request = URLRequest(url: url, timeoutInterval: 20)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private struct CurrentWeather: Sendable {
        let temperature: Double
        let weatherCode: Int
        let isDay: Bool
        let lowCelsius: Double?
        let highCelsius: Double?
    }

    private struct ForecastResponse: Decodable {
        struct Current: Decodable {
            let temperature2m: Double
            let weatherCode: Int
            let isDay: Int

            enum CodingKeys: String, CodingKey {
                case temperature2m = "temperature_2m"
                case weatherCode = "weather_code"
                case isDay = "is_day"
            }
        }
        struct Daily: Decodable {
            let temperature2mMax: [Double]
            let temperature2mMin: [Double]

            enum CodingKeys: String, CodingKey {
                case temperature2mMax = "temperature_2m_max"
                case temperature2mMin = "temperature_2m_min"
            }
        }
        let current: Current
        let daily: Daily?
    }

    private struct GeocodingResponse: Decodable {
        struct Result: Decodable {
            let id: Int
            let name: String
            let latitude: Double
            let longitude: Double
            let country: String?
            let admin1: String?
        }
        let results: [Result]?
    }
}
