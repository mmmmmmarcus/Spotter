import Foundation

@main
struct QuickTimeTests {
    static func main() {
        precondition(QuickTimeRecordingKind.allCases.count == 3)
        precondition(QuickTimeRecordingKind.screen.appleScript.lowercased().contains("screen recording"))
        precondition(QuickTimeRecordingKind.audio.appleScript.lowercased().contains("audio recording"))
        precondition(QuickTimeRecordingKind.movie.appleScript.lowercased().contains("movie recording"))
        precondition(QuickTimeRecordingKind.allCases.allSatisfy { $0.appleScript.contains("activate") })
        precondition(QuickTimeRecordingKind.allCases.allSatisfy { $0.appleScript.contains("System Events") })
        precondition(QuickTimeRecordingKind.allCases.allSatisfy { $0.appleScript.contains($0.title) })
        precondition(QuickTimeRecordingKind.allCases.allSatisfy { !$0.appleScript.contains("start (") })
        print("QuickTime Recording: ALL PASSED")
    }
}
