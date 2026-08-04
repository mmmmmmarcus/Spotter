import Foundation

/// Durations offered by "Caffeinate For". Foundation-only and pure so `Tools/coffee-test.swift`
/// compiles the real logic; the process lives in `CoffeeManager`.
enum CoffeeDuration: String, CaseIterable, Sendable {
    case fifteenMinutes
    case thirtyMinutes
    case oneHour
    case twoHours
    case fourHours
    case eightHours

    var seconds: Int {
        switch self {
        case .fifteenMinutes: 15 * 60
        case .thirtyMinutes: 30 * 60
        case .oneHour: 3600
        case .twoHours: 2 * 3600
        case .fourHours: 4 * 3600
        case .eightHours: 8 * 3600
        }
    }

    var title: String {
        switch self {
        case .fifteenMinutes: "15 minutes"
        case .thirtyMinutes: "30 minutes"
        case .oneHour: "1 hour"
        case .twoHours: "2 hours"
        case .fourHours: "4 hours"
        case .eightHours: "8 hours"
        }
    }
}

/// What the Mac is being kept awake for. `caffeinate` needs at least one assertion flag; these map
/// to the three that matter for a laptop on a desk.
struct CoffeeOptions: Equatable, Sendable {
    /// `-d`: keep the display awake too, not just the system.
    var keepsDisplayAwake = true
    /// `-m`: keep the disk from idle-sleeping.
    var keepsDiskAwake = false

    /// `-i` (idle sleep) is always present — without an assertion flag `caffeinate` does nothing at all.
    func arguments(seconds: Int?, pid: Int32?) -> [String] {
        var arguments = ["-i"]
        if keepsDisplayAwake { arguments.append("-d") }
        if keepsDiskAwake { arguments.append("-m") }
        if let seconds { arguments += ["-t", String(seconds)] }
        // -w outlives nothing: caffeinate exits when the watched process does.
        if let pid { arguments += ["-w", String(pid)] }
        return arguments
    }
}

enum CoffeeState: Equatable, Sendable {
    case off
    /// No end — runs until stopped.
    case indefinite
    case until(Date)
    /// Tied to another app's lifetime.
    case whileRunning(appName: String)

    var isOn: Bool { self != .off }

    var summary: String {
        switch self {
        case .off: "Your Mac can sleep normally."
        case .indefinite: "Staying awake until you stop it."
        case .until(let date):
            "Staying awake until " + CoffeeFormatter.clock(date) + "."
        case .whileRunning(let appName): "Staying awake while \(appName) is running."
        }
    }

    var menuTitle: String {
        switch self {
        case .off: "Off"
        case .indefinite: "On"
        case .until(let date): "Until " + CoffeeFormatter.clock(date)
        case .whileRunning(let appName): "While \(appName)"
        }
    }
}

enum CoffeeFormatter {
    /// Locale-driven short time, since this is only ever shown to the user.
    static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// "1h 5m" / "12m" / "40s" — the countdown a status row shows.
    static func remaining(until end: Date, now: Date = Date()) -> String {
        let total = max(0, Int(end.timeIntervalSince(now)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(seconds)s"
    }
}
