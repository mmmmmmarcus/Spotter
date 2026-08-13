import Foundation

@main
struct AppVersionTests {
    static func main() {
        var failures = 0

        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            if condition() {
                print("PASS  \(message)")
            } else {
                failures += 1
                print("FAIL  \(message)")
            }
        }

        let version = AppVersion(short: "1.4.13-dev", build: "7")
        check(version.short == "1.4.13-dev", "launcher label keeps the channel-aware version")
        check(version.aboutLabel == "Version 1.4.13-dev (7)", "About includes the build number")

        let missing = AppVersion(short: "  ", build: nil)
        check(missing.short == "—", "missing short version has a safe fallback")
        check(missing.aboutLabel == "Version — (—)", "missing build has a safe fallback")

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
