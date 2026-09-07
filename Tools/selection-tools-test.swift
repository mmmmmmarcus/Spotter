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

        check(
            "the default targets resolve",
            TranslationLanguages.targets(for: TranslationLanguages.defaultTargetCodes).map(\.code)
                == ["zh-CN", "en"])
        check(
            "unknown target codes are dropped",
            TranslationLanguages.targets(for: ["ja", "klingon", "ja"]).map(\.code) == ["ja"])
        check("known codes name themselves", TranslationLanguages.name(for: "ja") == "Japanese")
        check("unknown codes fall back to the code", TranslationLanguages.name(for: "xx") == "xx")

        check(
            "an English target is skipped for English",
            TranslationLanguages.isSameLanguage(target: "en", as: "en"))
        check(
            "a regional source still matches its target",
            TranslationLanguages.isSameLanguage(target: "pt", as: "pt-BR"))
        check(
            "Simplified and Traditional stay separate translations",
            !TranslationLanguages.isSameLanguage(target: "zh-TW", as: "zh-CN"))
        check(
            "a detector's zh-Hans is Google's zh-CN",
            TranslationLanguages.isSameLanguage(target: "zh-CN", as: "zh-Hans"))
        check(
            "different languages are never skipped",
            !TranslationLanguages.isSameLanguage(target: "ja", as: "en"))

        check(
            "undetected text is treated as English",
            TranslationLanguages.normalizedSource(nil) == "en")
        check(
            "a detected script maps onto the target table",
            TranslationLanguages.normalizedSource("zh-Hant") == "zh-TW")
        check(
            "Hebrew keeps Google's spelling",
            TranslationLanguages.normalizedSource("he") == "iw")

        let translation = SelectionTranslation(
            original: "Hello", sourceLanguage: "en",
            rows: [
                SelectionTranslationRow(code: "zh-CN", name: "Chinese (Simplified)", text: "你好"),
                SelectionTranslationRow(code: "ja", name: "Japanese", text: "こんにちは"),
            ])
        let snapshot = SelectionToolsResults.snapshot(
            screen: .selection, state: .translated(translation))
        check(
            "every translation leads and the original comes last",
            snapshot.items.map(\.id) == ["zh-CN", "ja", "original"])
        check(
            "translation rows carry the expected text",
            snapshot.items.map(\.title) == ["你好", "こんにちは", "Hello"])
        check(
            "the original names the detected language",
            snapshot.items.last?.subtitle == "Original · English")
        check(
            "every completed row is copyable",
            snapshot.items.allSatisfy { $0.primaryActionTitle.hasPrefix("Copy ") })
        check(
            "a long translation is never truncated",
            snapshot.items.allSatisfy { $0.titleLineLimit == nil })

        let loading = SelectionToolsResults.snapshot(
            screen: .selection,
            state: .loading(
                original: "Source", targets: TranslationLanguages.targets(for: ["ja"])))
        check(
            "loading reserves each target ahead of the original",
            loading.items.map(\.id) == ["ja", "original"])
        check("loading keeps the original immediately copyable", loading.items.last?.title == "Source")

        let filtered = SelectionToolsResults.snapshot(
            screen: .selection, state: .translated(translation), query: "Japanese")
        check("translation rows can be filtered by language", filtered.items.map(\.id) == ["ja"])

        let pageTargets = TranslationLanguages.targets(for: ["ja", "fr"])
        func page(
            _ state: SelectionToolsState, _ query: String, hasAPIKey: Bool = true,
            targets: [TranslationLanguage]? = nil
        ) -> PluginPaletteSnapshot {
            SelectionToolsResults.snapshot(
                screen: .compose, state: state, query: query,
                targets: targets ?? pageTargets, hasAPIKey: hasAPIKey)
        }

        let noKey = page(.idle, "Hello", hasAPIKey: false)
        check("the Translate page offers no row without a key", noKey.items.isEmpty)
        check(
            "the Translate page names the missing key",
            noKey.errorMessage == GoogleTranslationError.missingAPIKey.localizedDescription)
        check(
            "a missing key is never assumed away",
            SelectionToolsResults.snapshot(screen: .compose, state: .idle, query: "Hello")
                .items.isEmpty)
        let noTargets = page(.idle, "Hello", targets: [])
        check("the Translate page offers no row without a target", noTargets.items.isEmpty)
        check(
            "the Translate page names the empty target list",
            noTargets.errorMessage == GoogleTranslationError.noTargets.localizedDescription)

        let untyped = page(.idle, "   \n ")
        check("an empty Translate page has nothing to activate", untyped.items.isEmpty)
        check(
            "an empty Translate page says how to use it",
            untyped.emptyMessage == "Type text to translate, then press ↵")

        let ready = page(.idle, " Hello ")
        check("typed text offers exactly one action row", ready.items.count == 1)
        check(
            "the action row is the only thing that spends a request",
            ready.items.first?.id == "translate-action")
        check(
            "the action row names the configured targets",
            ready.items.first?.subtitle == "Into Japanese, French")
        check("the action row reads as an action", ready.items.first?.primaryActionTitle == "Translate")

        check(
            "the Translate page shows pending rows for the text it is translating",
            page(.loading(original: "Hello", targets: pageTargets), "Hello").items.map(\.id)
                == ["ja", "fr"])
        check(
            "the typed text itself is never repeated as a row",
            page(.loading(original: "Hello", targets: pageTargets), "Hello").items
                .allSatisfy { $0.id != "original" })
        let answered = page(
            .translated(
                SelectionTranslation(
                    original: "Hello", sourceLanguage: "en",
                    rows: [
                        SelectionTranslationRow(code: "ja", name: "Japanese", text: "こんにちは"),
                        SelectionTranslationRow(code: "fr", name: "French", text: "Bonjour"),
                    ])),
            "Hello")
        check("the Translate page lists one row per target", answered.items.map(\.id) == ["ja", "fr"])
        check(
            "the Translate page's rows are copyable",
            answered.items.allSatisfy { $0.primaryActionTitle.hasPrefix("Copy ") })
        let edited = page(
            .translated(
                SelectionTranslation(
                    original: "Hello", sourceLanguage: "en",
                    rows: [SelectionTranslationRow(code: "ja", name: "Japanese", text: "こんにちは")])),
            "Hello there")
        check(
            "editing the text hands back the action row instead of a stale answer",
            edited.items.map(\.id) == ["translate-action"])
        let stalled = page(.loading(original: "Hello", targets: pageTargets), "Hello there")
        check(
            "a run for older text never claims the newly typed text",
            stalled.items.map(\.id) == ["translate-action"])

        let retry = page(.failed("Google Cloud Translation failed (HTTP 403)."), "Hello")
        check("a failed page stays retryable", retry.items.map(\.id) == ["translate-action"])
        check(
            "a failed page says why in the row",
            retry.items.first?.subtitle == "Google Cloud Translation failed (HTTP 403).")
        check(
            "a failed row reads as a retry",
            retry.items.first?.primaryActionTitle == "Try Again")
        check(
            "a failure message is never truncated",
            retry.items.first?.subtitleLineLimit == nil)

        check(
            "a missing key explains where to add one",
            GoogleTranslationError.missingAPIKey.localizedDescription.contains(
                "Selection Tools settings"))
        check(
            "an empty target list explains itself",
            GoogleTranslationError.noTargets.localizedDescription.contains(
                "Selection Tools settings"))

        print(failures == 0 ? "\nSelection Tools: ALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
