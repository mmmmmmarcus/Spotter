import Foundation

enum ScheduleViewMode: String, CaseIterable, Sendable {
    case week, month
    var title: String { rawValue.capitalized }
    var component: Calendar.Component {
        switch self {
        case .week: .weekOfYear
        case .month: .month
        }
    }
}

struct ScheduleTimeBlock: Identifiable, Equatable, Sendable {
    let id: String
    let startMinute: Double
    let endMinute: Double
    var column = 0
    var columnCount = 1
}

enum ScheduleDirection: Sendable {
    case up, down, left, right
}

struct ScheduleEventPosition: Identifiable, Sendable {
    let eventID: String
    let day: Date
    let startMinute: Double
    let isAllDay: Bool

    var id: String { Self.id(eventID: eventID, day: day) }

    static func id(eventID: String, day: Date) -> String {
        eventID + "@" + String(day.timeIntervalSinceReferenceDate)
    }
}

enum ScheduleNavigation {
    static func ordered(_ items: [ScheduleEventPosition]) -> [ScheduleEventPosition] {
        items.sorted {
            if $0.isAllDay != $1.isAllDay { return $0.isAllDay }
            if $0.day != $1.day { return $0.day < $1.day }
            if $0.startMinute != $1.startMinute { return $0.startMinute < $1.startMinute }
            return $0.eventID < $1.eventID
        }
    }

    static func neighbor(
        in items: [ScheduleEventPosition], selectedID: String?, direction: ScheduleDirection
    ) -> String? {
        guard let current = items.first(where: { $0.id == selectedID }) else {
            return ordered(items).first?.id
        }
        switch direction {
        case .up, .down:
            let column = ordered(items.filter { $0.day == current.day })
            guard let index = column.firstIndex(where: { $0.id == current.id }) else { return current.id }
            let next = index + (direction == .up ? -1 : 1)
            return column.indices.contains(next) ? column[next].id : current.id
        case .left, .right:
            let candidates = items.filter { direction == .left ? $0.day < current.day : $0.day > current.day }
            let day = direction == .left ? candidates.map(\.day).max() : candidates.map(\.day).min()
            guard let day else { return current.id }
            return candidates.filter { $0.day == day }.min {
                let leftLane = $0.isAllDay == current.isAllDay
                let rightLane = $1.isAllDay == current.isAllDay
                if leftLane != rightLane { return leftLane }
                let leftDistance = abs($0.startMinute - current.startMinute)
                let rightDistance = abs($1.startMinute - current.startMinute)
                if leftDistance != rightDistance { return leftDistance < rightDistance }
                if $0.startMinute != $1.startMinute { return $0.startMinute < $1.startMinute }
                return $0.eventID < $1.eventID
            }?.id
        }
    }

    static func monthNeighbor(from index: Int, direction: ScheduleDirection, count: Int) -> Int? {
        guard count > 0 else { return nil }
        guard (0..<count).contains(index) else { return 0 }
        let step: Int
        switch direction {
        case .up: step = -7
        case .down: step = 7
        case .left: step = -1
        case .right: step = 1
        }
        let next = index + step
        return (0..<count).contains(next) ? next : index
    }
}

enum ScheduleLayout {
    static func initialScrollMinute(
        days: [Date], events: [(start: Date, end: Date, isAllDay: Bool)],
        now: Date, calendar: Calendar
    ) -> Double {
        let containsToday = days.contains { calendar.isDate($0, inSameDayAs: now) }
        let hasCurrentEvent = events.contains { !$0.isAllDay && $0.start <= now && now < $0.end }
        guard containsToday, hasCurrentEvent else { return 600 }
        return elapsedMinutes(on: now, now: now, calendar: calendar)
    }

    static func days(containing date: Date, mode: ScheduleViewMode, calendar: Calendar) -> [Date] {
        guard let period = calendar.dateInterval(of: mode.component, for: date) else { return [] }
        let start = mode == .month
            ? calendar.dateInterval(of: .weekOfYear, for: period.start)?.start ?? period.start
            : period.start
        let count = mode == .month ? 42 : 7
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    static func moved(_ date: Date, mode: ScheduleViewMode, by step: Int, calendar: Calendar) -> Date {
        let anchor = calendar.dateInterval(of: mode.component, for: date)?.start ?? date
        return calendar.date(byAdding: mode.component, value: step, to: anchor) ?? date
    }

    static func elapsedMinutes(on day: Date, now: Date, calendar: Calendar) -> Double {
        let start = calendar.startOfDay(for: day)
        let today = calendar.startOfDay(for: now)
        if start < today { return 1440 }
        if start > today { return 0 }
        let parts = calendar.dateComponents([.hour, .minute, .second], from: now)
        return Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0)) + Double(parts.second ?? 0) / 60
    }

    static func overlaps(start: Date, end: Date, day: Date, calendar: Calendar) -> Bool {
        guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return false }
        return start < next && max(end, start.addingTimeInterval(1)) > day
    }

    static func block(id: String, start: Date, end: Date, day: Date,
                      calendar: Calendar) -> ScheduleTimeBlock? {
        guard overlaps(start: start, end: end, day: day, calendar: calendar),
              let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
        func minute(_ date: Date) -> Double {
            let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
            return Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0)) + Double(parts.second ?? 0) / 60
        }
        let first = start <= day ? 0 : minute(start)
        let last = end >= next ? 1440 : minute(end)
        return ScheduleTimeBlock(id: id, startMinute: first,
                                 endMinute: min(1440, max(last, first + 30)))
    }

    static func columns(_ blocks: [ScheduleTimeBlock]) -> [ScheduleTimeBlock] {
        let sorted = blocks.sorted {
            if $0.startMinute != $1.startMinute { return $0.startMinute < $1.startMinute }
            if $0.endMinute != $1.endMinute { return $0.endMinute > $1.endMinute }
            return $0.id < $1.id
        }
        var result: [ScheduleTimeBlock] = []
        var group: [ScheduleTimeBlock] = []
        var ends: [Double] = []
        func flush() {
            result += group.map { block in
                var block = block
                block.columnCount = ends.count
                return block
            }
            group = []
            ends = []
        }
        for var block in sorted {
            if !group.isEmpty, block.startMinute >= (ends.max() ?? 0) { flush() }
            let column = ends.firstIndex(where: { $0 <= block.startMinute }) ?? ends.count
            if column == ends.count { ends.append(block.endMinute) }
            else { ends[column] = block.endMinute }
            block.column = column
            group.append(block)
        }
        flush()
        return result
    }
}
