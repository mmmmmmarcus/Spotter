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
        switch self {
        case .screen:
            "tell application \"QuickTime Player\" to start (new screen recording)"
        case .audio:
            "tell application \"QuickTime Player\" to activate\ntell application \"QuickTime Player\" to start (new audio recording)"
        case .movie:
            "tell application \"QuickTime Player\" to activate\ntell application \"QuickTime Player\" to start (new movie recording)"
        }
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
                process.waitUntilExit()
            } catch {
                return (Int32(-1), error.localizedDescription)
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
