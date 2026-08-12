import Combine
import EventKit
import Foundation

enum DashboardCalendarAccess: Equatable, Sendable {
    case notDetermined
    case denied
    case restricted
    case writeOnly
    case fullAccess

    var canRead: Bool { self == .fullAccess }
}

@MainActor
final class DashboardWidgetsStore: ObservableObject {
    private enum Keys {
        static let enabledWidgets = "dashboard-widgets.enabled-widgets"
        static let calendarSource = "dashboard-widgets.calendar-source"
        static let includesAllDayEvents = "dashboard-widgets.includes-all-day-events"
        static let clockTimeZone = "dashboard-widgets.clock-time-zone"
    }

    @Published private(set) var preferences: DashboardWidgetPreferences
    @Published private(set) var calendarAccess: DashboardCalendarAccess
    @Published private(set) var calendarAccounts: [DashboardCalendarAccount] = []
    @Published private(set) var nextEvent: DashboardEvent?
    @Published private(set) var codexUsage: DashboardUsageSnapshot?
    @Published private(set) var claudeUsage: DashboardUsageSnapshot?
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var isRequestingCalendarAccess = false

    private let defaults: UserDefaults
    private let eventStore: EKEventStore
    private var refreshTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard, eventStore: EKEventStore = EKEventStore()) {
        self.defaults = defaults
        self.eventStore = eventStore
        calendarAccess = Self.currentCalendarAccess()
        preferences = DashboardWidgetPreferences(
            enabledWidgets: DashboardWidgetsEngine.widgetKinds(
                from: defaults.stringArray(forKey: Keys.enabledWidgets)),
            calendarSourceIdentifier: defaults.string(forKey: Keys.calendarSource)?.nilIfEmpty,
            includesAllDayEvents: defaults.object(forKey: Keys.includesAllDayEvents) == nil
                || defaults.bool(forKey: Keys.includesAllDayEvents),
            clockTimeZoneIdentifier: defaults.string(forKey: Keys.clockTimeZone)?.nilIfEmpty)
    }

    var hasEnabledWidgets: Bool { !preferences.enabledWidgets.isEmpty }

    var clockTimeZone: TimeZone {
        DashboardWidgetsEngine.resolvedTimeZone(
            identifier: preferences.clockTimeZoneIdentifier, fallback: .autoupdatingCurrent)
    }

    func isWidgetEnabled(_ widget: DashboardWidgetKind) -> Bool {
        preferences.enabledWidgets.contains(widget)
    }

    func setWidgetEnabled(_ widget: DashboardWidgetKind, enabled: Bool) {
        var updated = preferences
        if enabled {
            updated.enabledWidgets.insert(widget)
        } else {
            updated.enabledWidgets.remove(widget)
        }
        updatePreferences(updated)
    }

    func setCalendarSourceIdentifier(_ identifier: String?) {
        var updated = preferences
        updated.calendarSourceIdentifier = identifier?.nilIfEmpty
        updatePreferences(updated)
    }

    func setIncludesAllDayEvents(_ included: Bool) {
        var updated = preferences
        updated.includesAllDayEvents = included
        updatePreferences(updated)
    }

    func setClockTimeZoneIdentifier(_ identifier: String?) {
        var updated = preferences
        updated.clockTimeZoneIdentifier = TimeZone(identifier: identifier ?? "") == nil
            ? nil : identifier
        updatePreferences(updated)
    }

    @discardableResult
    func applyPreferences(
        enabledWidgetRawValues: [String]?, calendarSourceIdentifier: String?,
        includesAllDayEvents: Bool?, clockTimeZoneIdentifier: String?
    ) -> Int {
        var updated = preferences
        var count = 0
        if let enabledWidgetRawValues {
            updated.enabledWidgets = DashboardWidgetsEngine.widgetKinds(from: enabledWidgetRawValues)
            count += 1
        }
        if let calendarSourceIdentifier {
            updated.calendarSourceIdentifier = calendarSourceIdentifier.nilIfEmpty
            count += 1
        }
        if let includesAllDayEvents {
            updated.includesAllDayEvents = includesAllDayEvents
            count += 1
        }
        if let clockTimeZoneIdentifier {
            updated.clockTimeZoneIdentifier = TimeZone(identifier: clockTimeZoneIdentifier) == nil
                ? nil : clockTimeZoneIdentifier
            count += 1
        }
        updatePreferences(updated)
        return count
    }

    func start() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    break
                }
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refresh() async {
        refreshCalendar()
        let wantsCodex = isWidgetEnabled(.codex)
        let wantsClaude = isWidgetEnabled(.claudeCode)
        guard wantsCodex || wantsClaude else {
            codexUsage = nil
            claudeUsage = nil
            lastRefresh = Date()
            return
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let usage = await Task.detached(priority: .utility) {
            DashboardUsageReader.load(homeDirectory: home)
        }.value
        guard !Task.isCancelled else { return }
        codexUsage = wantsCodex ? usage.codex : nil
        claudeUsage = wantsClaude ? usage.claude : nil
        lastRefresh = Date()
    }

    func requestCalendarAccess() {
        guard !isRequestingCalendarAccess,
            calendarAccess == .notDetermined || calendarAccess == .writeOnly
        else { return }
        isRequestingCalendarAccess = true
        Task { [weak self] in
            guard let self else { return }
            defer { isRequestingCalendarAccess = false }
            do {
                _ = try await eventStore.requestFullAccessToEvents()
            } catch {
                AppLog.error(
                    "DashboardWidgets",
                    "Calendar access request failed: \(error.localizedDescription)")
            }
            refreshCalendarAuthorization()
        }
    }

    func refreshCalendarAuthorization() {
        let current = Self.currentCalendarAccess()
        guard current != calendarAccess else { return }
        calendarAccess = current
        refreshCalendar()
    }

    private func refreshCalendar(now: Date = Date(), calendar: Calendar = .current) {
        calendarAccess = Self.currentCalendarAccess()
        guard calendarAccess.canRead else {
            calendarAccounts = []
            nextEvent = nil
            return
        }
        let calendars = eventStore.calendars(for: .event)
        calendarAccounts = Self.calendarAccounts(from: calendars)
        guard isWidgetEnabled(.nextEvent),
            let horizon = calendar.date(byAdding: .year, value: 1, to: now)
        else {
            nextEvent = nil
            return
        }
        let effectiveSourceIdentifier = DashboardWidgetsEngine.effectiveCalendarSourceIdentifier(
            selected: preferences.calendarSourceIdentifier,
            availableIdentifiers: Set(calendarAccounts.map(\DashboardCalendarAccount.id)))
        let selectedCalendars = effectiveSourceIdentifier.map { identifier in
            calendars.filter { $0.source?.sourceIdentifier == identifier }
        }
        let predicateCalendars = selectedCalendars?.isEmpty == false ? selectedCalendars : nil
        let predicate = eventStore.predicateForEvents(
            withStart: now, end: horizon, calendars: predicateCalendars)
        let events = eventStore.events(matching: predicate)
            .filter {
                $0.status != .canceled && $0.endDate > now
                    && DashboardWidgetsEngine.shouldIncludeCalendarEvent(
                        isAllDay: $0.isAllDay,
                        sourceIdentifier: $0.calendar.source?.sourceIdentifier ?? "",
                        selectedSourceIdentifier: effectiveSourceIdentifier,
                        includesAllDayEvents: preferences.includesAllDayEvents)
            }
        guard let event = events
            .filter({ $0.startDate < horizon })
            .min(by: { $0.startDate < $1.startDate })
        else {
            nextEvent = nil
            return
        }
        nextEvent = DashboardEvent(
            id: event.eventIdentifier ?? UUID().uuidString,
            title: event.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? "Untitled event",
            startDate: event.startDate, endDate: event.endDate, isAllDay: event.isAllDay,
            calendarTitle: event.calendar.title,
            location: event.location?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty)
    }

    private static func currentCalendarAccess() -> DashboardCalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .restricted: return .restricted
        case .writeOnly: return .writeOnly
        case .fullAccess, .authorized: return .fullAccess
        @unknown default: return .restricted
        }
    }

    private static func calendarAccounts(from calendars: [EKCalendar]) -> [DashboardCalendarAccount] {
        var accounts: [String: DashboardCalendarAccount] = [:]
        for calendar in calendars {
            guard let source = calendar.source else { continue }
            guard !source.sourceIdentifier.isEmpty else { continue }
            accounts[source.sourceIdentifier] = DashboardCalendarAccount(
                id: source.sourceIdentifier, title: source.title)
        }
        return accounts.values.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private func updatePreferences(_ updated: DashboardWidgetPreferences) {
        guard updated != preferences else { return }
        preferences = updated
        defaults.set(
            updated.enabledWidgets.map(\DashboardWidgetKind.rawValue).sorted(),
            forKey: Keys.enabledWidgets)
        defaults.set(updated.calendarSourceIdentifier ?? "", forKey: Keys.calendarSource)
        defaults.set(updated.includesAllDayEvents, forKey: Keys.includesAllDayEvents)
        defaults.set(updated.clockTimeZoneIdentifier ?? "", forKey: Keys.clockTimeZone)
        if !isWidgetEnabled(.nextEvent) { nextEvent = nil }
        if !isWidgetEnabled(.codex) { codexUsage = nil }
        if !isWidgetEnabled(.claudeCode) { claudeUsage = nil }
        Task { [weak self] in await self?.refresh() }
    }
}

private struct DashboardUsageReader: Sendable {
    let codex: DashboardUsageSnapshot?
    let claude: DashboardUsageSnapshot?

    static func load(homeDirectory: URL) -> DashboardUsageReader {
        let support = homeDirectory.appending(path: "Library/Application Support")
        let codexBarSupport = support.appending(path: "CodexBar")
        let codexBarHistory = support.appending(path: "com.steipete.codexbar/history")
        let snapshotCandidates = [
            homeDirectory.appending(path: "Library/Group Containers/Y5PE65HELJ.com.steipete.codexbar/widget-snapshot.json"),
            homeDirectory.appending(path: "Library/Group Containers/group.com.steipete.codexbar/widget-snapshot.json"),
            codexBarSupport.appending(path: "widget-snapshot.json"),
        ]
        let snapshotData = snapshotCandidates.compactMap { try? Data(contentsOf: $0) }
            .max(by: { lhs, rhs in
                (DashboardWidgetsEngine.codexBarSnapshotUsage(from: lhs, provider: "codex")?.updatedAt ?? .distantPast)
                    < (DashboardWidgetsEngine.codexBarSnapshotUsage(from: rhs, provider: "codex")?.updatedAt ?? .distantPast)
            })
        let codexHistory = try? Data(contentsOf: codexBarHistory.appending(path: "codex.json"))
        let claudeHistory = try? Data(contentsOf: codexBarHistory.appending(path: "claude.json"))
        let codexSession = newestJSONL(
            under: [homeDirectory.appending(path: ".codex/sessions"), homeDirectory.appending(path: ".codex/archived_sessions")]
        ).flatMap { tail($0) }

        let codex = DashboardWidgetsEngine.preferredUsage([
            codexSession.flatMap(DashboardWidgetsEngine.codexSessionUsage),
            snapshotData.flatMap { DashboardWidgetsEngine.codexBarSnapshotUsage(from: $0, provider: "codex") },
            codexHistory.flatMap { DashboardWidgetsEngine.codexBarHistoryUsage(from: $0, provider: "codex") },
        ])
        let claude = DashboardWidgetsEngine.preferredUsage([
            snapshotData.flatMap { DashboardWidgetsEngine.codexBarSnapshotUsage(from: $0, provider: "claude") },
            claudeHistory.flatMap { DashboardWidgetsEngine.codexBarHistoryUsage(from: $0, provider: "claude") },
        ])
        return DashboardUsageReader(codex: codex, claude: claude)
    }

    private static func newestJSONL(under roots: [URL]) -> URL? {
        var newest: (url: URL, date: Date)?
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey]
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants])
            else { continue }
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                guard let values = try? url.resourceValues(forKeys: keys),
                    values.isRegularFile == true,
                    let date = values.contentModificationDate
                else { continue }
                if newest == nil || date > newest!.date { newest = (url, date) }
            }
        }
        return newest?.url
    }

    private static func tail(_ url: URL, maximumBytes: UInt64 = 2_000_000) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return nil }
        let offset = end > maximumBytes ? end - maximumBytes : 0
        try? handle.seek(toOffset: offset)
        return try? handle.readToEnd()
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
