import Foundation

/// Mole's command surface plus the parsers for every output shape Spotter renders.
/// Foundation-only and pure so `Tools/mole-test.swift` compiles the real logic; process spawning
/// lives in `MoleManager`.
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
        case .menu: "Mole"
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
        case .menu: "Every Mole screen in one list"
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

    /// The screen this command opens — every Mole command renders in the palette.
    var screen: MoleScreen {
        switch self {
        case .menu: .menu
        case .clean: .clean
        case .uninstall: .uninstall
        case .optimize: .optimize
        case .analyze: .analyze
        case .status: .status
        case .history: .history
        case .purge: .purge
        case .installer: .installer
        }
    }

    var argument: String { rawValue }
    var commandID: String { "command:mole:" + rawValue }
}

/// One rendered Mole screen. `menu` is the hub every other screen is reachable from.
enum MoleScreen: String, CaseIterable, Sendable {
    case menu
    case status
    case clean
    case optimize
    case purge
    case uninstall
    case analyze
    case history
    case installer

    var sectionTitle: String {
        switch self {
        case .menu: "Mole"
        case .status: "Mole · System Status"
        case .clean: "Mole · Clean"
        case .optimize: "Mole · Optimize"
        case .purge: "Mole · Purge"
        case .uninstall: "Mole · Uninstall"
        case .analyze: "Mole · Disk"
        case .history: "Mole · Cleanup History"
        case .installer: "Mole · Installer Files"
        }
    }

    var placeholder: String {
        switch self {
        case .menu: "Choose a Mole command…"
        case .uninstall: "Search installed apps…"
        case .analyze: "Filter this folder…"
        case .installer: "Filter installer files…"
        default: "Filter Mole results…"
        }
    }

    /// Arguments for the read-only pass that populates the screen. Nil when nothing is fetched.
    var previewArguments: [String]? {
        switch self {
        case .menu: nil
        case .status: ["status"]
        case .history: ["history", "--json"]
        case .clean: ["clean", "--dry-run"]
        case .optimize: ["optimize", "--dry-run"]
        case .purge: ["purge", "--dry-run"]
        case .uninstall: ["uninstall", "--list"]
        // Analyze targets a directory chosen at runtime, so the manager builds its arguments.
        case .analyze: nil
        // Mole's installer selector is TUI-only, so Spotter scans the same paths itself.
        case .installer: nil
        }
    }
}

/// A state-changing Mole run. Every case deletes something, so `AppCore` confirms before starting one.
enum MoleAction: Equatable, Sendable {
    case clean
    case optimize
    case purge
    case uninstall(name: String, permanent: Bool)

    var arguments: [String] {
        switch self {
        case .clean: ["clean"]
        case .optimize: ["optimize"]
        case .purge: ["purge"]
        case .uninstall(let name, let permanent):
            permanent ? ["uninstall", "--permanent", name] : ["uninstall", name]
        }
    }

    var title: String {
        switch self {
        case .clean: "Clean Now"
        case .optimize: "Optimize Now"
        case .purge: "Purge Now"
        case .uninstall(let name, let permanent):
            permanent ? "Delete \(name) Permanently" : "Uninstall \(name)"
        }
    }

    var confirmation: String {
        switch self {
        case .clean:
            "Mole will delete the caches, logs and temporary files listed here. System caches that need admin rights are skipped."
        case .optimize:
            "Mole will refresh system caches and services and repair safe maintenance issues."
        case .purge:
            "Mole will delete every build artifact directory listed here. They can be rebuilt, but this can't be undone."
        case .uninstall(let name, let permanent):
            permanent
                ? "\(name) and its support files will be deleted immediately, bypassing the Trash. This can't be undone."
                : "\(name) and its support files will be moved to the Trash."
        }
    }

    var isPermanent: Bool {
        switch self {
        case .purge: true
        case .uninstall(_, let permanent): permanent
        case .clean, .optimize: false
        }
    }

    /// The screen to re-read once the run finishes, so the list reflects what is left.
    var screen: MoleScreen {
        switch self {
        case .clean: .clean
        case .optimize: .optimize
        case .purge: .purge
        case .uninstall: .uninstall
        }
    }
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

/// `mole clean` / `mole optimize` output, which is sectioned plain text rather than JSON.
struct MoleReport: Equatable, Sendable {
    struct Item: Equatable, Sendable {
        let section: String
        let title: String
        let detail: String
    }

    let items: [Item]
    /// The closing lines Mole prints about space and counts, kept verbatim.
    let summary: [String]

    var isEmpty: Bool { items.isEmpty && summary.isEmpty }
}

/// One project artifact directory from `mole purge`.
struct MolePurgeEntry: Equatable, Sendable {
    let path: String
    let size: String
}

/// One row of `mole uninstall --list`.
struct MoleApp: Equatable, Sendable {
    let name: String
    let bundleID: String
    /// The exact token `mole uninstall` accepts, which is not always the display name.
    let uninstallName: String
    let path: String
    let size: String
}

/// One installer file found by Spotter's own scan of Mole's installer paths.
struct MoleInstallerEntry: Equatable, Sendable {
    let name: String
    let path: String
    /// The containing folder, home-abbreviated, shown as the row subtitle.
    let folder: String
    let size: Int64
}

/// The pure rules of the installer scan, mirroring `mo installer`: the same folders, the same
/// depth, the same extensions, and the same "a zip counts only if it contains an installer" test.
/// The filesystem walk itself lives in `MoleManager`.
enum MoleInstallerScan {
    static let maxDepth = 2
    static let directExtensions: Set<String> = ["dmg", "pkg", "mpkg", "iso", "xip"]

    /// Mole's `INSTALLER_SCAN_PATHS`, relative to the given home so the harness can test it.
    static func roots(home: String) -> [String] {
        [
            home + "/Downloads",
            home + "/Desktop",
            home + "/Documents",
            home + "/Public",
            home + "/Library/Downloads",
            "/Users/Shared/Downloads",
            home + "/Library/Caches/Homebrew",
            home + "/Library/Mobile Documents/com~apple~CloudDocs/Downloads",
            home + "/Library/Containers/com.apple.mail/Data/Library/Mail Downloads",
            home + "/Library/Application Support/Telegram Desktop",
            home + "/Downloads/Telegram Desktop",
        ]
    }

    static func isDirectInstaller(_ filename: String) -> Bool {
        directExtensions.contains((filename as NSString).pathExtension.lowercased())
    }

    static func isZip(_ filename: String) -> Bool {
        (filename as NSString).pathExtension.lowercased() == "zip"
    }

    /// A zip is an installer when any archived path has an installer component — `Foo.app/` counts,
    /// `notes.txt` doesn't (Mole's `is_installer_zip` awk test).
    static func zipListingSuggestsInstaller(_ entries: [String]) -> Bool {
        entries.contains { entry in
            entry.split(separator: "/").contains { component in
                let lowered = component.lowercased()
                return lowered.hasSuffix(".app") || lowered.hasSuffix(".pkg")
                    || lowered.hasSuffix(".dmg") || lowered.hasSuffix(".xip")
            }
        }
    }
}

/// One entry of an `analyze -json` listing.
struct MoleDiskEntry: Equatable, Sendable {
    let name: String
    let path: String
    let size: Int64
    let isDirectory: Bool
}

struct MoleAnalysis: Equatable, Sendable {
    let path: String
    let entries: [MoleDiskEntry]
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

    private struct AppPayload: Decodable {
        let name: String?
        let bundle_id: String?
        let uninstall_name: String?
        let path: String?
        let size: String?
    }

    private struct AnalysisPayload: Decodable {
        struct Entry: Decodable {
            let name: String?
            let path: String?
            let size: Int64?
            let is_dir: Bool?
        }
        let path: String?
        let entries: [Entry]?
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

    static func parseApps(_ data: Data) -> [MoleApp] {
        guard let payload = try? JSONDecoder().decode([AppPayload].self, from: data) else {
            return []
        }
        return payload.compactMap { app in
            // The uninstall token is what the command actually needs; a row without one is unusable.
            guard let name = app.name, let token = app.uninstall_name, !token.isEmpty else {
                return nil
            }
            return MoleApp(
                name: name,
                bundleID: app.bundle_id ?? "",
                uninstallName: token,
                path: app.path ?? "",
                size: app.size ?? "")
        }
    }

    static func parseAnalysis(_ data: Data) -> MoleAnalysis? {
        guard let payload = try? JSONDecoder().decode(AnalysisPayload.self, from: data),
            let path = payload.path
        else { return nil }
        let entries = (payload.entries ?? []).compactMap { entry -> MoleDiskEntry? in
            guard let name = entry.name, let entryPath = entry.path else { return nil }
            return MoleDiskEntry(
                name: name, path: entryPath, size: entry.size ?? 0,
                isDirectory: entry.is_dir ?? false)
        }
        return MoleAnalysis(path: path, entries: entries)
    }

    /// `mole purge` prints one line per directory: `✓ [DRY RUN] <path>, <size>`.
    /// The path may itself contain commas, so the size is taken from the last one.
    static func parsePurge(_ text: String) -> [MolePurgeEntry] {
        stripANSI(text).split(separator: "\n").compactMap { rawLine in
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("✓") else { return nil }
            line = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[DRY RUN]") {
                line = String(line.dropFirst("[DRY RUN]".count)).trimmingCharacters(in: .whitespaces)
            }
            guard let comma = line.lastIndex(of: ",") else { return nil }
            let path = String(line[..<comma]).trimmingCharacters(in: .whitespaces)
            let size = String(line[line.index(after: comma)...]).trimmingCharacters(in: .whitespaces)
            guard !path.isEmpty, !size.isEmpty else { return nil }
            return MolePurgeEntry(path: path, size: size)
        }
    }

    private static let summaryPrefixes = [
        "Potential space:", "Tracked cleanup:", "Free space:", "Would apply", "Applied",
        "Dry run complete", "Dry Run Complete", "Clean complete", "Skipped while active:",
        "System was already clean", "No additional space freed",
    ]

    /// Item markers Mole uses across `clean` and `optimize`: done, applied, and suggested.
    private static let itemMarkers: Set<Character> = ["→", "✓", "⊙"]

    /// `mole clean` and `mole optimize` print section headers followed by marked item lines.
    /// Anything else — banners, whitelist echoes, file-list hints — is noise the palette skips.
    static func parseReport(_ text: String) -> MoleReport {
        var items: [MoleReport.Item] = []
        var summary: [String] = []
        var section = ""
        for rawLine in stripANSI(text).split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("➤") {
                section = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                continue
            }
            if summaryPrefixes.contains(where: line.hasPrefix) {
                summary.append(line)
                continue
            }
            // Optimize heads some groups with a bare all-caps line instead of the ➤ marker.
            if isUppercaseHeading(line) {
                section = line
                continue
            }
            guard let marker = line.first, itemMarkers.contains(marker) else { continue }
            let body = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
            guard !body.isEmpty, !body.hasPrefix("DRY RUN MODE") else { continue }
            // `·` separates the item from its size/count; a line without one is its own title.
            if let separator = body.range(of: " · ") {
                items.append(
                    MoleReport.Item(
                        section: section,
                        title: String(body[..<separator.lowerBound]),
                        detail: String(body[separator.upperBound...])))
            } else {
                items.append(MoleReport.Item(section: section, title: body, detail: ""))
            }
        }
        return MoleReport(items: items, summary: summary)
    }

    private static func isUppercaseHeading(_ line: String) -> Bool {
        let letters = line.filter(\.isLetter)
        return !letters.isEmpty && letters.allSatisfy(\.isUppercase) && line.count <= 48
    }

    /// Mole colors and repaints its output; the palette needs the plain text underneath.
    static func stripANSI(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var iterator = text.makeIterator()
        var pending: Character?
        while let character = pending ?? iterator.next() {
            pending = nil
            guard character == "\u{1B}" else {
                // Mole redraws lines in place; a carriage return would otherwise glue two rows together.
                result.append(character == "\r" ? "\n" : character)
                continue
            }
            guard let next = iterator.next() else { break }
            guard next == "[" else {
                pending = next
                continue
            }
            // CSI runs through parameter and intermediate bytes, then one final byte that ends it.
            while let terminator = iterator.next() {
                if !(" "..."?" ~= terminator) { break }
            }
        }
        return result
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
