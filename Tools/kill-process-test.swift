import Foundation

@main
struct KillProcessTests {
    static func main() {
        var failures = 0
        func check(_ message: String, _ value: @autoclosure () -> Bool) {
            if value() { print("PASS  \(message)") } else { failures += 1; print("FAIL  \(message)") }
        }

        let fixture = """
         120 1 8.5 2048 /Applications/Safari.app/Contents/MacOS/Safari
         121 120 4.0 1024 /Applications/Safari.app/Contents/Frameworks/Safari Helper
         220 1 2.0 4096 /usr/bin/example
         1 0 0.0 100 /sbin/launchd
        """
        let parsed = KillProcessEngine.parse(fixture)
        check("parser omits pid 1", parsed.count == 3)
        check("bundle exclusion", KillProcessEngine.parse(fixture, excludingBundlePath: "/Applications/Safari.app").map(\.id) == [220])
        check("app bundle is detected", parsed[0].appBundlePath == "/Applications/Safari.app")
        let grouped = KillProcessEngine.groupApplications(parsed)
        let safari = grouped.first { $0.appName == "Safari" }
        check("helpers are grouped", grouped.count == 2 && safari?.childProcessIDs == [121])
        check("usage is aggregated", safari?.cpu == 12.5 && safari?.memoryKB == 3072)
        let searched = KillProcessEngine.visible(parsed, query: "220", sort: .cpu, groupingApplications: true, searchPaths: false, searchPIDs: true, prioritizeApps: true)
        check("pid search", searched.map(\.id) == [220])

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
