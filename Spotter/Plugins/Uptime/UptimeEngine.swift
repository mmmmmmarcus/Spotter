import Foundation

/// Today's input tallies. Counts only: whatever feeds these never reads a key code, a character or a
/// click location — there is nothing here to reconstruct what was typed from.
struct UptimeInputCounts: Equatable, Sendable {
    var keys: Int
    var clicks: Int

    static let zero = UptimeInputCounts(keys: 0, clicks: 0)
}

/// What the card draws: the day's start (nil until the first sign of activity) and its tallies.
struct UptimeSnapshot: Equatable, Sendable {
    var sessionStart: Date?
    var counts: UptimeInputCounts

    static let empty = UptimeSnapshot(sessionStart: nil, counts: .zero)
}

enum UptimeEngine {
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
        _ persisted: UptimeInputCounts, countedDay: Date?, now: Date, calendar: Calendar
    ) -> UptimeInputCounts {
        guard let countedDay, calendar.isDate(countedDay, inSameDayAs: now) else { return .zero }
        return persisted
    }

    /// Floored to the minute so the reading never rounds up past the elapsed time.
    static func formattedElapsed(from start: Date, to now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(start) / 60))
        let (hours, remainder) = minutes.quotientAndRemainder(dividingBy: 60)
        return hours == 0 ? "\(remainder)m" : "\(hours)h \(remainder)m"
    }

    /// The card spells its tallies out rather than leaning on a glyph, so each line says what it
    /// counts. Both pluralize, since a day's first keystroke would otherwise read "1 keys pressed".
    static func keysLabel(_ count: Int) -> String {
        "\(formattedCount(count)) \(count == 1 ? "key" : "keys") pressed"
    }

    static func clicksLabel(_ count: Int) -> String {
        "\(formattedCount(count)) mouse \(count == 1 ? "click" : "clicks")"
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
