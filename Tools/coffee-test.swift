// Compile: swiftc -swift-version 6 Spotter/Plugins/Coffee/CoffeeTypes.swift Tools/coffee-test.swift -o /tmp/coffee-test && /tmp/coffee-test
import Foundation

@main
struct CoffeeTests {
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

        // Durations
        check("durations are ordered", CoffeeDuration.allCases.map(\.seconds) == [900, 1800, 3600, 7200, 14400, 28800])
        check("every duration has a title", CoffeeDuration.allCases.allSatisfy { !$0.title.isEmpty })
        check("raw values round-trip", CoffeeDuration.allCases.allSatisfy {
            CoffeeDuration(rawValue: $0.rawValue) == $0
        })

        // caffeinate arguments — an assertion flag is mandatory or the command does nothing.
        let display = CoffeeOptions(keepsDisplayAwake: true, keepsDiskAwake: false)
        check("idle assertion is always present", display.arguments(seconds: nil, pid: nil).contains("-i"))
        check("display flag maps to -d", display.arguments(seconds: nil, pid: nil).contains("-d"))
        check("disk flag is absent when off", !display.arguments(seconds: nil, pid: nil).contains("-m"))

        let all = CoffeeOptions(keepsDisplayAwake: true, keepsDiskAwake: true)
        check("disk flag maps to -m", all.arguments(seconds: nil, pid: nil).contains("-m"))

        let minimal = CoffeeOptions(keepsDisplayAwake: false, keepsDiskAwake: false)
        check("display flag absent when off", !minimal.arguments(seconds: nil, pid: nil).contains("-d"))
        check("minimal options still assert idle", minimal.arguments(seconds: nil, pid: nil) == ["-i"])

        let timed = display.arguments(seconds: 3600, pid: nil)
        check("duration maps to -t", timed.contains("-t"))
        check("duration passes seconds", timed.contains("3600"))

        let watched = display.arguments(seconds: nil, pid: 4242)
        check("watched pid maps to -w", watched.contains("-w"))
        check("watched pid is passed", watched.contains("4242"))

        // State
        check("off is not on", !CoffeeState.off.isOn)
        check("indefinite is on", CoffeeState.indefinite.isOn)
        check("timed is on", CoffeeState.until(Date()).isOn)
        check("app-scoped is on", CoffeeState.whileRunning(appName: "Xcode").isOn)
        check("off explains normal sleep", CoffeeState.off.summary.contains("sleep normally"))
        check("app-scoped names the app", CoffeeState.whileRunning(appName: "Xcode").summary.contains("Xcode"))
        check("menu title is short when off", CoffeeState.off.menuTitle == "Off")

        // Countdown formatting
        let now = Date(timeIntervalSince1970: 1_000_000)
        check("hours and minutes", CoffeeFormatter.remaining(until: now.addingTimeInterval(3900), now: now) == "1h 5m")
        check("minutes only", CoffeeFormatter.remaining(until: now.addingTimeInterval(720), now: now) == "12m")
        check("seconds only", CoffeeFormatter.remaining(until: now.addingTimeInterval(40), now: now) == "40s")
        check("an elapsed deadline reads zero", CoffeeFormatter.remaining(until: now.addingTimeInterval(-60), now: now) == "0s")

        print(failures == 0 ? "\nCoffee: ALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
