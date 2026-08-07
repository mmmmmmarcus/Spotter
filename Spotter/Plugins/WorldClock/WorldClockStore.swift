import Combine
import Foundation

@MainActor
final class WorldClockStore: ObservableObject {
    private static let citiesKey = "world-clock.cities"

    @Published private(set) var cityIDs: [String]
    @Published private(set) var now: Date

    private let defaults: UserDefaults
    private let nowProvider: @Sendable () -> Date
    private var clockTask: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.defaults = defaults
        nowProvider = now
        self.now = now()
        if let stored = defaults.stringArray(forKey: Self.citiesKey) {
            cityIDs = stored.filter { WorldClockEngine.city(id: $0) != nil }
        } else {
            cityIDs = WorldClockEngine.defaultCities.map(\.id)
        }
    }

    var cities: [WorldClockCity] { cityIDs.compactMap(WorldClockEngine.city(id:)) }

    var usesDefaults: Bool { cityIDs == WorldClockEngine.defaultCities.map(\.id) }

    func availableCities(matching query: String) -> [WorldClockCity] {
        WorldClockEngine.searchCities(query, excluding: Set(cityIDs))
    }

    func add(_ city: WorldClockCity) {
        guard !cityIDs.contains(city.id) else { return }
        cityIDs.append(city.id)
        persist()
    }

    func remove(id: String) {
        cityIDs.removeAll { $0 == id }
        persist()
    }

    func restoreDefaults() {
        cityIDs = WorldClockEngine.defaultCities.map(\.id)
        persist()
    }

    /// Settings-backup import: replace the whole list, dropping IDs this build's catalog doesn't know.
    func replace(cityIDs newIDs: [String]) {
        let filtered = newIDs.filter { WorldClockEngine.city(id: $0) != nil }
        guard filtered != cityIDs else { return }
        cityIDs = filtered
        persist()
    }

    /// Hour offset the palette screen's ←/→ scrubbing applies to every row; preview-only state.
    @Published private(set) var previewOffsetHours = 0

    func adjustPreview(byHours delta: Int) {
        previewOffsetHours += delta
    }

    func start() {
        guard clockTask == nil else { return }
        // Every open starts at the real present; the scrub offset is a per-visit preview.
        previewOffsetHours = 0
        now = nowProvider()
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, let self else { return }
                now = nowProvider()
            }
        }
    }

    func stop() {
        clockTask?.cancel()
        clockTask = nil
    }

    func result(
        for cityID: String, calendar: Calendar = .current, locale: Locale = .current
    ) -> WorldClockResult? {
        guard let city = WorldClockEngine.city(id: cityID) else { return nil }
        return WorldClockEngine.result(
            for: city, now: now.addingTimeInterval(TimeInterval(previewOffsetHours) * 3_600),
            calendar: calendar, locale: locale,
            localTimeZone: .autoupdatingCurrent)
    }

    private func persist() {
        defaults.set(cityIDs, forKey: Self.citiesKey)
    }
}
