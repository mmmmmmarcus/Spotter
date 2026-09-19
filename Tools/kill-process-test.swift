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

        check("kill parses an application argument", KillProcessEngine.applicationArgument("kill Chrome") == "Chrome")
        check("kill accepts casing and multiword names", KillProcessEngine.applicationArgument("  KILL  Google Chrome  ") == "Google Chrome")
        for query in ["kill", "kill   ", "killall Chrome", "Q Chrome", "skill Chrome", "Chrome", String(repeating: "k", count: 257)] {
            check("reject unrelated or incomplete query: \(query.prefix(24))", KillProcessEngine.applicationArgument(query) == nil)
        }
        let apps = KillProcessEngine.parse("""
         10 1 0 0 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome
         20 1 0 0 /Applications/Safari.app/Contents/MacOS/Safari
         30 1 0 0 /Applications/Safari Technology Preview.app/Contents/MacOS/Safari Technology Preview
         40 1 0 0 /Applications/Spotter.app/Contents/MacOS/Spotter
         50 1 0 0 /usr/bin/Chrome
        """)
        func target(_ argument: String, in source: [RunningProcessInfo]? = nil) -> Int32? {
            KillProcessEngine.applicationTarget(in: source ?? apps, argument: argument, excludingPID: 40)?.id
        }
        check("Chrome resolves a running Google Chrome", target("chrome") == 10)
        check("partial application name works", target("Chro") == 10)
        check("exact name outranks variants", target("Safari") == 20)
        check("full variant name selects that variant", target("Safari Technology") == 30)
        check("matching is independent of process order", target("Safari", in: Array(apps.reversed())) == 20)
        check("Spotter is excluded", target("Spotter") == nil)
        check("missing application produces no target", target("Firefox") == nil)
        check("empty argument produces no target", target("") == nil)
        check("exited application cannot retarget a binary", target("Chrome", in: apps.filter { $0.id != 10 }) == nil)

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
