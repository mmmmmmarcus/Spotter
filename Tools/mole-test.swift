// Compile with `MoleTypes.swift` and `MoleProcessRunner.swift`; see docs/development.md.
import Foundation

private final class MoleOutputRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []

    func append(_ data: Data) {
        lock.withLock { values.append(String(decoding: data, as: UTF8.self)) }
    }

    var snapshots: [String] {
        lock.withLock { values }
    }
}

@main
struct MoleTests {
    static func main() async {
        var failures = 0
        func check(_ message: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS  \(message)")
            } else {
                failures += 1
                print("FAIL  \(message)")
            }
        }

        // Catalog
        check("every command has a title", MoleCommand.allCases.allSatisfy { !$0.title.isEmpty })
        check(
            "command ids are unique",
            Set(MoleCommand.allCases.map(\.commandID)).count == MoleCommand.allCases.count)
        check("clean opens the clean screen", MoleCommand.clean.screen == .clean)
        check("uninstall opens the uninstall screen", MoleCommand.uninstall.screen == .uninstall)
        check("the installer selector renders in the palette too", MoleCommand.installer.screen == .installer)
        check(
            "every screen is reachable from a command",
            Set(MoleCommand.allCases.map(\.screen)) == Set(MoleScreen.allCases))

        // Actions — the destructive surface, and how each one is spelled on the command line.
        check("clean runs without --dry-run", MoleAction.clean.arguments == ["clean"])
        check(
            "uninstall passes the app name",
            MoleAction.uninstall(name: "Slack", permanent: false).arguments
                == ["uninstall", "Slack"])
        check(
            "permanent uninstall bypasses the Trash",
            MoleAction.uninstall(name: "Slack", permanent: true).arguments
                == ["uninstall", "--permanent", "Slack"])
        check("a Trash uninstall is recoverable, so not flagged permanent",
            !MoleAction.uninstall(name: "Slack", permanent: false).isPermanent)
        check("purge is irreversible", MoleAction.purge.isPermanent)
        check("clean is not flagged irreversible", !MoleAction.clean.isPermanent)
        check(
            "every action names what it removes",
            [MoleAction.clean, .optimize, .purge, .uninstall(name: "X", permanent: true)]
                .allSatisfy { !$0.confirmation.isEmpty && !$0.title.isEmpty })
        check("each action refreshes its own screen", MoleAction.purge.screen == .purge)

        // Preview arguments — the read-only pass behind each screen.
        check("clean previews with --dry-run",
            MoleScreen.clean.previewArguments == ["clean", "--dry-run"])
        check("history asks for JSON", MoleScreen.history.previewArguments == ["history", "--json"])
        check("uninstall lists apps", MoleScreen.uninstall.previewArguments == ["uninstall", "--list"])
        check("the menu fetches nothing", MoleScreen.menu.previewArguments == nil)
        check("analyze builds its own arguments", MoleScreen.analyze.previewArguments == nil)
        check("the installer screen never invokes Mole", MoleScreen.installer.previewArguments == nil)

        // Installer scan rules — Mole's own, mirrored exactly.
        check("dmg is a direct installer", MoleInstallerScan.isDirectInstaller("Foo.dmg"))
        check("case-insensitive extensions", MoleInstallerScan.isDirectInstaller("Foo.PKG"))
        check("mpkg, iso and xip count", ["a.mpkg", "b.iso", "c.xip"].allSatisfy(MoleInstallerScan.isDirectInstaller))
        check("zip is not direct", !MoleInstallerScan.isDirectInstaller("Foo.zip"))
        check("zip detection", MoleInstallerScan.isZip("Foo.zip") && !MoleInstallerScan.isZip("Foo.dmg"))
        check("plain files never count", !MoleInstallerScan.isDirectInstaller("notes.txt"))
        check(
            "a zip holding an app is an installer",
            MoleInstallerScan.zipListingSuggestsInstaller(["Foo.app/Contents/Info.plist"]))
        check(
            "a zip holding a nested pkg is an installer",
            MoleInstallerScan.zipListingSuggestsInstaller(["payload/Install Me.pkg"]))
        check(
            "a zip of documents is not",
            !MoleInstallerScan.zipListingSuggestsInstaller(["report.pdf", "images/shot.png"]))
        check(
            "an app-named file without the suffix as component is not",
            !MoleInstallerScan.zipListingSuggestsInstaller(["myapp.txt"]))
        check("scan depth matches Mole", MoleInstallerScan.maxDepth == 2)
        let roots = MoleInstallerScan.roots(home: "/Users/x")
        check("scan roots start at Downloads", roots.first == "/Users/x/Downloads")
        check("scan roots match Mole's list", roots.count == 11 && roots.contains("/Users/Shared/Downloads"))
        check(
            "no preview mutates anything",
            MoleScreen.allCases.compactMap(\.previewArguments).allSatisfy { arguments in
                let verb = arguments[0]
                return verb == "status" || verb == "history" || arguments.contains("--dry-run")
                    || arguments.contains("--list")
            })

        // Status parsing — the real shape `mole status` emits on a non-TTY.
        let statusJSON = """
        {"host":"Mac","uptime":"4d 13h","procs":628,"health_score":92,
         "health_score_msg":"Excellent",
         "hardware":{"model":"MacBook Pro","cpu_model":"Apple M4","total_ram":"16.0 GB",
                     "os_version":"macOS 26.5.2"},
         "cpu":{"usage":22.9,"core_count":10},
         "memory":{"used":13473972224,"total":17179869184,"used_percent":78.4},
         "disks":[{"mount":"/","used":406229131317,"total":494384795648,"used_percent":82.1}],
         "trash_size":75561043616}
        """.data(using: .utf8)!

        guard let status = MoleParser.parseStatus(statusJSON) else {
            print("FAIL  status parses")
            exit(1)
        }
        check("status reads the health score", status.healthScore == 92)
        check("status reads the health message", status.healthMessage == "Excellent")
        check("status surfaces a CPU row", status.rows.contains { $0.title == "CPU" })
        check("CPU row shows a rounded percent", status.rows.first { $0.title == "CPU" }?.value == "23%")
        check("status surfaces a Memory row", status.rows.contains { $0.title == "Memory" })
        check("status surfaces the mounted disk", status.rows.contains { $0.title == "Disk /" })
        check("status surfaces trash when non-empty", status.rows.contains { $0.title == "Trash" })
        check("status surfaces uptime", status.rows.contains { $0.title == "Uptime" })

        // Trash is omitted rather than shown as zero.
        let noTrash = """
        {"health_score":100,"health_score_msg":"Great","trash_size":0}
        """.data(using: .utf8)!
        check(
            "empty trash is not listed",
            MoleParser.parseStatus(noTrash)?.rows.contains { $0.title == "Trash" } == false)

        check("malformed status returns nil", MoleParser.parseStatus(Data("nope".utf8)) == nil)

        // History parsing
        let historyJSON = """
        {"limit":20,"sessions":[
          {"command":"clean","started_at":"2026-08-04 21:41:57","ended_at":"","items":12,
           "size":"1.2GB","operation_count":3,"failed_tasks":1},
          {"command":"optimize","started_at":"2026-08-03 10:00:00","items":0,"size":"0B",
           "failed_tasks":0}],
         "deletions":[]}
        """.data(using: .utf8)!
        let history = MoleParser.parseHistory(historyJSON)
        check("history reads every session", history.count == 2)
        check("history keeps the command", history.first?.command == "clean")
        check("history keeps the size", history.first?.size == "1.2GB")
        check("history keeps failures", history.first?.failedTasks == 1)
        check("history tolerates a missing ended_at", history.last?.command == "optimize")
        check("empty history is not an error", MoleParser.parseHistory(
            Data(#"{"sessions":[]}"#.utf8)).isEmpty)
        check("malformed history is empty", MoleParser.parseHistory(Data("nope".utf8)).isEmpty)

        // ANSI stripping — Mole colors everything and redraws lines in place.
        check(
            "colour codes are removed",
            MoleParser.stripANSI("\u{1B}[0;33m→\u{1B}[0m User app cache") == "→ User app cache")
        check(
            "cursor moves are removed",
            MoleParser.stripANSI("\u{1B}[H\u{1B}[2KSelect") == "Select")
        check(
            "a carriage return becomes a line break",
            MoleParser.stripANSI("a\rb") == "a\nb")
        check("plain text is untouched", MoleParser.stripANSI("plain") == "plain")

        // Clean / optimize report parsing — sectioned plain text, not JSON.
        let cleanText = """
        \u{1B}[1;35mClean Your Mac\u{1B}[0m

        \u{1B}[0;33m→ DRY RUN MODE\u{1B}[0m, Preview only

        \u{1B}[1;35m➤ User essentials\u{1B}[0m
          \u{1B}[0;33m→\u{1B}[0m User app cache\u{1B}[0m · 108 items, \u{1B}[0;31m13.35GB\u{1B}[0m dry
          \u{1B}[0;33m→\u{1B}[0m Trash · would empty, 106 items

        ➤ Browsers
          → Chrome cache · 2 items, 1.84GB dry

        Potential space: 21.3GB | Items: 402 | Categories: 51
        Free space: 35.57GB
        """
        let report = MoleParser.parseReport(cleanText)
        check("report keeps every item", report.items.count == 3)
        check("report keeps the first title", report.items.first?.title == "User app cache")
        check("report keeps the detail", report.items.first?.detail == "108 items, 13.35GB dry")
        check("report assigns the section", report.items.first?.section == "User essentials")
        check("report tracks a section change", report.items.last?.section == "Browsers")
        check("report drops the banner", !report.items.contains { $0.title.contains("DRY RUN") })
        check("report captures the summary", report.summary.count == 2)
        check(
            "report captures potential space",
            report.summary.first?.hasPrefix("Potential space:") == true)
        check("an empty report is empty", MoleParser.parseReport("").isEmpty)

        // Optimize items have no `·` separator, use ✓ / ⊙ markers, and head some groups
        // with a bare all-caps line instead of the ➤ marker.
        let optimizeText = """
        PERFORMANCE DIAGNOSIS
          ✓ No sustained high-CPU bottleneck detected
        ➤ DNS & Spotlight Check
          ✓ DNS cache flushed
          → Spotlight index verified
          ⊙ pnpm store · 1.94GB · ~/Library/pnpm/store
        Use mo clean --whitelist to add protection rules
        Dry Run Complete, No Changes Made
        """
        let optimize = MoleParser.parseReport(optimizeText)
        check("every marker counts as an item", optimize.items.count == 4)
        check("an all-caps line becomes a section",
            optimize.items.first?.section == "PERFORMANCE DIAGNOSIS")
        check("an item without a separator keeps its whole title",
            optimize.items.first?.title == "No sustained high-CPU bottleneck detected")
        check("an item without a separator has no detail", optimize.items.first?.detail == "")
        check("a ➤ header still wins after an all-caps one",
            optimize.items.last?.section == "DNS & Spotlight Check")
        check("the suggestion marker keeps its detail",
            optimize.items.last?.detail == "1.94GB · ~/Library/pnpm/store")
        check("closing hints are not summary lines", optimize.summary == ["Dry Run Complete, No Changes Made"])

        // Purge parsing
        let purgeText = """
        → DRY RUN MODE, No project artifacts will be removed

        ✓ [DRY RUN] ~/GitHub/EraseVideo/node_modules, 1.19GB
        ✓ [DRY RUN] ~/GitHub/a, b/build, 702.4MB
        ✓ ~/GitHub/done/dist, 10.0MB
        not a purge line
        """
        let purge = MoleParser.parsePurge(purgeText)
        check("purge reads every directory", purge.count == 3)
        check("purge strips the dry-run marker", purge.first?.path == "~/GitHub/EraseVideo/node_modules")
        check("purge keeps the size", purge.first?.size == "1.19GB")
        check("a path containing a comma splits on the last one", purge[1].path == "~/GitHub/a, b/build")
        check("a real run has no marker to strip", purge.last?.path == "~/GitHub/done/dist")
        check("non-matching lines are ignored", MoleParser.parsePurge("hello").isEmpty)

        // App list parsing
        let appsJSON = """
        [
          {"name": "Cursor", "bundle_id": "com.todesktop.x", "source": "App",
           "uninstall_name": "Cursor", "path": "/Applications/Cursor.app", "size": "559.5MB"},
          {"name": "No Token", "bundle_id": "com.x", "path": "/Applications/X.app"}
        ]
        """.data(using: .utf8)!
        let apps = MoleParser.parseApps(appsJSON)
        check("apps drop rows with no uninstall token", apps.count == 1)
        check("apps keep the display name", apps.first?.name == "Cursor")
        check("apps keep the uninstall token", apps.first?.uninstallName == "Cursor")
        check("apps keep the size", apps.first?.size == "559.5MB")
        check("malformed app list is empty", MoleParser.parseApps(Data("nope".utf8)).isEmpty)

        // Disk analysis parsing
        let analysisJSON = """
        {"path": "/Users/me/Documents", "overview": false, "entries": [
          {"name": "Codex", "path": "/Users/me/Documents/Codex", "size": 808747898, "is_dir": true},
          {"name": "note.txt", "path": "/Users/me/Documents/note.txt", "size": 12}
        ]}
        """.data(using: .utf8)!
        let analysis = MoleParser.parseAnalysis(analysisJSON)
        check("analysis keeps the root path", analysis?.path == "/Users/me/Documents")
        check("analysis keeps every entry", analysis?.entries.count == 2)
        check("analysis marks directories", analysis?.entries.first?.isDirectory == true)
        check("a missing is_dir reads as a file", analysis?.entries.last?.isDirectory == false)
        check("analysis keeps the size", analysis?.entries.first?.size == 808747898)
        check("malformed analysis returns nil", MoleParser.parseAnalysis(Data("nope".utf8)) == nil)

        // Formatting
        check("bytes scale to GB", MoleParser.bytes(75561043616) == "70.4 GB")
        check("small byte counts stay bytes", MoleParser.bytes(512) == "512 B")
        check("percent rounds", MoleParser.percent(82.16) == "82%")
        check("percent clamps above 100", MoleParser.percent(140) == "100%")
        check("percent clamps below zero", MoleParser.percent(-5) == "0%")

        // Process runner — cancellation must stop an expensive preview instead of orphaning it.
        let start = ContinuousClock.now
        let scan = Task {
            await MoleProcessRunner.capture(path: "/bin/sleep", arguments: ["10"])
        }
        try? await Task.sleep(for: .milliseconds(100))
        scan.cancel()
        let cancelled = await scan.value
        check(
            "cancelling a preview interrupts the process",
            ifCaseFailure(cancelled) && start.duration(to: .now) < .seconds(2))

        let environment = await MoleProcessRunner.capture(
            path: "/bin/sh", arguments: ["-c", "printf %s \"$MO_NO_OPLOG\""],
            environment: ["MO_NO_OPLOG": "1"])
        check("preview environment reaches Mole", successText(environment) == "1")

        let output = MoleOutputRecorder()
        _ = await MoleProcessRunner.capture(
            path: "/bin/sh", arguments: ["-c", "printf first; sleep 0.3; printf second"],
            onOutput: { output.append($0) })
        check("preview output streams before completion", output.snapshots.first == "first")
        check("the final streamed snapshot is complete", output.snapshots.last == "firstsecond")

        print(failures == 0 ? "\nMole: ALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    private static func ifCaseFailure(_ result: Result<Data, MoleRunError>) -> Bool {
        if case .failure = result { return true }
        return false
    }

    private static func successText(_ result: Result<Data, MoleRunError>) -> String? {
        guard case .success(let data) = result else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
