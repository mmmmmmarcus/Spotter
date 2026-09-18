import Foundation

// Fake location callbacks exercise the real store without requesting location or network access.
@MainActor
final class WeatherLocationProvider {
    static var latest: WeatherLocationProvider?
    var onAuthorization: ((WeatherLocationAuthorization) -> Void)?
    var onFix: ((Double, Double) -> Void)?
    var onFailure: (() -> Void)?
    var authorization: WeatherLocationAuthorization = .authorized
    var requests = 0
    var latitude = 1.0
    var longitude = 2.0
    func deliver(_ latitude: Double, _ longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
        onFix?(latitude, longitude)
    }
    init() { Self.latest = self }
    func requestAuthorizationIfNeeded() { }
    func requestFix() {
        requests += 1
        Task { @MainActor [weak self] in
            guard let self else { return }
            onFix?(latitude, longitude)
        }
    }
}

actor ForecastProbe {
    private(set) var calls = 0
    let fail: Bool
    init(fail: Bool = false) { self.fail = fail }
    func fetch(_ url: URL) async throws -> DashboardWeatherStore.CurrentWeather {
        calls += 1
        try await Task.sleep(for: .milliseconds(60))
        if fail { throw URLError(.notConnectedToInternet) }
        return DashboardWeatherStore.CurrentWeather(
            temperature: 20, weatherCode: 0, isDay: true, lowCelsius: 10,
            highCelsius: 25, timeZoneIdentifier: "UTC")
    }
}

@main @MainActor
struct WeatherRefreshTests {
    static func main() async throws {
        let suite = "spotter-weather-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: dir)
        }
        let probe = ForecastProbe()
        let store = DashboardWeatherStore(defaults: defaults,
            cacheURL: dir.appendingPathComponent("weather.json"), fetchWeather: { try await probe.fetch($0) })
        store.start()
        precondition(WeatherLocationProvider.latest == nil, "no location before consent")
        store.recordConsent(granted: true)
        try await Task.sleep(for: .milliseconds(250))
        let firstCount = await probe.calls
        precondition(firstCount == 1, "a fix callback must not cancel and restart the active fetch")
        precondition(store.snapshot != nil, "the first fetch must complete")
        let provider = WeatherLocationProvider.latest!
        precondition(provider.requests <= 3, "locating must not feed back into continuous requests")
        for _ in 0..<20 { provider.deliver(1.00001, 2.00001) }
        store.start()
        try await Task.sleep(for: .milliseconds(100))
        let unchangedCount = await probe.calls
        precondition(unchangedCount == 1, "nearby fixes and repeated start must keep the refresh cadence")
        provider.deliver(40, 50)
        try await Task.sleep(for: .milliseconds(250))
        let movedCount = await probe.calls
        precondition(movedCount == 2, "a material place change must wake the refresh loop")
        provider.onAuthorization?(.denied)
        precondition(store.snapshot == nil, "denial must discard the reading")
        let deniedCount = await probe.calls
        try await Task.sleep(for: .milliseconds(100))
        let stoppedCount = await probe.calls
        precondition(stoppedCount == deniedCount, "denial stops fetching")

        let failing = ForecastProbe(fail: true)
        let retryStore = DashboardWeatherStore(defaults: defaults,
            cacheURL: dir.appendingPathComponent("retry.json"), fetchWeather: { try await failing.fetch($0) })
        retryStore.start()
        try await Task.sleep(for: .milliseconds(250))
        let retryProvider = WeatherLocationProvider.latest!
        for _ in 0..<20 { retryProvider.onFix?(1, 2) }
        try await Task.sleep(for: .milliseconds(100))
        let failureCount = await failing.calls
        precondition(failureCount == 1, "location callbacks must not bypass the failed-fetch retry delay")
        retryProvider.onAuthorization?(.denied)
        print("Weather refresh: ALL PASSED")
    }
}
