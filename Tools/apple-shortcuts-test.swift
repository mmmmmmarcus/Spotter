import Foundation

@main
@MainActor
enum AppleShortcutsTests {
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { failures += 1; print("FAIL: \(message)") }
    }

    static func main() {
        let one = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let two = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let parsed = AppleShortcut.parseList("Zeta (\(one.uuidString))\nAlpha (\(two.uuidString))\nBad\nZeta (\(one.uuidString))\n")
        expect(parsed.map(\.name) == ["Alpha", "Zeta"], "parses, de-duplicates and sorts shortcuts")
        expect(parsed[1].entryID.hasPrefix(AppleShortcut.entryIDPrefix), "uses stable launcher identity")
        if failures == 0 { print("Apple Shortcuts tests passed") } else { exit(1) }
    }
}
