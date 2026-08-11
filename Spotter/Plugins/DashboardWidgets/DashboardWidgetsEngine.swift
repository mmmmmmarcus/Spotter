import Foundation

struct DashboardEvent: Equatable, Sendable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarTitle: String
    let location: String?
}

struct DashboardUsageWindow: Equatable, Sendable {
    let name: String
    let usedPercent: Double
    let windowMinutes: Int?
    let resetsAt: Date?
}

enum DashboardUsageSource: String, Equatable, Sendable {
    case codexSession
    case codexBarSnapshot
    case codexBarHistory
}

struct DashboardUsageSnapshot: Equatable, Sendable {
    let provider: String
    let primary: DashboardUsageWindow?
    let secondary: DashboardUsageWindow?
    let updatedAt: Date
    let source: DashboardUsageSource

    func hasCurrentWindow(at now: Date) -> Bool {
        !currentWindows(at: now).isEmpty
    }

    func currentWindows(at now: Date) -> [DashboardUsageWindow] {
        [primary, secondary].compactMap { $0 }.filter { window in
            if let reset = window.resetsAt { return reset > now }
            return now.timeIntervalSince(updatedAt) <= 6 * 60 * 60
        }
    }
}

enum DashboardWidgetsEngine {
    static func codexSessionUsage(from data: Data) -> DashboardUsageSnapshot? {
        let marker = Data("\"rate_limits\"".utf8)
        for line in data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true).reversed() {
            let lineData = Data(line)
            guard lineData.range(of: marker) != nil,
                let root = jsonObject(lineData),
                let payload = root["payload"] as? [String: Any],
                let limits = payload["rate_limits"] as? [String: Any]
            else { continue }
            let updatedAt = date(root["timestamp"]) ?? date(payload["timestamp"]) ?? .distantPast
            let primary = usageWindow(limits["primary"], fallbackName: nil)
            let secondary = usageWindow(limits["secondary"], fallbackName: nil)
            guard primary != nil || secondary != nil else { continue }
            return DashboardUsageSnapshot(
                provider: "codex", primary: primary, secondary: secondary,
                updatedAt: updatedAt, source: .codexSession)
        }
        return nil
    }

    static func codexBarSnapshotUsage(
        from data: Data, provider: String
    ) -> DashboardUsageSnapshot? {
        guard let root = jsonObject(data), let entries = root["entries"] as? [[String: Any]] else {
            return nil
        }
        let candidates = entries.compactMap { entry -> DashboardUsageSnapshot? in
            guard (entry["provider"] as? String)?.hasPrefix(provider) == true else { return nil }
            let primary = usageWindow(entry["primary"], fallbackName: nil)
            let secondary = usageWindow(entry["secondary"], fallbackName: nil)
            guard primary != nil || secondary != nil else { return nil }
            return DashboardUsageSnapshot(
                provider: provider, primary: primary, secondary: secondary,
                updatedAt: date(entry["updatedAt"]) ?? date(root["generatedAt"]) ?? .distantPast,
                source: .codexBarSnapshot)
        }
        return candidates.max(by: { $0.updatedAt < $1.updatedAt })
    }

    static func codexBarHistoryUsage(
        from data: Data, provider: String
    ) -> DashboardUsageSnapshot? {
        guard let root = jsonObject(data) else { return nil }
        let groups: [[String: Any]]
        if provider == "claude" {
            groups = root["unscoped"] as? [[String: Any]] ?? []
        } else if let preferred = root["preferredAccountKey"] as? String,
            let accounts = root["accounts"] as? [String: Any],
            let preferredGroups = accounts[preferred] as? [[String: Any]]
        {
            groups = preferredGroups
        } else if let accounts = root["accounts"] as? [String: Any] {
            groups = accounts.values.flatMap { $0 as? [[String: Any]] ?? [] }
        } else {
            groups = []
        }

        let latest = groups.compactMap { group -> (DashboardUsageWindow, Date)? in
            guard let entries = group["entries"] as? [[String: Any]],
                let entry = entries.max(by: {
                    (date($0["capturedAt"]) ?? .distantPast)
                        < (date($1["capturedAt"]) ?? .distantPast)
                }),
                let percent = number(entry["usedPercent"])
            else { return nil }
            let minutes = int(group["windowMinutes"])
            let name = (group["name"] as? String) ?? windowName(minutes)
            return (
                DashboardUsageWindow(
                    name: displayName(name, minutes: minutes),
                    usedPercent: clamped(percent), windowMinutes: minutes,
                    resetsAt: date(entry["resetsAt"])),
                date(entry["capturedAt"]) ?? .distantPast)
        }
        guard !latest.isEmpty else { return nil }
        let ordered = latest.sorted { lhs, rhs in
            windowPriority(lhs.0) < windowPriority(rhs.0)
        }
        return DashboardUsageSnapshot(
            provider: provider, primary: ordered.first?.0,
            secondary: ordered.dropFirst().first?.0,
            updatedAt: latest.map(\.1).max() ?? .distantPast,
            source: .codexBarHistory)
    }

    static func preferredUsage(_ candidates: [DashboardUsageSnapshot?]) -> DashboardUsageSnapshot? {
        candidates.compactMap { $0 }.max(by: { $0.updatedAt < $1.updatedAt })
    }

    private static func usageWindow(_ value: Any?, fallbackName: String?) -> DashboardUsageWindow? {
        guard let object = value as? [String: Any], let percent = number(object["used_percent"] ?? object["usedPercent"])
        else { return nil }
        let minutes = int(object["window_minutes"] ?? object["windowMinutes"])
        let rawName = fallbackName ?? object["name"] as? String
        return DashboardUsageWindow(
            name: displayName(rawName, minutes: minutes),
            usedPercent: clamped(percent), windowMinutes: minutes,
            resetsAt: date(object["resets_at"] ?? object["resetsAt"]))
    }

    private static func displayName(_ raw: String?, minutes: Int?) -> String {
        switch raw?.lowercased() {
        case "session": return "5h"
        case "weekly": return "7d"
        case "opus": return "Opus 7d"
        case .some(let name) where !name.isEmpty: return name
        default: return windowName(minutes)
        }
    }

    private static func windowName(_ minutes: Int?) -> String {
        switch minutes {
        case 300: return "5h"
        case 1_440: return "24h"
        case 10_080: return "7d"
        case .some(let value) where value >= 60 && value.isMultiple(of: 60):
            return "\(value / 60)h"
        default: return "Usage"
        }
    }

    private static func windowPriority(_ window: DashboardUsageWindow) -> Int {
        if window.name == "5h" { return 0 }
        if window.name == "7d" { return 1 }
        return 2
    }

    private static func clamped(_ value: Double) -> Double { min(max(value, 0), 100) }

    private static func jsonObject(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func int(_ value: Any?) -> Int? {
        number(value).map(Int.init)
    }

    private static func date(_ value: Any?) -> Date? {
        if let number = number(value) {
            let seconds = number > 10_000_000_000 ? number / 1_000 : number
            return Date(timeIntervalSince1970: seconds)
        }
        guard let string = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}
