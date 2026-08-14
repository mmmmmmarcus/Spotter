import Foundation

/// Today's input tallies. Counts only: whatever feeds these never reads a key code, a character or a
/// click location — there is nothing here to reconstruct what was typed from.
struct DashboardInputCounts: Equatable, Sendable {
    var keys: Int
    var clicks: Int

    static let zero = DashboardInputCounts(keys: 0, clicks: 0)
}

/// What the card draws: the day's start (nil until the first sign of activity) and its tallies.
struct DashboardUptimeSnapshot: Equatable, Sendable {
    var sessionStart: Date?
    var counts: DashboardInputCounts

    static let empty = DashboardUptimeSnapshot(sessionStart: nil, counts: .zero)
}

enum DashboardUptimeEngine {
    /// A persisted start belongs to `now` only while it is still the same calendar day. A rollover —
    /// or a clock dragged backwards, which would otherwise report a negative session — drops it, and
    /// the store re-stamps on the day's first sign of activity rather than at midnight, so an
    /// overnight-awake Mac doesn't claim the user was at it since 00:00.
    static func carriedOverSessionStart(
        _ persisted: Date?, now: Date, calendar: Calendar
    ) -> Date? {
        guard let persisted, persisted <= now, calendar.isDate(persisted, inSameDayAs: now) else {
            return nil
        }
        return persisted
    }

    /// Tallies survive a relaunch but not a new day; an absent or stale stamp zeroes them.
    static func carriedOverCounts(
        _ persisted: DashboardInputCounts, countedDay: Date?, now: Date, calendar: Calendar
    ) -> DashboardInputCounts {
        guard let countedDay, calendar.isDate(countedDay, inSameDayAs: now) else { return .zero }
        return persisted
    }

    /// Floored to the minute so the reading never rounds up past the elapsed time.
    static func formattedElapsed(from start: Date, to now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(start) / 60))
        let (hours, remainder) = minutes.quotientAndRemainder(dividingBy: 60)
        return hours == 0 ? "\(remainder)m" : "\(hours)h \(remainder)m"
    }

    /// Grouped by hand rather than through a locale format, so the engine stays pure — its output
    /// can't shift with the Mac's region — and the harness can assert one stable string.
    static func formattedCount(_ count: Int) -> String {
        var grouped = ""
        for (offset, digit) in String(max(0, count)).reversed().enumerated() {
            if offset > 0, offset.isMultiple(of: 3) { grouped.append(",") }
            grouped.append(digit)
        }
        return String(grouped.reversed())
    }
}
