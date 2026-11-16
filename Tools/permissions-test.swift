import Foundation

@main
struct PermissionsTest {
    static func main() {
        var failures = 0

        func check(_ description: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS  \(description)")
            } else {
                print("FAIL  \(description)")
                failures += 1
            }
        }

        // MARK: - Automation status mapping

        check(
            "noErr is granted",
            PermissionsProbe.automationPermission(for: 0) == .granted)
        check(
            "errAEEventNotPermitted is denied",
            PermissionsProbe.automationPermission(for: -1743) == .denied)
        check(
            "errAEEventWouldRequireUserConsent has not been asked",
            PermissionsProbe.automationPermission(for: -1744) == .notDetermined)
        check(
            "procNotFound means the target is not running",
            PermissionsProbe.automationPermission(for: -600) == .targetNotRunning)
        // An unexpected status must stay unexpected: silently folding it into denied would invent a
        // permission problem, and folding it into granted would hide a real one.
        check(
            "an unexpected status is reported verbatim",
            PermissionsProbe.automationPermission(for: -1708) == .unknown(-1708))
        check(
            "a positive unexpected status is reported verbatim",
            PermissionsProbe.automationPermission(for: 42) == .unknown(42))

        check(
            "the mapping uses the measured constants",
            PermissionsProbe.automationGrantedStatus == 0
                && PermissionsProbe.automationDeniedStatus == -1743
                && PermissionsProbe.automationConsentStatus == -1744
                && PermissionsProbe.automationNotRunningStatus == -600)

        // MARK: - Automation targets

        check("every target Spotter drives is listed", AutomationTarget.all.count == 5)
        check(
            "the listed bundle identifiers are the ones Spotter sends events to",
            Set(AutomationTarget.all.map(\.bundleIdentifier)) == [
                "com.apple.finder", "com.apple.systemevents", "com.apple.Music",
                "com.apple.Terminal", "com.googlecode.iterm2"
            ])
        check(
            "no target is listed twice",
            Set(AutomationTarget.all.map(\.id)).count == AutomationTarget.all.count)
        check(
            "every target carries a glyph so the pane's two groups match",
            AutomationTarget.all.allSatisfy { !$0.symbolName.isEmpty })

        // MARK: - Screen Recording window probe

        let mine = 501
        let other = 777

        func window(layer: Int, pid: Int, name: String?) -> [String: Any] {
            var entry: [String: Any] = ["kCGWindowLayer": layer, "kCGWindowOwnerPID": pid]
            if let name { entry["kCGWindowName"] = name }
            return entry
        }

        check(
            "no windows at all is not a grant",
            PermissionsProbe.screenRecordingGranted(windows: [], ownProcessID: mine) == false)

        check(
            "a named layer-0 window owned by another process is a grant",
            PermissionsProbe.screenRecordingGranted(
                windows: [window(layer: 0, pid: other, name: "Untitled.txt")], ownProcessID: mine))

        // The value is legitimately empty for an untitled window: it is the key's presence that
        // macOS withholds without the grant, so testing for a non-empty string reads a healthy
        // install as denied.
        check(
            "an empty window name still counts, because the key is present",
            PermissionsProbe.screenRecordingGranted(
                windows: [window(layer: 0, pid: other, name: "")], ownProcessID: mine))

        check(
            "a layer-0 window with no name key is not a grant",
            PermissionsProbe.screenRecordingGranted(
                windows: [window(layer: 0, pid: other, name: nil)], ownProcessID: mine) == false)

        // WindowServer hands its own menu bar entries out unconditionally; they sit above layer 0.
        check(
            "a layer-24 Menubar entry is not a grant",
            PermissionsProbe.screenRecordingGranted(
                windows: [window(layer: 24, pid: other, name: "Menubar")], ownProcessID: mine)
                == false)

        check(
            "Spotter's own named window is not a grant",
            PermissionsProbe.screenRecordingGranted(
                windows: [window(layer: 0, pid: mine, name: "Spotter")], ownProcessID: mine)
                == false)

        check(
            "a real mix still finds the one qualifying window",
            PermissionsProbe.screenRecordingGranted(
                windows: [
                    window(layer: 24, pid: other, name: "Menubar"),
                    window(layer: 0, pid: mine, name: "Spotter"),
                    window(layer: 0, pid: other, name: nil),
                    window(layer: 0, pid: other, name: "Mail")
                ], ownProcessID: mine))

        check(
            "a mix with no qualifying window is not a grant",
            PermissionsProbe.screenRecordingGranted(
                windows: [
                    window(layer: 24, pid: other, name: "Menubar"),
                    window(layer: 3, pid: other, name: "Dock"),
                    window(layer: 0, pid: mine, name: "Spotter"),
                    window(layer: 0, pid: other, name: nil)
                ], ownProcessID: mine) == false)

        // A malformed entry must not crash the probe or be read as a grant.
        check(
            "an entry missing both keys is ignored",
            PermissionsProbe.screenRecordingGranted(
                windows: [["kCGWindowName": "Mail"]], ownProcessID: mine) == false)

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
