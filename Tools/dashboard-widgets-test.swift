import Foundation

@main
@MainActor
struct DashboardWidgetsTests {
    private static var failures = 0

    static func main() {
        let codexLine = #"{"timestamp":"2026-08-10T06:02:06.674Z","payload":{"rate_limits":{"primary":{"used_percent":24,"window_minutes":10080,"resets_at":1786933919},"secondary":null}}}"#
        let codex = DashboardWidgetsEngine.codexSessionUsage(from: Data(codexLine.utf8))
        check(codex?.primary?.usedPercent == 24, "Codex percent should decode")
        check(codex?.primary?.name == "7d", "Codex weekly window should be named 7d")
        check(codex?.source == .codexSession, "Codex source should identify session metadata")
        let noResetLine = #"{"timestamp":"2026-08-10T06:02:06Z","payload":{"rate_limits":{"primary":{"used_percent":24,"window_minutes":10080},"secondary":null}}}"#
        let noReset = DashboardWidgetsEngine.codexSessionUsage(from: Data(noResetLine.utf8))
        let codexCapturedAt = ISO8601DateFormatter().date(from: "2026-08-10T06:02:06Z")!
        check(
            noReset?.hasCurrentWindow(at: codexCapturedAt.addingTimeInterval(5 * 60 * 60)) == true,
            "no-reset metadata should remain current for six hours")
        check(
            noReset?.hasCurrentWindow(at: codexCapturedAt.addingTimeInterval(7 * 60 * 60)) == false,
            "no-reset metadata should expire instead of becoming a false zero")

        let history = #"""
        {
          "version": 1,
          "unscoped": [
            {"name":"session","windowMinutes":300,"entries":[{"capturedAt":"2026-08-10T04:00:00Z","resetsAt":"2026-08-10T09:00:00Z","usedPercent":31}]},
            {"name":"weekly","windowMinutes":10080,"entries":[{"capturedAt":"2026-08-10T04:01:00Z","resetsAt":"2026-08-15T09:00:00Z","usedPercent":47}]}
          ]
        }
        """#
        let claude = DashboardWidgetsEngine.codexBarHistoryUsage(
            from: Data(history.utf8), provider: "claude")
        check(claude?.primary?.name == "5h", "Claude session window should lead")
        check(claude?.secondary?.name == "7d", "Claude weekly window should follow")
        check(claude?.secondary?.usedPercent == 47, "Claude weekly percent should decode")
        check(
            claude?.hasCurrentWindow(at: Date(timeIntervalSince1970: 1_800_000_000)) == false,
            "expired reset windows should not be presented as current")

        let snapshot = #"""
        {
          "generatedAt":"2026-08-10T05:00:00Z",
          "entries":[{"provider":"claude","updatedAt":"2026-08-10T04:59:00Z","primary":{"usedPercent":12,"windowMinutes":300,"resetsAt":"2026-08-10T09:00:00Z"},"secondary":null}]
        }
        """#
        let cached = DashboardWidgetsEngine.codexBarSnapshotUsage(
            from: Data(snapshot.utf8), provider: "claude")
        check(cached?.primary?.usedPercent == 12, "CodexBar widget snapshot should decode")
        check(cached?.source == .codexBarSnapshot, "widget source should be identified")
        check(
            DashboardWidgetsEngine.preferredUsage([claude, cached])?.source
                == .codexBarSnapshot,
            "newest usage source should win")

        print(failures == 0 ? "Dashboard widgets tests passed" : "\(failures) test(s) failed")
        exit(failures == 0 ? 0 : 1)
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        }
    }
}
