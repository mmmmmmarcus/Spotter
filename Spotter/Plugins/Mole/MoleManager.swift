import AppKit
import Combine

/// Carries the user-facing reason a Mole invocation failed across the actor boundary.
struct MoleRunError: Error, Sendable {
    let message: String
}

/// Owns the Mole plugin's live state: locating the binary, running the two JSON commands off-main,
/// and handing interactive commands to Terminal. `AppCore` owns the single instance.
@MainActor
final class MoleManager: ObservableObject {
    enum Screen: Equatable {
        case status
        case history
    }

    enum LoadState: Equatable {
        case idle
        case loading
        case status(MoleStatus)
        case history([MoleHistoryEntry])
        case failed(String)
    }

    @Published private(set) var state: LoadState = .idle
    @Published private(set) var screen: Screen = .status

    /// Where Mole was found, or nil when it isn't installed — the settings pane and the palette both read this.
    @Published private(set) var binaryPath: String?

    private var loadTask: Task<Void, Never>?
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

    func open(_ screen: Screen) {
        self.screen = screen
        reload()
    }

    func reload() {
        loadTask?.cancel()
        guard let path = binaryPath else {
            state = .failed("Mole isn't installed. Get it at mole.fit, or set its path in Settings.")
            return
        }
        let screen = screen
        state = .loading
        loadTask = Task { [weak self] in
            let argument = screen == .status ? "status" : "history"
            // `history` needs the flag; `status` already emits JSON on a non-TTY.
            let arguments = screen == .status ? [argument] : [argument, "--json"]
            let result = await Self.runJSON(path: path, arguments: arguments)
            guard !Task.isCancelled else { return }
            self?.apply(result, for: screen)
        }
    }

    func stop() {
        loadTask?.cancel()
        loadTask = nil
        state = .idle
    }

    private func apply(_ result: Result<Data, MoleRunError>, for screen: Screen) {
        // A screen switch mid-flight must not have its result overwritten by the older request.
        guard screen == self.screen else { return }
        switch result {
        case .failure(let error):
            state = .failed(error.message)
        case .success(let data):
            switch screen {
            case .status:
                guard let status = MoleParser.parseStatus(data) else {
                    state = .failed("Mole returned an unreadable status response.")
                    return
                }
                state = .status(status)
            case .history:
                state = .history(MoleParser.parseHistory(data))
            }
        }
    }

    /// Off-main; only plain values cross back. stdout is a pipe, so Mole takes its non-TTY JSON path.
    private nonisolated static func runJSON(path: String, arguments: [String]) async -> Result<
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

    /// Interactive commands are TUIs that also delete files, so they run in the user's terminal where they can be seen and confirmed — never silently from the launcher.
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
