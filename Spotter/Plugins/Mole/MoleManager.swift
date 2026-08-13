import AppKit
import Combine

/// Owns the Mole plugin's live state: locating the binary, reading every screen off-main, and
/// running the state-changing commands Spotter drives itself. `AppCore` owns the single instance.
@MainActor
final class MoleManager: ObservableObject {
    enum LoadState: Equatable {
        case idle
        case loading
        case status(MoleStatus)
        case history([MoleHistoryEntry])
        case report(MoleReport)
        case purge([MolePurgeEntry])
        case apps([MoleApp])
        case analysis(MoleAnalysis)
        case installers([MoleInstallerEntry])
        case failed(String)
    }

    @Published private(set) var state: LoadState = .idle
    @Published private(set) var screen: MoleScreen = .menu
    @Published private(set) var isLoadingPreview = false
    /// Set while a state-changing command runs; the palette shows it and blocks a second start.
    @Published private(set) var runningAction: MoleAction?
    /// The last run's closing lines, shown above the refreshed list until the screen changes.
    @Published private(set) var lastRunSummary: [String] = []

    /// Where Mole was found, or nil when it isn't installed — the settings pane and the palette both read this.
    @Published private(set) var binaryPath: String?

    /// The root currently visited by Spotter's native installer scan, shown while large folders load.
    @Published private(set) var installerScanPath: String?

    var onRunProgress: ((UUID, String, Double?) -> Void)?
    var onRunFinished: ((UUID, MoleAction, [String], Bool) -> Void)?

    /// The directory the Analyze screen is showing, plus the trail back out of it.
    @Published private(set) var analyzePath: String = NSHomeDirectory()
    private var analyzeTrail: [String] = []

    private var loadTask: Task<Void, Never>?
    private var runTask: Task<Void, Never>?
    private var loadGeneration = 0
    private var screenVisible = false
    private var lastSuccessfulLoad: (screen: MoleScreen, date: Date)?
    private static let previewReuseInterval: TimeInterval = 30
    private static let overrideKey = "mole.binary-path"
    /// Homebrew on Apple silicon, Homebrew on Intel, then a manual install.
    private static let searchPaths = [
        "/opt/homebrew/bin/mole", "/usr/local/bin/mole", "/opt/homebrew/bin/mo",
        "/usr/local/bin/mo",
    ]
    private nonisolated static let homebrewPaths = [
        "/opt/homebrew/bin/brew", "/usr/local/bin/brew",
    ]
    /// Mole 1.50's Bash 3.2 cask probe can terminate `uninstall --list` mid-JSON.
    private static let uninstallInventoryEnvironment = [
        "MO_NO_OPLOG": "1", "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
    ]

    init() {
        binaryPath = Self.locateBinary()
    }

    var isInstalled: Bool { binaryPath != nil }
    var isRunning: Bool { runningAction != nil }

    func setBinaryPathOverride(_ path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.overrideKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: Self.overrideKey)
        }
        binaryPath = Self.locateBinary()
    }

    var binaryPathOverride: String {
        UserDefaults.standard.string(forKey: Self.overrideKey) ?? ""
    }

    private static func locateBinary() -> String? {
        let fm = FileManager.default
        if let override = UserDefaults.standard.string(forKey: overrideKey),
            !override.isEmpty, fm.isExecutableFile(atPath: override)
        {
            return override
        }
        return searchPaths.first { fm.isExecutableFile(atPath: $0) }
    }

    // MARK: - Screens

    func open(_ screen: MoleScreen) {
        let changed = screen != self.screen
        if changed { lastRunSummary = [] }
        self.screen = screen
        screenVisible = true
        if screen == .analyze { resetAnalyzeRoot() }
        if !changed, canReuseCurrentPreview { return }
        if runningAction?.screen == screen { return }
        reload()
    }

    func reload() {
        guard runningAction?.screen != screen else { return }
        loadTask?.cancel()
        loadTask = nil
        loadGeneration &+= 1
        let generation = loadGeneration
        isLoadingPreview = false
        installerScanPath = nil
        lastSuccessfulLoad = nil
        guard screen != .menu else {
            state = .idle
            return
        }
        // The installer scan is Spotter's own — Mole's selector is TUI-only — so it works even
        // with no binary installed.
        if screen == .installer {
            state = .installers([])
            isLoadingPreview = true
            loadTask = Task { [weak self] in
                let entries = await Self.scanInstallers { [weak self] path, entries in
                    self?.enqueueInstallerProgress(
                        path: path, entries: entries, generation: generation)
                }
                guard !Task.isCancelled else { return }
                guard let self, self.screen == .installer, self.loadGeneration == generation else {
                    return
                }
                self.loadTask = nil
                self.isLoadingPreview = false
                self.installerScanPath = nil
                self.state = .installers(entries)
                self.markSuccessfulLoad(for: .installer)
            }
            return
        }
        guard let path = binaryPath else {
            isLoadingPreview = false
            state = .failed("Mole isn't installed. Get it at mole.fit, or set its path in Settings.")
            return
        }
        let screen = screen
        let arguments = screen == .analyze ? ["analyze", "-json", analyzePath] : screen.previewArguments
        guard let arguments else {
            state = .idle
            return
        }
        state = .loading
        isLoadingPreview = true
        let onOutput: (@Sendable (Data) -> Void)?
        if screen == .clean {
            onOutput = { [weak self] data in
                self?.enqueueCleanProgress(data, for: screen, generation: generation)
            }
        } else {
            onOutput = nil
        }
        loadTask = Task { [weak self] in
            let environment = screen == .uninstall
                ? Self.uninstallInventoryEnvironment : ["MO_NO_OPLOG": "1"]
            let result = await MoleProcessRunner.capture(
                path: path, arguments: arguments, environment: environment,
                onOutput: onOutput)
            guard !Task.isCancelled else { return }
            guard screen == .uninstall, case .success = result else {
                self?.apply(result, for: screen)
                return
            }
            let casks = await Self.loadHomebrewCasks()
            guard !Task.isCancelled else { return }
            switch casks {
            case .success(let catalog):
                self?.apply(result, for: screen, homebrewCasks: catalog)
            case .failure(let error):
                self?.apply(
                    .failure(
                        MoleRunError(
                            message: "Homebrew ownership check failed: \(error.message)")),
                    for: screen)
            }
        }
    }

    /// Cancels only the read-only pass; a state-changing run keeps going so closing the palette
    /// mid-clean can't leave the machine half-cleaned.
    func stop() {
        screenVisible = false
        let wasLoading = isLoadingPreview
        loadTask?.cancel()
        loadTask = nil
        loadGeneration &+= 1
        isLoadingPreview = false
        installerScanPath = nil
        guard !isRunning else { return }
        if wasLoading { state = .idle }
    }

    // MARK: - Analyze navigation

    func descend(into entry: MoleDiskEntry) {
        guard entry.isDirectory else { return }
        analyzeTrail.append(analyzePath)
        analyzePath = entry.path
        reload()
    }

    func ascend() {
        guard let previous = analyzeTrail.popLast() else { return }
        analyzePath = previous
        reload()
    }

    var canAscend: Bool { !analyzeTrail.isEmpty }

    private func resetAnalyzeRoot() {
        analyzeTrail = []
        analyzePath = NSHomeDirectory()
    }

    // MARK: - Running

    /// Starts a state-changing command. `AppCore` owns the confirmation, so this executes directly.
    @discardableResult
    func run(_ action: MoleAction, taskID: UUID) -> Bool {
        guard let path = binaryPath, !isRunning else { return false }
        let expectedItemCount = expectedItemCount(for: action)
        loadTask?.cancel()
        loadTask = nil
        loadGeneration &+= 1
        isLoadingPreview = false
        runTask?.cancel()
        runningAction = action
        screen = action.screen
        lastSuccessfulLoad = nil
        lastRunSummary = []
        runTask = Task { [weak self] in
            let result = await MoleProcessRunner.capture(
                path: path, arguments: action.arguments,
                standardInput: action.standardInput,
                onOutput: { [weak self] data in
                    self?.enqueueRunProgress(
                        data, taskID: taskID, action: action,
                        expectedItemCount: expectedItemCount)
                })
            guard let self else { return }
            self.finish(result, for: action, taskID: taskID)
        }
        return true
    }

    private func finish(
        _ result: Result<Data, MoleRunError>, for action: MoleAction, taskID: UUID
    ) {
        runningAction = nil
        runTask = nil
        let succeeded: Bool
        switch result {
        case .failure(let error):
            succeeded = false
            lastRunSummary = [error.message]
            AppLog.error("mole", "\(action.title) failed: \(error.message)")
        case .success(let data):
            succeeded = true
            let text = String(decoding: data, as: UTF8.self)
            let report = MoleParser.parseReport(text)
            lastRunSummary =
                report.summary.isEmpty ? ["\(action.title) finished."] : report.summary
        }
        // A hidden palette should not launch another expensive preview after the real run.
        if screen == action.screen {
            if screenVisible { reload() } else { state = .idle }
        }
        onRunFinished?(taskID, action, lastRunSummary, succeeded)
    }

    private func expectedItemCount(for action: MoleAction) -> Int? {
        switch (action, state) {
        case (.clean, .report(let report)), (.optimize, .report(let report)):
            report.items.count
        case (.purge, .purge(let entries)):
            entries.count
        default:
            nil
        }
    }

    private nonisolated func enqueueRunProgress(
        _ data: Data, taskID: UUID, action: MoleAction, expectedItemCount: Int?
    ) {
        let snapshot = Self.runProgress(
            data, action: action, expectedItemCount: expectedItemCount)
        Task { @MainActor [weak self] in
            guard self?.runningAction == action else { return }
            self?.onRunProgress?(taskID, snapshot.detail, snapshot.progress)
        }
    }

    private nonisolated static func runProgress(
        _ data: Data, action: MoleAction, expectedItemCount: Int?
    ) -> (detail: String, progress: Double?) {
        let text = String(decoding: data, as: UTF8.self)
        let completed: Int
        let detail: String
        switch action {
        case .clean, .optimize:
            let report = MoleParser.parseReport(text)
            completed = report.items.count
            detail = report.items.last?.title ?? latestProgressLine(in: text) ?? "Running…"
        case .purge:
            let entries = MoleParser.parsePurge(text)
            completed = entries.count
            detail = entries.last.map { ($0.path as NSString).lastPathComponent }
                ?? latestProgressLine(in: text) ?? "Running…"
        case .uninstall:
            completed = 0
            detail = latestProgressLine(in: text) ?? "Removing the app and its support files…"
        }
        let progress = expectedItemCount.flatMap { count in
            count > 0 ? min(Double(completed) / Double(count), 0.99) : nil
        }
        return (detail, progress)
    }

    private nonisolated static func latestProgressLine(in text: String) -> String? {
        MoleParser.stripANSI(text)
            .split(separator: "\n")
            .reversed()
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private func apply(
        _ result: Result<Data, MoleRunError>, for screen: MoleScreen,
        homebrewCasks: [String: String] = [:]
    ) {
        // A screen switch mid-flight must not have its result overwritten by the older request.
        guard screen == self.screen else { return }
        loadTask = nil
        isLoadingPreview = false
        switch result {
        case .failure(let error):
            state = .failed(error.message)
            AppLog.error("mole", "Loading \(screen.rawValue) failed: \(error.message)")
        case .success(let data):
            switch screen {
            case .menu:
                state = .idle
            case .status:
                guard let status = MoleParser.parseStatus(data) else {
                    state = .failed("Mole returned an unreadable status response.")
                    return
                }
                state = .status(status)
            case .history:
                state = .history(MoleParser.parseHistory(data))
            case .clean, .optimize:
                state = .report(MoleParser.parseReport(String(decoding: data, as: UTF8.self)))
            case .purge:
                state = .purge(MoleParser.parsePurge(String(decoding: data, as: UTF8.self)))
            case .uninstall:
                let apps = MoleParser.parseApps(data, homebrewCasks: homebrewCasks)
                state = apps.isEmpty
                    ? .failed("Mole didn't return an app list.") : .apps(apps)
            case .analyze:
                guard let analysis = MoleParser.parseAnalysis(data) else {
                    state = .failed("Mole couldn't analyze \(analyzePath).")
                    return
                }
                state = .analysis(analysis)
            case .installer:
                break  // populated by the dedicated scan branch in `reload`
            }
            if case .failed = state {} else { markSuccessfulLoad(for: screen) }
        }
    }

    private var canReuseCurrentPreview: Bool {
        guard let loaded = lastSuccessfulLoad, loaded.screen == screen,
            Date().timeIntervalSince(loaded.date) < Self.previewReuseInterval
        else { return false }
        return switch state {
        case .status, .history, .report, .purge, .apps, .analysis, .installers: true
        case .idle, .loading, .failed: false
        }
    }

    private func markSuccessfulLoad(for screen: MoleScreen) {
        lastSuccessfulLoad = (screen, Date())
    }

    /// Homebrew's local JSON lets Spotter block cask rows that Mole would remove incompletely.
    private nonisolated static func loadHomebrewCasks()
        async -> Result<[String: String], MoleRunError>
    {
        guard let brew = homebrewPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return .success([:])
        }
        let result = await MoleProcessRunner.capture(
            path: brew, arguments: ["info", "--json=v2", "--installed", "--cask"],
            environment: ["HOMEBREW_NO_AUTO_UPDATE": "1", "HOMEBREW_NO_ENV_HINTS": "1"])
        switch result {
        case .failure(let error):
            return .failure(error)
        case .success(let data):
            guard let catalog = MoleParser.parseHomebrewCasks(data) else {
                return .failure(MoleRunError(message: "Homebrew returned unreadable cask data."))
            }
            return .success(catalog)
        }
    }

    private nonisolated func enqueueCleanProgress(
        _ data: Data, for screen: MoleScreen, generation: Int
    ) {
        Task { @MainActor [weak self] in
            self?.applyCleanProgress(data, for: screen, generation: generation)
        }
    }

    private func applyCleanProgress(_ data: Data, for screen: MoleScreen, generation: Int) {
        guard screen == .clean, self.screen == screen, screenVisible, isLoadingPreview,
            runningAction == nil, generation == loadGeneration
        else { return }
        let report = MoleParser.parseReport(String(decoding: data, as: UTF8.self))
        guard !report.isEmpty else { return }
        state = .report(report)
    }

    /// Walks Mole's installer paths (depth 2) off-main: direct installer extensions always count,
    /// a zip only when its listing contains an installer — the same rules `mo installer` applies.
    private nonisolated static func scanInstallers(
        onProgress: @escaping @Sendable (String, [MoleInstallerEntry]) -> Void
    ) async -> [MoleInstallerEntry] {
        let scan = Task.detached(priority: .userInitiated) {
            walkInstallerRoots(onProgress: onProgress)
        }
        return await withTaskCancellationHandler {
            await scan.value
        } onCancel: {
            scan.cancel()
        }
    }

    /// Synchronous walk — `DirectoryEnumerator` iteration isn't available in async contexts.
    private nonisolated static func walkInstallerRoots(
        onProgress: @Sendable (String, [MoleInstallerEntry]) -> Void
    ) -> [MoleInstallerEntry] {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        var entries: [MoleInstallerEntry] = []
        var seen = Set<String>()
        for root in MoleInstallerScan.roots(home: home) {
            guard !Task.isCancelled else { return [] }
            onProgress(root, entries.sorted { $0.size > $1.size })
            guard let walker = fm.enumerator(
                at: URL(fileURLWithPath: root),
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants])
            else { continue }
            for case let url as URL in walker {
                guard !Task.isCancelled else { return [] }
                if !MoleInstallerScan.canDescend(from: walker.level) {
                    walker.skipDescendants()
                }
                guard MoleInstallerScan.includes(level: walker.level) else { continue }
                let name = url.lastPathComponent
                let direct = MoleInstallerScan.isDirectInstaller(name)
                guard direct || MoleInstallerScan.isZip(name) else { continue }
                guard
                    let values = try? url.resourceValues(
                        forKeys: [.fileSizeKey, .isRegularFileKey]),
                    values.isRegularFile == true
                else { continue }
                // Roots overlap (Downloads contains Telegram Desktop); one path, one row.
                guard seen.insert(url.path).inserted else { continue }
                if !direct, !zipContainsInstaller(at: url.path) { continue }
                guard !Task.isCancelled else { return [] }
                entries.append(
                    MoleInstallerEntry(
                        name: name,
                        path: url.path,
                        folder: (url.deletingLastPathComponent().path as NSString)
                            .abbreviatingWithTildeInPath,
                        size: Int64(values.fileSize ?? 0)))
                onProgress(root, entries.sorted { $0.size > $1.size })
            }
        }
        return entries.sorted { $0.size > $1.size }
    }

    private nonisolated func enqueueInstallerProgress(
        path: String, entries: [MoleInstallerEntry], generation: Int
    ) {
        Task { @MainActor [weak self] in
            guard let self, self.screen == .installer, self.screenVisible,
                self.isLoadingPreview, self.runningAction == nil,
                generation == self.loadGeneration
            else { return }
            self.installerScanPath = path
            self.state = .installers(entries)
        }
    }

    /// `zipinfo -1` lists archived paths without extraction; a failure reads as "not an installer".
    private nonisolated static func zipContainsInstaller(at path: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zipinfo")
        process.arguments = ["-1", path]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let listing = String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
        return MoleInstallerScan.zipListingSuggestsInstaller(listing)
    }
}
