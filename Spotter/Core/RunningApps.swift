import AppKit

/// One regular app's live resource reading for the Active Apps launcher section.
struct AppResourceUsage: Equatable, Sendable {
    let cpu: Double
    let memoryBytes: Int64

    var text: String {
        let cpuText = cpu.formatted(.number.precision(.fractionLength(0))) + "%"
        let memoryText = ByteCountFormatter.string(fromByteCount: memoryBytes, countStyle: .memory)
        return cpuText + " · " + memoryText
    }
}

/// Tracks running apps for the launcher's running indicator, updating live from NSWorkspace launch/terminate notifications.
@MainActor
final class RunningAppsMonitor: ObservableObject {
    @Published private(set) var runningBundleIDs: Set<String> = []
    /// Live per-app readings for the Active Apps section, keyed by bundle identifier; empty while sampling is off.
    @Published private(set) var usage: [String: AppResourceUsage] = [:]
    private var observers: [NotificationToken] = []
    private var usageTask: Task<Void, Never>?

    init() {
        refresh()
        let center = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            observers.append(NotificationToken(token, center: center))
        }
    }

    /// True when the entry's bundle is currently running — drives the row's running dot and the Quit action.
    func isRunning(_ app: AppEntry) -> Bool {
        guard let bundleID = app.bundleID else { return false }
        return runningBundleIDs.contains(bundleID)
    }

    // MARK: - Usage sampling

    /// Started when the palette shows with the Active Apps section enabled and stopped when it
    /// hides: one `ps` snapshot every few seconds, summed per running app bundle — the same source
    /// Kill Process reads, scoped to apps the launcher actually lists.
    func startUsageSampling() {
        guard usageTask == nil else { return }
        usageTask = Task { [weak self] in
            while !Task.isCancelled {
                let apps = NSWorkspace.shared.runningApplications
                    .filter { $0.activationPolicy == .regular }
                    .compactMap { app -> (bundleID: String, path: String)? in
                        guard let id = app.bundleIdentifier, let url = app.bundleURL else {
                            return nil
                        }
                        return (id, url.path)
                    }
                let sampled = await Self.sampleUsage(apps: apps)
                guard let self, !Task.isCancelled else { return }
                if self.usage != sampled { self.usage = sampled }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func stopUsageSampling() {
        usageTask?.cancel()
        usageTask = nil
        usage = [:]
    }

    nonisolated private static func sampleUsage(
        apps: [(bundleID: String, path: String)]
    ) async -> [String: AppResourceUsage] {
        await Task.detached(priority: .utility) {
            let task = Process()
            let pipe = Pipe()
            task.executableURL = URL(fileURLWithPath: "/bin/ps")
            task.arguments = ["-axo", "%cpu=,rss=,comm="]
            task.environment = ProcessInfo.processInfo.environment.merging(["LC_ALL": "C"]) {
                _, new in new
            }
            task.standardOutput = pipe
            task.standardError = FileHandle.nullDevice
            guard (try? task.run()) != nil else { return [:] }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else { return [:] }

            var totals: [String: (cpu: Double, memoryKB: Int64)] = [:]
            let output = String(decoding: data, as: UTF8.self)
            for line in output.split(whereSeparator: \.isNewline) {
                let fields = line.split(maxSplits: 2, whereSeparator: \.isWhitespace)
                guard fields.count == 3,
                    let cpu = Double(fields[0].replacingOccurrences(of: ",", with: ".")),
                    let memoryKB = Int64(fields[1])
                else { continue }
                let path = String(fields[2])
                // Every process inside the app bundle counts toward the app, helpers included.
                guard let app = apps.first(where: {
                    path == $0.path || path.hasPrefix($0.path + "/")
                }) else { continue }
                let current = totals[app.bundleID] ?? (0, 0)
                totals[app.bundleID] = (current.cpu + cpu, current.memoryKB + memoryKB)
            }
            return totals.mapValues {
                AppResourceUsage(cpu: $0.cpu, memoryBytes: $0.memoryKB * 1024)
            }
        }.value
    }

    /// Launch/terminate fire for helpers and agents the launcher never lists, so republish only on a real change — an unconditional assign would invalidate every observer for nothing.
    private func refresh() {
        let next = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        guard next != runningBundleIDs else { return }
        runningBundleIDs = next
    }
}
