import Foundation

@main
struct MenuTypeaheadTest {
    nonisolated(unsafe) static var failures = 0

    static func check(_ description: String, _ condition: Bool) {
        if condition {
            print("PASS  \(description)")
        } else {
            print("FAIL  \(description)")
            failures += 1
        }
    }

    static func main() {
        let titles = [
            "Open Application", "Add to Favorites", "Show in Finder", "Uninstall with Mole",
        ]
        check(
            "prefix selects uninstall",
            PaletteMenuTypeahead.bestMatch(query: "un", titles: titles) == 3)
        check(
            "matching is case insensitive",
            PaletteMenuTypeahead.bestMatch(query: "UN", titles: titles) == 3)
        check(
            "fuzzy initials select finder",
            PaletteMenuTypeahead.bestMatch(query: "sf", titles: titles) == 2)
        check(
            "unmatched query changes nothing",
            PaletteMenuTypeahead.bestMatch(query: "zzz", titles: titles) == nil)

        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        var buffer = PaletteMenuTypeaheadBuffer()
        buffer.append("u", at: start)
        buffer.append("n", at: start.addingTimeInterval(0.2))
        check("quick characters accumulate", buffer.query == "un")
        buffer.deleteLast()
        check("backspace edits the buffer", buffer.query == "u")
        buffer.append("s", at: start.addingTimeInterval(1.1))
        check("an expired buffer starts a new query", buffer.query == "s")
        buffer.reset()
        check("reset clears the buffer", buffer.query.isEmpty)

        print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
