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

    /// The system's own tz-database country table, read once — the store may touch the filesystem, the pure engine may not.
    private nonisolated static let zoneTable =
        (try? String(contentsOfFile: "/usr/share/zoneinfo/zone.tab", encoding: .utf8)) ?? ""
    private nonisolated static let zoneCountries = WorldClockEngine.countryCodes(fromZoneTab: zoneTable)
    private nonisolated static let zoneCoordinates = WorldClockMapGeometry.coordinates(fromZoneTab: zoneTable)

    func coordinate(for city: WorldClockCity) -> WorldClockCoordinate? {
        WorldClockMapGeometry.coordinate(for: city, zones: Self.zoneCoordinates)
    }

    func mapInstant(for query: String) -> Date {
        if case .conversion(let conversion) = screenIntent(for: query) { return conversion.instant }
        return now.addingTimeInterval(TimeInterval(previewOffsetMinutes) * 60)
    }

    /// The row's flag: the zone's country as emoji, or nil for zones the table doesn't place.
    nonisolated func flag(forTimeZoneIdentifier identifier: String) -> String? {
        Self.zoneCountries[identifier].flatMap(WorldClockEngine.flagEmoji(countryCode:))
    }

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

    @Published private(set) var previewOffsetMinutes = 0
    @Published private var conversionPreviewMinutes = 0
    private var conversionPreviewQuery = ""
    private var isDragging = false

    var previewLabel: String {
        let minutes = abs(previewOffsetMinutes)
        let duration = minutes < 60 ? "\(minutes) min"
            : minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
        return previewOffsetMinutes == 0 ? "Cities" : "Cities · \(previewOffsetMinutes < 0 ? "−" : "+")\(duration)"
    }

    func adjustPreview(byHours delta: Int) {
        previewOffsetMinutes += delta * 60
    }

    func beginMapDrag(query: String) -> Int {
        isDragging = true
        if WorldClockEngine.parseConversion(query) != nil {
            return conversionPreviewQuery == query ? conversionPreviewMinutes : 0
        }
        return previewOffsetMinutes
    }

    func dragMap(to minutes: Int, query: String) {
        if WorldClockEngine.parseConversion(query) != nil {
            guard conversionPreviewQuery != query || conversionPreviewMinutes != minutes else { return }
            conversionPreviewQuery = query
            conversionPreviewMinutes = minutes
        } else if previewOffsetMinutes != minutes {
            previewOffsetMinutes = minutes
        }
    }

    func endMapDrag() { isDragging = false }

    func start() {
        guard clockTask == nil else { return }
        // Every open starts at the real present; the scrub offset is a per-visit preview.
        previewOffsetMinutes = 0
        conversionPreviewQuery = ""
        conversionPreviewMinutes = 0
        isDragging = false
        now = nowProvider()
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, let self else { return }
                if !isDragging { now = nowProvider() }
            }
        }
    }

    func stop() {
        clockTask?.cancel()
        clockTask = nil
        isDragging = false
    }

    func result(
        for cityID: String, calendar: Calendar = .current, locale: Locale = .current
    ) -> WorldClockResult? {
        guard let city = WorldClockEngine.city(id: cityID) else { return nil }
        return WorldClockEngine.result(
            for: city, now: now.addingTimeInterval(TimeInterval(previewOffsetMinutes) * 60),
            calendar: calendar, locale: locale,
            localTimeZone: .autoupdatingCurrent)
    }

    // A conversion starts at its typed instant; dragging offsets only that exact query.
    func screenIntent(
        for query: String, calendar: Calendar = .current, locale: Locale = .current
    ) -> WorldClockScreenIntent {
        WorldClockEngine.screenIntent(
            for: query, cities: cities, now: now, calendar: calendar, locale: locale,
            localTimeZone: .autoupdatingCurrent,
            previewOffsetMinutes: conversionPreviewQuery == query ? conversionPreviewMinutes : 0)
    }

    private func persist() {
        defaults.set(cityIDs, forKey: Self.citiesKey)
    }
}
