import AppKit
import Combine

/// Carries the user-facing reason a Mole invocation failed across the actor boundary.
struct MoleRunError: Error, Sendable {
    let message: String
}

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
        case failed(String)
    }

    @Published private(set) var state: LoadState = .idle
    @Published private(set) var screen: MoleScreen = .menu
    /// Set while a state-changing command runs; the palette shows it and blocks a second start.
    @Published private(set) var runningAction: MoleAction?
    /// The last run's closing lines, shown above the refreshed list until the screen changes.
    @Published private(set) var lastRunSummary: [String] = []

    /// Where Mole was found, or nil when it isn't installed — the settings pane and the palette both read this.
    @Published private(set) var binaryPath: String?

    /// Fired when a state-changing run finishes, so `AppCore` can surface a HUD if the Mole screen
    /// isn't visible to show it on the run row.
    var onRunFinished: ((MoleAction, [String]) -> Void)?

    /// The directory the Analyze screen is showing, plus the trail back out of it.
    @Published private(set) var analyzePath: String = NSHomeDirectory()
    private var analyzeTrail: [String] = []

    private var loadTask: Task<Void, Never>?
    private var runTask: Task<Void, Never>?
    private static let overrideKey = "mole.binary-path"
    /// Homebrew on Apple silicon, Homebrew on Intel, then a manual install.
    private static let searchPaths = [
        "/opt/homebrew/bin/mole", "/usr/local/bin/mole", "/opt/homebrew/bin/mo",
        "/usr/local/bin/mo",
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
        if screen != self.screen { lastRunSummary = [] }
        self.screen = screen
        if screen == .analyze { resetAnalyzeRoot() }
        reload()
    }

    func reload() {
        loadTask?.cancel()
        guard screen != .menu else {
            state = .idle
            return
        }
        guard let path = binaryPath else {
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
        loadTask = Task { [weak self] in
            let result = await Self.capture(path: path, arguments: arguments)
            guard !Task.isCancelled else { return }
            self?.apply(result, for: screen)
        }
    }

    /// Cancels only the read-only pass; a state-changing run keeps going so closing the palette
    /// mid-clean can't leave the machine half-cleaned.
    func stop() {
        loadTask?.cancel()
        loadTask = nil
        guard !isRunning else { return }
        state = .idle
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
    func run(_ action: MoleAction) {
        guard let path = binaryPath, !isRunning else { return }
        runTask?.cancel()
        runningAction = action
        lastRunSummary = []
        runTask = Task { [weak self] in
            let result = await Self.capture(path: path, arguments: action.arguments)
            guard let self else { return }
            self.finish(result, for: action)
        }
    }

    private func finish(_ result: Result<Data, MoleRunError>, for action: MoleAction) {
        runningAction = nil
        switch result {
        case .failure(let error):
            lastRunSummary = [error.message]
        case .success(let data):
            let text = String(decoding: data, as: UTF8.self)
            let report = MoleParser.parseReport(text)
            lastRunSummary =
                report.summary.isEmpty ? ["\(action.title) finished."] : report.summary
        }
        // The list is now stale — re-read it so what's left is what's shown.
        if screen == action.screen { reload() }
        onRunFinished?(action, lastRunSummary)
    }

    private func apply(_ result: Result<Data, MoleRunError>, for screen: MoleScreen) {
        // A screen switch mid-flight must not have its result overwritten by the older request.
        guard screen == self.screen else { return }
        switch result {
        case .failure(let error):
            state = .failed(error.message)
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
                let apps = MoleParser.parseApps(data)
                state = apps.isEmpty
                    ? .failed("Mole didn't return an app list.") : .apps(apps)
            case .analyze:
                guard let analysis = MoleParser.parseAnalysis(data) else {
                    state = .failed("Mole couldn't analyze \(analyzePath).")
                    return
                }
                state = .analysis(analysis)
            }
        }
    }

    /// Off-main; only plain values cross back. stdin is `/dev/null` and stdout a pipe, so Mole takes
    /// its non-interactive path — no TUI, no sudo prompt, nothing waiting on a keystroke.
    private nonisolated static func capture(path: String, arguments: [String]) async -> Result<
        Data, MoleRunError
    > {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments
                let out = Pipe()
                process.standardOutput = out
                process.standardError = Pipe()
                process.standardInput = FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    continuation.resume(
                        returning: .failure(
                            MoleRunError(message: "Couldn't run Mole: \(error.localizedDescription)")))
                    return
                }
                let data = out.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard !data.isEmpty else {
                    continuation.resume(
                        returning: .failure(MoleRunError(message: "Mole returned no output.")))
                    return
                }
                continuation.resume(returning: .success(data))
            }
        }
    }

    /// The installer selector repaints a full-screen list and reads raw keystrokes, so it is the one
    /// command Spotter can't render — it runs where the user can actually see and drive it.
    func runInTerminal(_ command: MoleCommand) {
        guard let path = binaryPath else { return }
        let script = """
            tell application "Terminal"
                activate
                do script "\(path) \(command.argument)"
            end tell
            """
        Task.detached {
            var error: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&error)
        }
    }
}
