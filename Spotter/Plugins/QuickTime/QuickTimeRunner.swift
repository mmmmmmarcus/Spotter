import Foundation

enum QuickTimeRecordingKind: String, CaseIterable, Identifiable, Sendable {
    case screen, audio, movie

    var id: String { rawValue }
    var title: String {
        switch self {
        case .screen: "New Screen Recording"
        case .audio: "New Audio Recording"
        case .movie: "New Movie Recording"
        }
    }
    var systemImage: String {
        switch self {
        case .screen: "rectangle.dashed.badge.record"
        case .audio: "mic"
        case .movie: "video"
        }
    }

    var appleScript: String {
        """
        tell application "QuickTime Player" to activate
        tell application "System Events"
            tell process "QuickTime Player"
                click menu item "\(title)" of menu "File" of menu bar 1
            end tell
        end tell
        """
    }
}

struct QuickTimeRunError: Error, Sendable {
    let message: String
}

enum QuickTimeRunner {
    static func run(_ kind: QuickTimeRecordingKind) async throws {
        let script = kind.appleScript
        let result = await Task.detached(priority: .userInitiated) {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            process.standardError = pipe
            do {
                try process.run()
            } catch {
                return (Int32(-1), error.localizedDescription)
            }
            try? await Task.sleep(for: .seconds(2))
            if process.isRunning {
                process.terminate()
                return (Int32(0), "")
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        }.value
        guard result.0 == 0 else {
            let detail = result.1.trimmingCharacters(in: .whitespacesAndNewlines)
            throw QuickTimeRunError(message: detail.isEmpty ? "QuickTime Player could not start the recording." : detail)
        }
    }
}
