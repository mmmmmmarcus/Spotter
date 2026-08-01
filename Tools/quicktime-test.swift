import Foundation

@main
struct QuickTimeTests {
    static func main() {
        precondition(QuickTimeRecordingKind.allCases.count == 3)
        precondition(QuickTimeRecordingKind.screen.appleScript.contains("screen recording"))
        precondition(QuickTimeRecordingKind.audio.appleScript.contains("audio recording"))
        precondition(QuickTimeRecordingKind.movie.appleScript.contains("movie recording"))
        print("QuickTime Recording: ALL PASSED")
    }
}
