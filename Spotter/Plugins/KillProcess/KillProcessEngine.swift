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
