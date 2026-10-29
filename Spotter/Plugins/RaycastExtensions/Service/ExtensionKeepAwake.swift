import Darwin
import Foundation

struct ExtensionKeepAwakeProcess: Codable, Sendable, Equatable {
    let id: UUID
    let pid: Int32
    let startSeconds: UInt64
    let startMicroseconds: UInt64
    let extensionName: String
    let extensionTitle: String
    let startedAt: Date
    let duration: TimeInterval?

    static func capture(pid: Int32, name: String, title: String, arguments: [String]) -> Self? {
        guard let identity = identity(pid: pid) else { return nil }
        return Self(id: UUID(), pid: pid, startSeconds: identity.0, startMicroseconds: identity.1,
                    extensionName: name, extensionTitle: title, startedAt: Date(),
                    duration: duration(arguments: arguments))
    }

    static func duration(arguments: [String]) -> TimeInterval? {
        // A watched process can end before its timeout; utility commands ignore the timeout entirely.
        var duration: TimeInterval?
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "-t" {
                index += 1
                guard index < arguments.count, let value = Double(arguments[index]),
                      value.isFinite, value > 0, value <= Double(Int32.max), value.rounded() == value else { return nil }
                duration = value
            } else if !argument.hasPrefix("-") || argument.count < 2
                || !argument.dropFirst().allSatisfy({ "dimsu".contains($0) }) {
                return nil
            }
            index += 1
        }
        return duration
    }

    var isRunning: Bool {
        guard let current = Self.identity(pid: pid) else { return false }
        return current.0 == startSeconds && current.1 == startMicroseconds
    }

    func stop() -> Bool {
        // Never trust a saved PID alone: it may now belong to an unrelated process.
        guard isRunning else { return true }
        return Darwin.kill(pid, SIGTERM) == 0 || errno == ESRCH
    }

    private static func identity(pid: Int32) -> (UInt64, UInt64)? {
        guard pid > 1 else { return nil }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
              info.pbi_uid == getuid(), info.pbi_status != SZOMB else { return nil }
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0,
              String(decoding: path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self) == "/usr/bin/caffeinate" else { return nil }
        return (info.pbi_start_tvsec, info.pbi_start_tvusec)
    }

    private var validDuration: TimeInterval? {
        guard let duration, duration.isFinite, duration > 0, duration <= Double(Int32.max) else { return nil }
        return duration
    }

    func detail(now: Date) -> String {
        guard let duration = validDuration else { return "Keeping Mac awake · Until stopped or the watched process ends" }
        let remaining = Int(ceil(min(duration, max(0, duration - now.timeIntervalSince(startedAt)))))
        guard remaining > 0 else { return "Finishing…" }
        let hours = remaining / 3600
        let minutes = remaining % 3600 / 60
        let seconds = remaining % 60
        let text = hours > 0 ? "\(hours)h \(minutes)m" : minutes > 0 ? "\(minutes)m \(seconds)s" : "\(seconds)s"
        return "Keeping Mac awake · \(text) remaining"
    }

    func progress(now: Date) -> Double? {
        validDuration.map { min(1, max(0, now.timeIntervalSince(startedAt) / $0)) }
    }
}

@MainActor
final class ExtensionKeepAwake {
    private let tasks: BackgroundTaskStore
    private let defaults: UserDefaults
    private let key = "raycast-extensions.keep-awake-processes"
    private var processes: [UUID: ExtensionKeepAwakeProcess] = [:]
    private var stopping: Set<UUID> = []
    private var ticker: Task<Void, Never>?
    private var acceptsNewWork = true
    private var removedExtensions: Set<String> = []

    init(tasks: BackgroundTaskStore, defaults: UserDefaults = .standard) {
        self.tasks = tasks
        self.defaults = defaults
    }

    deinit { ticker?.cancel() }

    func setEnabled(_ enabled: Bool) {
        acceptsNewWork = enabled
        if !enabled { stop() }
    }

    func remove(extensionName: String) {
        removedExtensions.insert(extensionName)
        stop(extensionName: extensionName)
    }

    func synchronize(installed: Set<String>) {
        removedExtensions.subtract(installed)
        for process in Array(processes.values) where !installed.contains(process.extensionName) {
            remove(extensionName: process.extensionName)
        }
    }

    func restore() {
        guard let data = defaults.data(forKey: key),
              let saved = try? JSONDecoder().decode([ExtensionKeepAwakeProcess].self, from: data) else { return }
        for process in saved where process.isRunning { track(process) }
        persist()
    }

    func track(_ process: ExtensionKeepAwakeProcess) {
        guard process.isRunning, !processes.values.contains(where: {
            $0.pid == process.pid && $0.startSeconds == process.startSeconds
                && $0.startMicroseconds == process.startMicroseconds
        }) else { return }
        processes[process.id] = process
        // Recovery can replace an interrupted snapshot previously loaded by settings sync.
        tasks.discard(id: process.id)
        tasks.begin(title: "\(process.extensionTitle) · Keeping Mac awake",
                    detail: process.detail(now: Date()), systemImage: "cup.and.saucer.fill", id: process.id,
                    onCancel: { [weak self] in self?.stop(id: process.id) })
        if !acceptsNewWork || removedExtensions.contains(process.extensionName) { stop(id: process.id) }
        refresh()
        persist()
        if ticker == nil {
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled, let self else { return }
                    self.refresh()
                    if self.processes.isEmpty { self.ticker = nil; return }
                }
            }
        }
    }

    func stop(extensionName: String? = nil) {
        for process in Array(processes.values) where extensionName == nil || process.extensionName == extensionName {
            stop(id: process.id)
        }
    }

    private func stop(id: UUID) {
        guard let process = processes[id] else { return }
        guard process.stop() else {
            tasks.update(id: id, detail: "Could not stop keeping awake. Try Cancel again.", progress: nil)
            return
        }
        stopping.insert(id)
        tasks.update(id: id, detail: "Stopping…", progress: nil)
    }

    func refresh(now: Date = Date()) {
        var changed = false
        for process in Array(processes.values) {
            if !process.isRunning {
                let stopped = stopping.remove(process.id) != nil
                tasks.complete(id: process.id, detail: stopped ? "Stopped keeping Mac awake." : "Keep-awake session ended.")
                processes[process.id] = nil
                changed = true
            } else if !stopping.contains(process.id) {
                tasks.update(id: process.id, detail: process.detail(now: now), progress: process.progress(now: now))
            }
        }
        if changed { persist() }
    }

    private func persist() {
        defaults.set(try? JSONEncoder().encode(Array(processes.values)), forKey: key)
    }
}
