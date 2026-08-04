import Foundation

/// Mole's command surface plus the parsers for the two commands that emit JSON.
/// Foundation-only and pure so `Tools/mole-test.swift` compiles the real logic; process spawning
/// and Terminal hand-off live in `MoleRunner`.
enum MoleCommand: String, CaseIterable, Sendable {
    case menu
    case clean
    case uninstall
    case optimize
    case analyze
    case status
    case history
    case purge
    case installer

    var title: String {
        switch self {
        case .menu: "Mole Menu"
        case .clean: "Mole Clean"
        case .uninstall: "Mole Uninstall App"
        case .optimize: "Mole Optimize"
        case .analyze: "Mole Analyze Disk"
        case .status: "Mole System Status"
        case .history: "Mole Cleanup History"
        case .purge: "Mole Purge Build Artifacts"
        case .installer: "Mole Remove Installers"
        }
    }

    var summary: String {
        switch self {
        case .menu: "Open Mole's main menu"
        case .clean: "Free up disk space"
        case .uninstall: "Remove an app completely"
        case .optimize: "Refresh caches and services"
        case .analyze: "Explore disk usage"
        case .status: "Monitor system health"
        case .history: "Review cleanup activity"
        case .purge: "Remove old project artifacts"
        case .installer: "Find and remove installer files"
        }
    }

    var systemImage: String {
        switch self {
        case .menu: "circle.grid.2x2"
        case .clean: "sparkles"
        case .uninstall: "trash"
        case .optimize: "wand.and.stars"
        case .analyze: "chart.pie"
        case .status: "waveform.path.ecg"
        case .history: "clock.arrow.circlepath"
        case .purge: "hammer"
        case .installer: "shippingbox"
        }
    }

    /// The two read-only commands emit JSON on a non-TTY, so Spotter renders them itself. Everything else is an interactive TUI that needs a real terminal — and several delete files, which is not something to run blind from a launcher.
    var rendersInPalette: Bool {
        self == .status || self == .history
    }

    var argument: String { rawValue }
    var commandID: String { "command:mole:" + rawValue }
}

/// The subset of `mole status` Spotter surfaces, already formatted for display.
struct MoleStatus: Equatable, Sendable {
    struct Row: Equatable, Sendable {
        let title: String
        let detail: String
        let value: String
    }

    let healthScore: Int
    let healthMessage: String
    let rows: [Row]
}

/// One `mole history --json` session.
struct MoleHistoryEntry: Equatable, Sendable {
    let command: String
    let startedAt: String
    let items: Int
    let size: String
    let failedTasks: Int
}

enum MoleParser {
    private struct StatusPayload: Decodable {
        struct Hardware: Decodable {
            let model: String?
            let cpu_model: String?
            let total_ram: String?
            let os_version: String?
        }
        struct CPU: Decodable {
            let usage: Double?
            let core_count: Int?
        }
        struct Memory: Decodable {
            let used: Int64?
            let total: Int64?
            let used_percent: Double?
        }
        struct Disk: Decodable {
            let mount: String?
            let used: Int64?
            let total: Int64?
            let used_percent: Double?
        }
        let host: String?
        let uptime: String?
        let procs: Int?
        let health_score: Int?
        let health_score_msg: String?
        let hardware: Hardware?
        let cpu: CPU?
        let memory: Memory?
        let disks: [Disk]?
        let trash_size: Int64?
    }

    private struct HistoryPayload: Decodable {
        struct Session: Decodable {
            let command: String?
            let started_at: String?
            let items: Int?
            let size: String?
            let failed_tasks: Int?
        }
        let sessions: [Session]?
    }

    static func parseStatus(_ data: Data) -> MoleStatus? {
        guard let p = try? JSONDecoder().decode(StatusPayload.self, from: data) else { return nil }
        var rows: [MoleStatus.Row] = []

        if let cpu = p.cpu, let usage = cpu.usage {
            let cores = cpu.core_count.map { " · \($0) cores" } ?? ""
            rows.append(
                .init(
                    title: "CPU", detail: (p.hardware?.cpu_model ?? "Processor") + cores,
                    value: percent(usage)))
        }
        if let memory = p.memory, let used = memory.used, let total = memory.total {
            rows.append(
                .init(
                    title: "Memory",
                    detail: "\(bytes(used)) of \(bytes(total)) used",
                    value: percent(memory.used_percent ?? 0)))
        }
        for disk in p.disks ?? [] {
            guard let used = disk.used, let total = disk.total else { continue }
            let free = max(0, total - used)
            rows.append(
                .init(
                    title: "Disk \(disk.mount ?? "")".trimmingCharacters(in: .whitespaces),
                    detail: "\(bytes(free)) free of \(bytes(total))",
                    value: percent(disk.used_percent ?? 0)))
        }
        if let trash = p.trash_size, trash > 0 {
            rows.append(
                .init(title: "Trash", detail: "Reclaimable by emptying", value: bytes(trash)))
        }
        if let uptime = p.uptime {
            let procs = p.procs.map { "\($0) processes" } ?? ""
            rows.append(.init(title: "Uptime", detail: procs, value: uptime))
        }
        if let hardware = p.hardware, let model = hardware.model {
            let ram = hardware.total_ram.map { " · \($0)" } ?? ""
            rows.append(
                .init(
                    title: model, detail: hardware.os_version ?? "",
                    value: (hardware.cpu_model ?? "") + ram))
        }

        return MoleStatus(
            healthScore: p.health_score ?? 0,
            healthMessage: p.health_score_msg ?? "",
            rows: rows)
    }

    static func parseHistory(_ data: Data) -> [MoleHistoryEntry] {
        guard let p = try? JSONDecoder().decode(HistoryPayload.self, from: data) else { return [] }
        return (p.sessions ?? []).compactMap { s in
            guard let command = s.command else { return nil }
            return MoleHistoryEntry(
                command: command,
                startedAt: s.started_at ?? "",
                items: s.items ?? 0,
                size: s.size ?? "0B",
                failedTasks: s.failed_tasks ?? 0)
        }
    }

    /// Mole prints sizes with its own units; these two keep Spotter's own rows consistent with them.
    static func bytes(_ value: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var size = Double(value)
        var index = 0
        while size >= 1024, index < units.count - 1 {
            size /= 1024
            index += 1
        }
        return index == 0
            ? "\(Int(size)) B" : String(format: "%.1f %@", size, units[index])
    }

    static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", max(0, min(100, value)))
    }
}
