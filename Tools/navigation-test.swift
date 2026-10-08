import Foundation

@main
enum NavigationTests {
    static func main() {
        let rows = [
            NavigationResult(id: "1", title: "Document", subtitle: "File → Open", appName: "Notes", bundlePath: nil, processIdentifier: 1, locator: []),
            NavigationResult(id: "2", title: "Settings", subtitle: "", appName: "Safari", bundlePath: nil, processIdentifier: 2, locator: []),
        ]
        precondition(NavigationResults.matching(rows, query: "notes").map(\.id) == ["1"])
        precondition(NavigationResults.matching(rows, query: "open").map(\.id) == ["1"])
        precondition(NavigationResults.matching(rows, query: "").count == 2)
        precondition(NavigationResults.windowIndex(locator: ["1", "Document"],
            titles: ["Document", "Document"]) == 1)
        precondition(NavigationResults.windowIndex(locator: ["9", "Document"],
            titles: ["Document", "Other"]) == 0)
        print("Navigation tests passed")
    }
}
