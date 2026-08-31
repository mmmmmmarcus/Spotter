import Foundation

enum TerminalCommandOutcome: Equatable, Sendable {
    case success
    case launchFailure(String)
    case scriptFailure(status: Int32)
}

/// The terminals "Run in Terminal" can hand a command to. AppleScript-scriptable apps get a
/// `do script`-style handoff; the rest launch with the command as their own `-e` argv. The Settings
/// picker offers only the installed ones, but a synced choice for a missing app still resolves here
/// and simply fails to launch, which the caller surfaces.
enum PreferredTerminal: String, CaseIterable, Sendable {
    case terminal
    case iterm
    case ghostty
    case alacritty
    case kitty

    var displayName: String {
        switch self {
        case .terminal: "Terminal"
        case .iterm: "iTerm2"
        case .ghostty: "Ghostty"
        case .alacritty: "Alacritty"
        case .kitty: "kitty"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .terminal: "com.apple.Terminal"
        case .iterm: "com.googlecode.iterm2"
        case .ghostty: "com.mitchellh.ghostty"
        case .alacritty: "org.alacritty"
        case .kitty: "net.kovidgoyal.kitty"
        }
    }

    /// The `open -a` name for the argv terminals.
    fileprivate var applicationName: String {
        switch self {
        case .terminal: "Terminal"
        case .iterm: "iTerm"
        case .ghostty: "Ghostty"
        case .alacritty: "Alacritty"
        case .kitty: "kitty"
        }
    }
}

/// One resolved handoff: the executable to spawn and its full argv.
struct TerminalInvocation: Equatable, Sendable {
    let executablePath: String
    let arguments: [String]
}

enum TerminalCommandRunner {
    private static let queue = DispatchQueue(
        label: "com.spotter.terminal-command", qos: .userInitiated, attributes: .concurrent)

    private static let terminalScriptLines = [
        "on run argv",
        "set commandText to item 1 of argv",
        "tell application \"Terminal\"",
        "activate",
        "do script commandText",
        "end tell",
        "end run",
    ]

    private static let itermScriptLines = [
        "on run argv",
        "set commandText to item 1 of argv",
        "tell application \"iTerm\"",
        "activate",
        "create window with default profile",
        "tell current session of current window",
        "write text commandText",
        "end tell",
        "end tell",
        "end run",
    ]

    nonisolated static func run(
        _ rawCommand: String, terminal: PreferredTerminal = .terminal
    ) async -> TerminalCommandOutcome {
        guard let invocation = invocation(for: rawCommand, terminal: terminal) else {
            return .success
        }
        return await withCheckedContinuation { continuation in
            queue.async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: invocation.executablePath)
                process.arguments = invocation.arguments
                process.standardInput = FileHandle.nullDevice
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: .launchFailure(error.localizedDescription))
                    return
                }
                process.waitUntilExit()
                guard process.terminationReason == .exit, process.terminationStatus == 0 else {
                    continuation.resume(
                        returning: .scriptFailure(status: process.terminationStatus))
                    return
                }
                continuation.resume(returning: .success)
            }
        }
    }

    /// For the scriptable terminals the command is an argv value, never interpolated into
    /// AppleScript source. The argv terminals run it as shell input — which it is — through their
    /// own `-e`, followed by an interactive shell so the window survives the command finishing.
    nonisolated static func invocation(
        for rawCommand: String, terminal: PreferredTerminal
    ) -> TerminalInvocation? {
        let command = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return nil }
        switch terminal {
        case .terminal:
            return TerminalInvocation(
                executablePath: "/usr/bin/osascript",
                arguments: terminalScriptLines.flatMap { ["-e", $0] } + ["--", command])
        case .iterm:
            return TerminalInvocation(
                executablePath: "/usr/bin/osascript",
                arguments: itermScriptLines.flatMap { ["-e", $0] } + ["--", command])
        case .ghostty, .alacritty, .kitty:
            // Newline, not `;`: a command ending in `&` or a comment must not swallow the exec.
            let shell = ["/bin/zsh", "-l", "-c", command + "\nexec /bin/zsh -i"]
            let launcher = terminal == .kitty ? ["--args"] : ["--args", "-e"]
            return TerminalInvocation(
                executablePath: "/usr/bin/open",
                arguments: ["-na", terminal.applicationName] + launcher + shell)
        }
    }
}
