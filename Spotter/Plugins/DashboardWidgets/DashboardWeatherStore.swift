import Combine
import Foundation

/// Downloads and caches the reading the dashboard weather widget renders, for wherever this Mac is.
/// Network, disk and Location Services live here; `DashboardWeatherEngine` stays pure and is handed
/// finished values.
///
/// This reaches the network, so it is gated on explicit consent — off until the user accepts the
/// dialog Spotter raises once, at first launch. Every path that could reach the network or surface a
/// reading re-checks `isEnabled` rather than trusting a caller. Consent is asked exactly once and,
/// once given, is permanent: there is no off switch (owner decision, Sep 2026), so "asked" and
/// "granted" are persisted separately — a decline is an answer that leaves the feature off.
///
/// The place is the Mac's own, from one coarse fix (owner decision, Sep 2026): there is no city to
/// pick and none to fall back to, so a Mac that cannot be located reports that rather than showing
/// somewhere else's weather.
@MainActor
final class DashboardWeatherStore: ObservableObject {
    /// Open-Meteo (`open-meteo.com`) — no key, no account, free for non-commercial use. Only the
    /// coordinates of the coarse fix leave the Mac.
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
    /// Whether the one dialog has been answered at all — a decline records this without granting.
    @Published private(set) var hasBeenAsked: Bool
    /// The newest reading, or nil when none has landed — and always nil while consent is withheld or
    /// this Mac cannot be located.
    @Published private(set) var snapshot: WeatherSnapshot?
    /// The last coarse fix, carried across launches by the cached reading itself.
    @Published private(set) var place: WeatherPlace?
    @Published private(set) var authorization: WeatherLocationAuthorization = .notDetermined
    /// Set by a fix that failed, so "allowed but no fix" can be told apart from "still looking".
    @Published private(set) var hasFailedFix = false
    @Published private(set) var unit: WeatherUnit

    /// Handed the located place's own zone, so the clock follows where this Mac is. Wired by
    /// `AppCore`, which owns the widget preferences this writes into.
    var onResolveTimeZone: ((String) -> Void)?

    private enum Keys {
        static let consent = "dashboard-widgets.weather-enabled"
        static let asked = "dashboard-widgets.weather-consent-asked"
        static let unit = "dashboard-widgets.weather-unit"
    }

    private let defaults: UserDefaults
    private let fileURL: URL
    private var pump: Task<Void, Never>?
    /// Created only once consent has been granted: no `CLLocationManager` exists before that.
    private var location: WeatherLocationProvider?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Absent reads as false, which is the only safe default for a network feature.
        isEnabled = defaults.bool(forKey: Keys.consent)
        hasBeenAsked = defaults.bool(forKey: Keys.asked)
        unit = DashboardWeatherEngine.resolvedUnit(from: defaults.string(forKey: Keys.unit))

        let bundleID = Bundle.main.bundleIdentifier ?? "com.spotter.app1"
        let base = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("weather.json")

        // Guard 1 — a disabled feature doesn't even read back a snapshot left on disk.
        guard isEnabled, let data = try? Data(contentsOf: fileURL),
            let cached = try? JSONDecoder().decode(WeatherSnapshot.self, from: data)
        else { return }
        // The cached reading carries the fix it was taken at, which is what a relaunch runs on until
        // a fresh one lands. Nothing renders from it until macOS confirms the grant is still there.
        snapshot = cached
        place = cached.place
    }

    /// What the widget may render: nil unless consent stands *and* this Mac is located, so a card
    /// can never caption a place Spotter can no longer confirm.
    var reading: WeatherSnapshot? {
        guard isEnabled, DashboardWeatherEngine.isLocated(locationState) else { return nil }
        return snapshot
    }

    var locationState: WeatherLocationState {
        DashboardWeatherEngine.locationState(
            authorization: authorization, place: place, hasFailedFix: hasFailedFix)
    }

    var consentState: WeatherConsentState {
        DashboardWeatherEngine.consentState(hasBeenAsked: hasBeenAsked, isGranted: isEnabled)
    }

    /// True only for someone who has never answered. The one place anything decides to ask.
    var needsConsentPrompt: Bool {
        DashboardWeatherEngine.shouldPresentConsent(hasBeenAsked: hasBeenAsked, isGranted: isEnabled)
    }

    /// The one entry point for an answer, from the first-launch dialog or the Settings row that
    /// stands in for it afterwards. Declining records the answer and leaves the feature off — and
    /// raises no system location prompt either; there is no path back through here to switch a
    /// granted feature off again.
    func recordConsent(granted: Bool) {
        hasBeenAsked = true
        defaults.set(true, forKey: Keys.asked)
        guard granted, !isEnabled else { return }
        isEnabled = true
        defaults.set(true, forKey: Keys.consent)
        start()
    }

    /// Starts locating and the refresh loop. Guard 2 — no consent, no location manager and no loop,
    /// so `AppCore.start()` can call this unconditionally.
    func start() {
        guard isEnabled else { return }
        startLocating()
        startPump()
    }

    /// Spotter's own question comes first and macOS's second: the system prompt is raised only after
    /// consent, so someone who declines is never asked for their location at all.
    private func startLocating() {
        guard isEnabled else { return }
        if location == nil {
            let provider = WeatherLocationProvider()
            provider.onAuthorization = { [weak self] in self?.handleAuthorization($0) }
            provider.onFix = { [weak self] in self?.handleFix(latitude: $0, longitude: $1) }
            provider.onFailure = { [weak self] in self?.handleFixFailure() }
            location = provider
            // Read before the prompt: an already-answered Mac starts in its real state rather than
            // spending a beat in `.waiting` — and a Mac that has since refused drops what it cached
            // here rather than waiting for a delegate callback that repeats what it already knows.
            handleAuthorization(provider.authorization)
        }
        location?.requestAuthorizationIfNeeded()
        location?.requestFix()
    }

    private func handleAuthorization(_ authorization: WeatherLocationAuthorization) {
        self.authorization = authorization
        switch authorization {
        case .authorized:
            hasFailedFix = false
            location?.requestFix()
            startPump()
        case .denied, .restricted:
            // Nothing may be attributed to a place Spotter is no longer allowed to confirm, so the
            // reading goes — from memory and from disk — rather than lingering as a stale claim.
            forgetReading()
        case .notDetermined:
            break
        }
    }

    private func handleFix(latitude: Double, longitude: Double) {
        hasFailedFix = false
        var located = WeatherPlace(latitude: latitude, longitude: longitude)
        // The zone belongs to the coordinates, so it survives a fix that only jittered — and is
        // dropped by one that moved, rather than dating a new place from the old one.
        if let previous = place,
            DashboardWeatherEngine.distanceKilometers(from: previous, to: located)
                <= DashboardWeatherEngine.placeChangeKilometers
        {
            located.timeZoneIdentifier = previous.timeZoneIdentifier
        }
        place = located
        publishClockTimeZone()
        // A reading from where this Mac no longer is must not caption where it now is.
        if let snapshot, !DashboardWeatherEngine.isSnapshot(snapshot, current: located) {
            self.snapshot = nil
            try? FileManager.default.removeItem(at: fileURL)
        }
        startPump()
    }

    private func handleFixFailure() {
        // Only the absence of a place is a failure to report: a Mac that has a fix and lost the next
        // one still knows where it is.
        guard place == nil else { return }
        hasFailedFix = true
    }

    private func forgetReading() {
        pump?.cancel()
        pump = nil
        snapshot = nil
        place = nil
        hasFailedFix = false
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Fetch whenever the cached reading is older than `refreshInterval`, otherwise sleep exactly
    /// until it expires. Guard 3 — the loop does not exist without consent and a located place.
    private func startPump() {
        guard isEnabled, place != nil else { return }
        // Replace rather than bail on a live pump: a loop that has already exited still leaves a
        // non-nil task behind, and a `pump == nil` guard would let that dead task block every restart.
        pump?.cancel()
        pump = Task { [weak self] in
            while !Task.isCancelled, let self, self.isEnabled, self.place != nil {
                // Clamped: a reading stamped in the future (clock skew, an edited cache file) must
                // not park the loop for longer than one interval.
                let age = max(
                    0, self.snapshot.map { Date().timeIntervalSince($0.fetchedAt) } ?? .infinity)
                guard age >= Self.refreshInterval else {
                    try? await Task.sleep(for: .seconds(Self.refreshInterval - age))
                    continue
                }
                // A fresh fix for the next cycle, so a Mac that travelled reads its new place — one
                // request, alongside a refresh that was happening anyway.
                self.location?.requestFix()
                let ok = await self.fetchAndStore()
                try? await Task.sleep(for: .seconds(ok ? Self.refreshInterval : Self.retryInterval))
            }
        }
    }

    /// Unit is display-only — readings are stored in Celsius, so a flip needs no request.
    func setUnit(_ unit: WeatherUnit) {
        guard unit != self.unit else { return }
        self.unit = unit
        defaults.set(unit.rawValue, forKey: Keys.unit)
    }

    /// Restores consent and unit from a trusted backup or sync file. Trusting such a file is itself
    /// the consent act, so this may switch the feature on — the same rule the other consent-gated
    /// stores follow. A file carrying `false` is not a revocation and not an answer: there is no off
    /// switch, and this Mac's user still gets asked. The place is deliberately not in the file: a
    /// coordinate describes the Mac it was measured on, so each Mac locates itself. Returns how many
    /// fields were touched, for the import summary.
    @discardableResult
    func applyPreferences(enabled: Bool?, unitRawValue: String?) -> Int {
        var count = 0
        if let unitRawValue {
            setUnit(DashboardWeatherEngine.resolvedUnit(from: unitRawValue))
            count += 1
        }
        if let enabled, enabled {
            recordConsent(granted: true)
            count += 1
        }
        return count
    }

    /// Manual "Update Now" from Settings. Returns whether a fresh reading landed, so the pane can say
    /// the fetch failed instead of leaving the button to spring back with nothing changed.
    func refreshNow() async -> Bool {
        guard isEnabled else { return false }
        location?.requestFix()
        return await fetchAndStore()
    }

    private func fetchAndStore() async -> Bool {
        // Guard 4 — re-checked at the network boundary itself: the pump may have been sleeping when
        // the grant changed, and this is the last line before a request goes out. The place is held
        // locally so the post-await check compares against the one this request was built for.
        guard isEnabled, let place = DashboardWeatherEngine.place(from: locationState),
            let url = DashboardWeatherEngine.forecastURL(
                latitude: place.latitude, longitude: place.longitude),
            let current = try? await Self.fetch(url: url)
        else { return false }
        // Re-check after the await: consent can be withdrawn, or the Mac moved, while the request is
        // in flight — a late response must not resurrect the feature or mislabel a new place.
        guard isEnabled, let now = self.place,
            DashboardWeatherEngine.distanceKilometers(from: place, to: now)
                <= DashboardWeatherEngine.placeChangeKilometers
        else { return false }

        let fetched = WeatherSnapshot(
            latitude: place.latitude, longitude: place.longitude,
            temperatureCelsius: current.temperature, weatherCode: current.weatherCode,
            isDay: current.isDay, fetchedAt: Date(), lowCelsius: current.lowCelsius,
            highCelsius: current.highCelsius, timeZoneIdentifier: current.timeZoneIdentifier)
        snapshot = fetched
        self.place = fetched.place
        publishClockTimeZone()
        if let data = try? JSONEncoder().encode(fetched) {
            try? data.write(to: fileURL, options: .atomic)
        }
        return true
    }

    /// The clock follows the located place through the zone the forecast already names for those
    /// coordinates — no second request, and nothing further about this Mac leaves it. An identifier
    /// macOS cannot resolve is dropped rather than allowed to blank a working clock setting.
    private func publishClockTimeZone() {
        guard let place,
            let identifier = DashboardWeatherEngine.clockTimeZoneIdentifier(for: place)
        else { return }
        onResolveTimeZone?(identifier)
    }

    /// Deliberately not `URLSession.shared`: a cacheable response would leave a second copy in the
    /// on-disk `URLCache` nothing else would ever delete. Cacheless, so a reading only ever exists
    /// where this store put it.
    private nonisolated static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    /// Off-main by way of `URLSession`'s async API; only plain values cross back.
    private nonisolated static func fetch(url: URL) async throws -> CurrentWeather {
        let request = URLRequest(url: url, timeoutInterval: 20)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(ForecastResponse.self, from: data)
        guard decoded.current.temperature2m.isFinite else { throw URLError(.cannotParseResponse) }
        // The range is a nice-to-have, not the reading: a missing or non-finite daily block leaves the
        // card's bar without its end captions rather than failing the whole fetch.
        return CurrentWeather(
            temperature: decoded.current.temperature2m,
            weatherCode: decoded.current.weatherCode,
            isDay: decoded.current.isDay == 1,
            lowCelsius: decoded.daily?.temperature2mMin.first.flatMap { $0.isFinite ? $0 : nil },
            highCelsius: decoded.daily?.temperature2mMax.first.flatMap { $0.isFinite ? $0 : nil },
            timeZoneIdentifier: decoded.timezone)
    }

    private struct CurrentWeather: Sendable {
        let temperature: Double
        let weatherCode: Int
        let isDay: Bool
        let lowCelsius: Double?
        let highCelsius: Double?
        let timeZoneIdentifier: String?
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
        /// What `timezone=auto` resolved the coordinates to — the clock's zone, for free.
        let timezone: String?
    }
}
