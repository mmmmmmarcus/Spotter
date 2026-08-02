import AppKit
import Darwin

@MainActor
final class KillProcessManager: ObservableObject {
    @Published private(set) var processes: [RunningProcessInfo] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    private var refreshTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?

    func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                let defaults = UserDefaults.standard
                let interval = defaults.object(forKey: "kill-process.refresh-seconds") == nil
                    ? 2.0 : max(0.5, defaults.double(forKey: "kill-process.refresh-seconds"))
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func refresh() async {
        guard refreshTask == nil else { return }
        isRefreshing = true
        errorMessage = nil
        let task = Task { [weak self] in
            do {
                let values = try await Self.fetchProcesses()
                guard !Task.isCancelled else { return }
                self?.processes = values
            } catch {
                self?.errorMessage = error.localizedDescription
            }
            self?.isRefreshing = false
            self?.refreshTask = nil
        }
        refreshTask = task
        await task.value
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        refreshTask?.cancel()
        refreshTask = nil
        isRefreshing = false
    }

    func terminate(_ process: RunningProcessInfo, force: Bool) async throws {
        let targets = process.childProcessIDs + [process.id]
        try await Task.detached(priority: .userInitiated) {
            try send(signal: force ? SIGKILL : SIGTERM, to: targets, elevateIfDenied: force)
        }.value
        processes.removeAll { targets.contains($0.id) }
    }

    func terminateAll(named name: String, force: Bool) async throws {
        let targets = processes.filter { $0.processName == name }.map(\.id)
        guard !targets.isEmpty else { return }
        try await Task.detached(priority: .userInitiated) {
            try send(signal: force ? SIGKILL : SIGTERM, to: targets, elevateIfDenied: force)
        }.value
        processes.removeAll { targets.contains($0.id) }
    }

    func restart(_ process: RunningProcessInfo, force: Bool) async throws {
        let bundlePath = process.appBundlePath
        let executablePath = process.executablePath
        try await terminate(process, force: force)
        try await Task.sleep(for: .milliseconds(250))
        if let bundlePath {
            let configuration = NSWorkspace.OpenConfiguration()
            try await NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: bundlePath), configuration: configuration)
        } else {
            try await Task.detached(priority: .userInitiated) {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: executablePath)
                task.standardInput = FileHandle.nullDevice
                task.standardOutput = FileHandle.nullDevice
                task.standardError = FileHandle.nullDevice
                try task.run()
            }.value
        }
        await refresh()
    }

    nonisolated private static func fetchProcesses() async throws -> [RunningProcessInfo] {
        try await Task.detached(priority: .userInitiated) {
            let task = Process()
            let pipe = Pipe()
            task.executableURL = URL(fileURLWithPath: "/bin/ps")
            task.arguments = ["-axo", "pid=,ppid=,%cpu=,rss=,comm="]
            task.environment = ProcessInfo.processInfo.environment.merging(["LC_ALL": "C"]) {
                _, new in new
            }
            task.standardOutput = pipe
            task.standardError = FileHandle.nullDevice
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else {
                throw CocoaError(.fileReadUnknown)
            }
            let output = String(decoding: data, as: UTF8.self)
            return KillProcessEngine.parse(
                output, excluding: ProcessInfo.processInfo.processIdentifier,
                excludingBundlePath: Bundle.main.bundleURL.path)
        }.value
    }
}

private func send(signal: Int32, to pids: [Int32], elevateIfDenied: Bool) throws {
    var firstError: NSError?
    var denied: [Int32] = []
    for pid in pids where Darwin.kill(pid, signal) != 0 {
        let code = errno
        if code == EPERM, elevateIfDenied { denied.append(pid); continue }
        guard firstError == nil else { continue }
        let message = String(cString: strerror(code))
        firstError = NSError(
            domain: NSPOSIXErrorDomain, code: Int(code),
            userInfo: [NSLocalizedDescriptionKey: "PID \(pid): \(message)"])
    }
    if let firstError { throw firstError }
    if !denied.isEmpty { try authorizedKill(signal: signal, pids: denied) }
}

private func authorizedKill(signal: Int32, pids: [Int32]) throws {
    let arguments = pids.map(String.init).joined(separator: " ")
    let script = "do shell script \"/bin/kill -\(signal) \(arguments)\" with administrator privileges"
    let task = Process()
    let errorPipe = Pipe()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    task.arguments = ["-e", script]
    task.standardOutput = FileHandle.nullDevice
    task.standardError = errorPipe
    try task.run()
    task.waitUntilExit()
    guard task.terminationStatus == 0 else {
        let detail = String(
            decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        throw NSError(
            domain: NSPOSIXErrorDomain, code: Int(task.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: detail.isEmpty ? "Administrator authorization was denied." : detail])
    }
}
