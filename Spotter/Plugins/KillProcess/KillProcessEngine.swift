import Foundation

enum ProcessSort: String, CaseIterable, Sendable {
    case cpu
    case memory

    var title: String { self == .cpu ? "CPU Usage" : "Memory Usage" }
}

struct RunningProcessInfo: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case app
        case binary
        case aggregatedApp
    }

    let id: Int32
    let parentID: Int32
    let cpu: Double
    let memoryKB: Int64
    let executablePath: String
    let processName: String
    let appName: String?
    let kind: Kind
    var childProcessIDs: [Int32] = []

    var appBundlePath: String? {
        guard let range = executablePath.range(of: ".app/") else { return nil }
        return String(executablePath[..<executablePath.index(before: range.upperBound)])
    }

    var canRestart: Bool {
        appBundlePath != nil || executablePath.hasPrefix("/")
    }
}

enum KillProcessEngine {
    static func applicationArgument(_ query: String) -> String? {
        guard query.count <= 256 else { return nil }
        let parts = query.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard parts.count == 2, parts[0].lowercased() == "kill" else { return nil }
        let name = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    static func applicationTarget(
        in processes: [RunningProcessInfo], argument: String, excludingPID: Int32
    ) -> RunningProcessInfo? {
        let needle = argument.lowercased()
        guard !needle.isEmpty else { return nil }
        func name(_ process: RunningProcessInfo) -> String { process.appName ?? process.processName }
        func rank(_ process: RunningProcessInfo) -> Int {
            let value = name(process).lowercased()
            return value == needle ? 0 : value.hasPrefix(needle) ? 1 : 2
        }
        return processes.filter {
            $0.id > 1 && $0.id != excludingPID && $0.kind == .app
                && name($0).localizedCaseInsensitiveContains(argument)
        }.sorted {
            if rank($0) != rank($1) { return rank($0) < rank($1) }
            let order = name($0).localizedStandardCompare(name($1))
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }.first
    }

    static func parse(
        _ output: String, excluding excludedPID: Int32? = nil,
        excludingBundlePath: String? = nil
    ) -> [RunningProcessInfo] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(maxSplits: 4, whereSeparator: \.isWhitespace)
            guard fields.count == 5,
                let pid = Int32(fields[0]), pid > 1, pid != excludedPID,
                let parent = Int32(fields[1]),
                let cpu = Double(fields[2].replacingOccurrences(of: ",", with: ".")),
                let memory = Int64(fields[3])
            else { return nil }

            let path = String(fields[4])
            if let excludingBundlePath,
                path == excludingBundlePath || path.hasPrefix(excludingBundlePath + "/")
            { return nil }
            let name = URL(fileURLWithPath: path).lastPathComponent
            guard !name.isEmpty else { return nil }
            let bundle = outerAppBundle(in: path)
            return RunningProcessInfo(
                id: pid,
                parentID: parent,
                cpu: cpu,
                memoryKB: memory,
                executablePath: path,
                processName: name,
                appName: bundle.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent },
                kind: bundle == nil ? .binary : .app)
        }
    }

    static func groupApplications(_ processes: [RunningProcessInfo]) -> [RunningProcessInfo] {
        let grouped = Dictionary(grouping: processes) { $0.appBundlePath }
        var result = grouped[nil] ?? []
        for (bundle, members) in grouped where bundle != nil {
            guard members.count > 1 else {
                result.append(contentsOf: members)
                continue
            }
            let appName = bundle.map {
                URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent
            } ?? members[0].processName
            let ids = Set(members.map(\.id))
            let main = members.first { $0.processName == appName }
                ?? members.first { !ids.contains($0.parentID) }
                ?? members[0]
            result.append(RunningProcessInfo(
                id: main.id,
                parentID: main.parentID,
                cpu: members.reduce(0) { $0 + $1.cpu },
                memoryKB: members.reduce(0) { $0 + $1.memoryKB },
                executablePath: main.executablePath,
                processName: main.processName,
                appName: appName,
                kind: .aggregatedApp,
                childProcessIDs: members.filter { $0.id != main.id }.map(\.id)))
        }
        return result
    }

    static func visible(
        _ processes: [RunningProcessInfo], query: String, sort: ProcessSort,
        groupingApplications: Bool, searchPaths: Bool, searchPIDs: Bool,
        prioritizeApps: Bool
    ) -> [RunningProcessInfo] {
        let source = groupingApplications ? groupApplications(processes) : processes
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var filtered = needle.isEmpty ? source : source.filter { process in
            process.processName.localizedCaseInsensitiveContains(needle)
                || process.appName?.localizedCaseInsensitiveContains(needle) == true
                || (searchPaths && process.executablePath.localizedCaseInsensitiveContains(needle))
                || (searchPIDs && String(process.id).contains(needle))
        }
        filtered.sort { left, right in
            if !needle.isEmpty, prioritizeApps, left.kind != right.kind {
                let leftApp = left.kind != .binary
                let rightApp = right.kind != .binary
                if leftApp != rightApp { return leftApp }
            }
            let comparison = sort == .cpu
                ? left.cpu > right.cpu : left.memoryKB > right.memoryKB
            if sort == .cpu, left.cpu == right.cpu {
                return left.memoryKB > right.memoryKB
            }
            if sort == .memory, left.memoryKB == right.memoryKB {
                return left.cpu > right.cpu
            }
            return comparison
        }
        return filtered
    }

    private static func outerAppBundle(in path: String) -> String? {
        guard let range = path.range(of: ".app/") else { return nil }
        return String(path[..<path.index(before: range.upperBound)])
    }
}
