import Foundation

@main
struct SearchTests {
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

        let URLCases = [
            "hello world",
            "你好，世界",
            "search 🧭✨",
            "a & b? #tag 100%",
            "first line\nsecond line",
        ]
        for value in URLCases {
            let url = SearchURLBuilder.googleSearchURL(for: value)
            let decoded = (url.flatMap {
                URLComponents(url: $0, resolvingAgainstBaseURL: false)
            })?.queryItems?.first(where: { $0.name == "q" })?.value
            check("Google URL round-trips \(value.debugDescription)", decoded == value)
            check("Google URL uses HTTPS", url?.scheme == "https")
        }
        check("empty search is rejected", SearchURLBuilder.googleSearchURL(for: " \n\t ") == nil)
        let trimmedComponents = SearchURLBuilder.googleSearchURL(
            for: " \nkeep internal space\t "
        ).flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        let trimmedQuery = trimmedComponents?.queryItems?.first(where: { $0.name == "q" })?.value
        check("search trims only outer whitespace", trimmedQuery == "keep internal space")

        let idle = SelectionToolsResults.snapshot(state: .idle)
        check("an idle Search screen has no rows", idle.items.isEmpty)
        check("an idle Search screen says what to do", idle.emptyMessage.contains("Select text"))
        check("an idle Search screen is not an error", idle.errorMessage == nil)

        let failed = SelectionToolsResults.snapshot(
            state: .failed("The default browser could not open the Google Search URL."))
        check("a failed Search screen still has no rows", failed.items.isEmpty)
        check(
            "a failed Search screen reports the failure",
            failed.errorMessage == "The default browser could not open the Google Search URL.")
        check("a failed Search screen repeats it when empty", failed.emptyMessage == failed.errorMessage)

        print(failures == 0 ? "\nSearch: ALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
