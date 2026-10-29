import Foundation

extension ExtensionTests {
    @MainActor
    static func keepAwakeChecks() async {
        check("coffee duration in seconds", ExtensionKeepAwakeProcess.duration(arguments: ["-u", "-d", "-i", "-t", "3600"]) == 3600)
        check("Coffee combined assertion flags retain duration", ExtensionKeepAwakeProcess.duration(arguments: ["-u", "-dmi", "-t", "3600"]) == 3600)
        for args in [["-t"], ["-t", "nan"], ["-t", "inf"], ["-t", "1e200"], ["-t", "-1"], ["-t", "0"], ["-t", "0.5"], ["-t", "10", "/usr/bin/true"], ["-w", "42"], ["-i"]] {
            check("unknown or indefinite duration has no invented countdown", ExtensionKeepAwakeProcess.duration(arguments: args) == nil)
        }
        let suite = "com.spotter.tests.coffee.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let rows = BackgroundTaskStore(defaults: defaults)
        let tracker = ExtensionKeepAwake(tasks: rows, defaults: defaults)
        let host = StubHost()
        let recorder = Recorder()
        let runtime = ExtensionRuntime(hostAPI: host, runtimeURL: runtimeURL(), onKeepAwake: { process in
            Task { @MainActor in tracker.track(process) }
        })
        runtime.setDelegate(recorder)
        defer { runtime.shutdown(); tracker.stop() }
        try? await runtime.boot(config: .current(supportDirectory: FileManager.default.temporaryDirectory))
        let code = """
            const { spawn } = require('node:child_process');
            module.exports.default = async function() {
                spawn('/usr/bin/caffeinate', ['-u', '-dmi', '-t', '30'], { detached: true, stdio: 'ignore' }).unref();
            };
            """
        await runtime.start(session: "coffee-test", code: code,
                            file: URL(fileURLWithPath: "/tmp/coffee-test.js"), mode: .noView,
                            context: launchContext(extensionName: "coffee", mode: .noView))
        await settle(200)
        check("detached Coffee launch reaches native tasks", rows.tasks.count == 1, recorder.failures.joined(separator: "; "))
        guard let row = rows.tasks.first,
              let data = defaults.data(forKey: "raycast-extensions.keep-awake-processes"),
              let saved = try? JSONDecoder().decode([ExtensionKeepAwakeProcess].self, from: data),
              let process = saved.first else { return }
        check("Coffee row exposes cancellation", rows.canCancel(id: row.id))
        check("Coffee row starts live with countdown", row.state == .running && row.detail.contains("remaining"))
        check("Coffee countdown advances", process.detail(now: process.startedAt.addingTimeInterval(10)).contains("20s"))
        check("Coffee progress uses duration", abs((process.progress(now: process.startedAt.addingTimeInterval(15)) ?? -1) - 0.5) < 0.001)
        tracker.track(process)
        check("repeated observation never duplicates task", rows.tasks.count == 1)
        await runtime.stop(session: "coffee-test")
        runtime.shutdown()
        await settle(100)
        check("closing runtime preserves keep-awake process", process.isRunning)

        let restoredRows = BackgroundTaskStore(defaults: defaults)
        let restored = ExtensionKeepAwake(tasks: restoredRows, defaults: defaults)
        restored.restore()
        restored.restore()
        check("relaunch restores one cancellable task with same ID", restoredRows.tasks.count == 1 && restoredRows.tasks.first?.id == row.id && restoredRows.canCancel(id: row.id))
        let foreign = Process()
        foreign.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        foreign.arguments = ["-i", "-t", "30"]
        try? foreign.run()
        defer { if foreign.isRunning { foreign.terminate() } }
        let stale = ExtensionKeepAwakeProcess(id: UUID(), pid: process.pid,
            startSeconds: process.startSeconds + 1, startMicroseconds: process.startMicroseconds,
            extensionName: "coffee", extensionTitle: "Coffee", startedAt: Date(), duration: 30)
        check("stale process identity cannot target a reused PID", !stale.isRunning && stale.stop() && process.isRunning)
        check("Cancel reaches executor", restoredRows.cancel(id: row.id))
        await settle(250)
        restored.refresh()
        tracker.refresh()
        check("Cancel actually terminates the Coffee process", !process.isRunning)
        check("Cancel leaves unrelated caffeinate alone", foreign.isRunning)
        check("stopped row becomes Done only after exit", restoredRows.tasks.first?.state == .done && restoredRows.tasks.first?.detail == "Stopped keeping Mac awake.")
        check("completed row cannot be cancelled again", !restoredRows.canCancel(id: row.id))
        let expiredRows = BackgroundTaskStore(defaults: defaults)
        let expired = ExtensionKeepAwake(tasks: expiredRows, defaults: defaults)
        defaults.set(data, forKey: "raycast-extensions.keep-awake-processes")
        expired.restore()
        check("relaunch drops dead saved processes", expiredRows.tasks.isEmpty)

        func child(seconds: Int) -> Process? {
            let child = Process()
            child.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
            child.arguments = ["-i", "-t", "\(seconds)"]
            do { try child.run(); return child } catch { check("test child starts", false); return nil }
        }
        if let timed = child(seconds: 1),
           let record = ExtensionKeepAwakeProcess.capture(pid: timed.processIdentifier, name: "coffee", title: "Coffee", arguments: ["-i", "-t", "1"]) {
            tracker.track(record)
            await settle(1300)
            tracker.refresh()
            check("natural expiry clears running state", !record.isRunning && rows.tasks.first(where: { $0.id == record.id })?.state == .done)
        }
        for removing in [false, true] {
            if let live = child(seconds: 30),
               let record = ExtensionKeepAwakeProcess.capture(pid: live.processIdentifier, name: "coffee", title: "Coffee", arguments: ["-i", "-t", "30"]) {
                if removing { tracker.remove(extensionName: "coffee") } else { tracker.setEnabled(false) }
                tracker.track(record)
                await settle(200)
                tracker.refresh()
                check("late launch is stopped after disable or uninstall", !record.isRunning)
                tracker.setEnabled(true)
                tracker.synchronize(installed: ["coffee"])
            }
        }
        check("own process is not a caffeinate target", ExtensionKeepAwakeProcess.capture(pid: ProcessInfo.processInfo.processIdentifier, name: "fixture", title: "Fixture", arguments: []) == nil)
    }
}
