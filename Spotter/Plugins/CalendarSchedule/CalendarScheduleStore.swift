import Combine
import EventKit
import Foundation

@MainActor
final class CalendarScheduleStore: ObservableObject {
    @Published private(set) var mode: ScheduleViewMode = .week
    @Published private(set) var date = Date()
    @Published private(set) var events: [DashboardEvent] = []
    @Published private(set) var isLoading = false
    @Published var detailID: String?
    @Published var peekID: String?
    @Published private(set) var zoom = 0
    var isNavigatingEvents = false
    private weak var dashboard: DashboardWidgetsStore?
    private var task: Task<Void, Never>?
    private var reader: Task<[DashboardEvent], Never>?
    private var timer: Task<Void, Never>?
    private var generation = UUID()
    private var lastRange: DateInterval?
    private var lastPreferences: DashboardWidgetPreferences?
    var calendar: Calendar { .current }
    var days: [Date] { ScheduleLayout.days(containing: date, mode: mode, calendar: calendar) }

    func open(dashboard: DashboardWidgetsStore) {
        self.dashboard = dashboard
        date = Date()
        detailID = nil
        peekID = nil
        isNavigatingEvents = false
        refresh()
        timer?.cancel()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                self?.refresh()
            }
        }
    }

    func close() {
        generation = UUID()
        task?.cancel()
        reader?.cancel()
        timer?.cancel()
        task = nil
        timer = nil
        events = []
        lastRange = nil
        lastPreferences = nil
        detailID = nil
        peekID = nil
        isNavigatingEvents = false
        isLoading = false
    }

    func setMode(_ mode: ScheduleViewMode) {
        guard mode != self.mode else { return }
        self.mode = mode
        detailID = nil
        peekID = nil
        isNavigatingEvents = false
        refresh()
    }

    func move(_ step: Int) {
        date = ScheduleLayout.moved(date, mode: mode, by: step, calendar: calendar)
        detailID = nil
        peekID = nil
        isNavigatingEvents = false
        refresh()
    }

    func today() { date = Date(); detailID = nil; peekID = nil; refresh() }
    func showWeek(containing day: Date) { date = day; mode = .week; detailID = nil; peekID = nil; refresh() }

    func changeZoom(by step: Int) {
        guard mode == .week, detailID == nil else { return }
        peekID = nil
        zoom = min(ScheduleViewport.zoomRange.upperBound, max(ScheduleViewport.zoomRange.lowerBound, zoom + step))
    }

    func matching(_ query: String) -> [DashboardEvent] {
        events.filter { matches($0, query: query) }
    }

    func matches(_ event: DashboardEvent, query: String) -> Bool {
        CalendarScheduleEngine.matches(query: query, title: event.title,
            calendarTitle: event.calendarTitle, location: event.location)
    }

    func refresh() {
        guard let dashboard, let start = days.first, let last = days.last,
              let end = calendar.date(byAdding: .day, value: 1, to: last) else { return }
        task?.cancel()
        reader?.cancel()
        generation = UUID()
        let request = generation
        let preferences = dashboard.preferences
        let range = DateInterval(start: start, end: end)
        if range != lastRange || preferences != lastPreferences || !dashboard.calendarAccess.canRead {
            events = []
        }
        lastRange = range
        lastPreferences = preferences
        isLoading = dashboard.calendarAccess.canRead
        let reader = Task.detached(priority: .userInitiated) {
            Self.read(start: start, end: end, preferences: preferences)
        }
        self.reader = reader
        task = Task { [weak self] in
            let result = await reader.value
            guard !Task.isCancelled, let self, generation == request else { return }
            events = result
            if let detailID, !result.contains(where: { CalendarSchedulePlugin.rowID(for: $0) == detailID }) {
                self.detailID = nil
                peekID = nil
            }
            if let peekID, CalendarSchedulePlugin.event(store: self, itemID: peekID) == nil {
                self.peekID = nil
            }
            isLoading = false
        }
    }

    nonisolated private static func read(start: Date, end: Date,
                                        preferences: DashboardWidgetPreferences) -> [DashboardEvent] {
        guard !Task.isCancelled, EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        return autoreleasepool {
            let store = EKEventStore()
            let calendars = store.calendars(for: .event)
            let source = DashboardWidgetsEngine.effectiveCalendarSourceIdentifier(
                selected: preferences.calendarSourceIdentifier,
                availableIdentifiers: Set(calendars.compactMap { $0.source?.sourceIdentifier }))
            let selected = source.map { id in calendars.filter { $0.source?.sourceIdentifier == id } }
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: selected)
            let events = store.events(matching: predicate).filter {
                $0.status != .canceled && $0.startDate < end && $0.endDate > start
                    && (preferences.includesAllDayEvents || !$0.isAllDay)
            }.map { event in
                DashboardEvent(
                    id: event.eventIdentifier ?? event.calendarItemIdentifier,
                    title: event.title?.isEmpty == false ? event.title : "Untitled event",
                    startDate: event.startDate, endDate: event.endDate, isAllDay: event.isAllDay,
                    calendarTitle: event.calendar.title, location: event.location ?? event.structuredLocation?.title,
                    urlString: event.url?.absoluteString, notes: event.notes,
                    timeZoneIdentifier: event.timeZone?.identifier, details: CalendarEventMetadata.read(event))
            }.sorted {
                if $0.isAllDay != $1.isAllDay { return $0.isAllDay }
                if $0.startDate != $1.startDate { return $0.startDate < $1.startDate }
                return $0.id < $1.id
            }
            guard !Task.isCancelled, EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
            return events
        }
    }
}
