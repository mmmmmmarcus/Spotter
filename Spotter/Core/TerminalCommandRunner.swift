import Foundation

enum TerminalCommandOutcome: Equatable, Sendable {
    case success
    case launchFailure(String)
    case scriptFailure(status: Int32)
}

enum TerminalCommandRunner {
    private static let queue = DispatchQueue(
        label: "com.spotter.terminal-command", qos: .userInitiated, attributes: .concurrent)
    private static let scriptLines = [
        "on run argv",
        "set commandText to item 1 of argv",
        "tell application \"Terminal\"",
        "activate",
        "do script commandText",
        "end tell",
        "end run",
    ]

    nonisolated static func run(_ rawCommand: String) async -> TerminalCommandOutcome {
        guard let arguments = arguments(for: rawCommand) else { return .success }
        return await withCheckedContinuation { continuation in
            queue.async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = arguments
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

    /// The command is an argv value, never interpolated into AppleScript source.
    nonisolated static func arguments(for rawCommand: String) -> [String]? {
        let command = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return nil }
        return scriptLines.flatMap { ["-e", $0] } + ["--", command]
    }
}
