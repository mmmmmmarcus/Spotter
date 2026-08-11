import Foundation

@main
struct SelectionToolsTests {
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

        do {
            let request = GoogleTranslationRequest(q: "你好 & hello", target: "en")
            let data = try JSONEncoder().encode(request)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: String]
            check("translation request preserves text", json?["q"] == "你好 & hello")
            check("translation request carries one target", json?["target"] == "en")
            check("translation request declares plain text", json?["format"] == "text")
        } catch {
            failures += 1
            print("FAIL  translation request encodes: \(error)")
        }

        do {
            let data = Data(
                #"{"data":{"translations":[{"detectedSourceLanguage":"en","translatedText":"你好"}]}}"#.utf8)
            let response = try JSONDecoder().decode(GoogleTranslationResponse.self, from: data)
            check(
                "translation response decodes detected language",
                response.data.translations.first?.detectedSourceLanguage == "en")
            check(
                "translation response decodes translated text",
                response.data.translations.first?.translatedText == "你好")
        } catch {
            failures += 1
            print("FAIL  translation response decodes: \(error)")
        }

        do {
            let data = Data(#"{"error":{"message":"API key not valid"}}"#.utf8)
            let response = try JSONDecoder().decode(GoogleTranslationErrorResponse.self, from: data)
            check("translation API errors retain provider detail", response.error?.message == "API key not valid")
        } catch {
            failures += 1
            print("FAIL  translation error decodes: \(error)")
        }

        let translation = SelectionTranslation(
            original: "Hello", chinese: "你好", english: "Hello",
            detectedSourceLanguage: "en")
        let snapshot = SelectionToolsResults.snapshot(state: .translated(translation))
        check(
            "translation rows stay original, Chinese, English",
            snapshot.items.map(\.id) == ["original", "chinese", "english"])
        check(
            "translation rows carry the expected text",
            snapshot.items.map(\.title) == ["Hello", "你好", "Hello"])
        check(
            "every completed row is copyable",
            snapshot.items.allSatisfy { $0.primaryActionTitle.hasPrefix("Copy ") })

        let loading = SelectionToolsResults.snapshot(state: .loading("Source"))
        check("loading reserves exactly three rows", loading.items.count == 3)
        check("loading keeps the original immediately copyable", loading.items.first?.title == "Source")

        let filtered = SelectionToolsResults.snapshot(
            state: .translated(translation), query: "Chinese")
        check("translation rows can be filtered by language", filtered.items.map(\.id) == ["chinese"])

        check(
            "disabled translation explains how to enable it",
            GoogleTranslationError.disabled.localizedDescription.contains("Selection Tools settings"))

        print(failures == 0 ? "\nSelection Tools: ALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
