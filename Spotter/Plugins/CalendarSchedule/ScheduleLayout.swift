import Foundation

enum ScheduleViewMode: String, CaseIterable, Sendable {
    case day, week, month
    var title: String { rawValue.capitalized }
    var component: Calendar.Component {
        switch self {
        case .day: .day
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

enum ScheduleLayout {
    static func days(containing date: Date, mode: ScheduleViewMode, calendar: Calendar) -> [Date] {
        guard let period = calendar.dateInterval(of: mode.component, for: date) else { return [] }
        let start = mode == .month
            ? calendar.dateInterval(of: .weekOfYear, for: period.start)?.start ?? period.start
            : period.start
        let count = mode == .month ? 42 : mode == .week ? 7 : 1
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    static func moved(_ date: Date, mode: ScheduleViewMode, by step: Int, calendar: Calendar) -> Date {
        let anchor = calendar.dateInterval(of: mode.component, for: date)?.start ?? date
        return calendar.date(byAdding: mode.component, value: step, to: anchor) ?? date
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
