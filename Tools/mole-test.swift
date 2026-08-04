// Compile: swiftc -swift-version 6 Spotter/Plugins/Mole/MoleTypes.swift Tools/mole-test.swift -o /tmp/mole-test && /tmp/mole-test
import Foundation

@main
struct MoleTests {
    static func main() {
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
        check("only status and history render in the palette",
            MoleCommand.allCases.filter(\.rendersInPalette).map(\.rawValue).sorted()
                == ["history", "status"])
        check("clean stays a terminal hand-off", !MoleCommand.clean.rendersInPalette)
        check("uninstall stays a terminal hand-off", !MoleCommand.uninstall.rendersInPalette)

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

        // Formatting
        check("bytes scale to GB", MoleParser.bytes(75561043616) == "70.4 GB")
        check("small byte counts stay bytes", MoleParser.bytes(512) == "512 B")
        check("percent rounds", MoleParser.percent(82.16) == "82%")
        check("percent clamps above 100", MoleParser.percent(140) == "100%")
        check("percent clamps below zero", MoleParser.percent(-5) == "0%")

        print(failures == 0 ? "\nMole: ALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
