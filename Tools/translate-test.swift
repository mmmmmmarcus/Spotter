import Foundation

@main
struct TranslateTests {
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
            check(
                "translation API errors retain provider detail",
                response.error?.message == "API key not valid")
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

        // The pause is what keeps live translation cheap, so it has to stay a real pause.
        check(
            "the typing pause is long enough to be a pause",
            TranslateTiming.typingPause >= .milliseconds(400))
        check(
            "the typing pause is short enough to feel live",
            TranslateTiming.typingPause <= .seconds(2))

        let ja = TranslationLanguages.targets(for: ["ja"])
        let jaResult = TranslationResult(
            original: "Hello", sourceLanguage: "en",
            rows: [TranslationRow(code: "ja", name: "Japanese", text: "こんにちは")])
        var memo = TranslationMemo()
        let jaKey = TranslationMemo.key(text: "Hello", targets: ["ja"])
        check("an unseen text is never memoized", memo.value(for: jaKey) == nil)
        memo.insert(jaResult, for: jaKey)
        check("a translated text is answered from the memo", memo.value(for: jaKey) == jaResult)
        check(
            "a different target list is a different bill",
            memo.value(for: TranslationMemo.key(text: "Hello", targets: ["ja", "fr"])) == nil)
        check(
            "different text is a different bill",
            memo.value(for: TranslationMemo.key(text: "Hello!", targets: ["ja"])) == nil)
        check(
            "re-inserting the same key does not grow the memo",
            { memo.insert(jaResult, for: jaKey); return memo.count == 1 }())
        for index in 0..<(TranslationMemo.capacity + 8) {
            memo.insert(
                TranslationResult(original: "t\(index)", sourceLanguage: "en", rows: []),
                for: TranslationMemo.key(text: "t\(index)", targets: ["ja"]))
        }
        check("the memo stays bounded", memo.count == TranslationMemo.capacity)
        memo.removeAll()
        check("clearing the memo forgets everything", memo.count == 0)

        let translation = TranslationResult(
            original: "Hello", sourceLanguage: "en",
            rows: [
                TranslationRow(code: "zh-CN", name: "Chinese (Simplified)", text: "你好"),
                TranslationRow(code: "ja", name: "Japanese", text: "こんにちは"),
            ])
        let snapshot = TranslateResults.snapshot(screen: .selection, state: .translated(translation))
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

        let loading = TranslateResults.snapshot(
            screen: .selection, state: .loading(original: "Source", targets: ja))
        check(
            "loading reserves each target ahead of the original",
            loading.items.map(\.id) == ["ja", "original"])
        check("loading keeps the original immediately copyable", loading.items.last?.title == "Source")

        let filtered = TranslateResults.snapshot(
            screen: .selection, state: .translated(translation), query: "Japanese")
        check("translation rows can be filtered by language", filtered.items.map(\.id) == ["ja"])

        let pageTargets = TranslationLanguages.targets(for: ["ja", "fr"])
        func page(
            _ state: TranslateState, _ query: String, hasAPIKey: Bool = true,
            targets: [TranslationLanguage]? = nil
        ) -> PluginPaletteSnapshot {
            TranslateResults.snapshot(
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
            TranslateResults.snapshot(screen: .compose, state: .idle, query: "Hello").items.isEmpty)
        let noTargets = page(.idle, "Hello", targets: [])
        check("the Translate page offers no row without a target", noTargets.items.isEmpty)
        check(
            "the Translate page names the empty target list",
            noTargets.errorMessage == GoogleTranslationError.noTargets.localizedDescription)

        let untyped = page(.idle, "   \n ")
        check("an empty Translate page has nothing to show", untyped.items.isEmpty)
        check(
            "an empty Translate page says how it works",
            untyped.emptyMessage == "Type text — it translates when you pause")

        let typed = page(.idle, " Hello ")
        check("typed text offers no row to press", typed.items.isEmpty)
        check(
            "typed text says the pause is what spends the request",
            typed.emptyMessage == "Pause typing to translate into Japanese, French")

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
                TranslationResult(
                    original: "Hello", sourceLanguage: "en",
                    rows: [
                        TranslationRow(code: "ja", name: "Japanese", text: "こんにちは"),
                        TranslationRow(code: "fr", name: "French", text: "Bonjour"),
                    ])),
            "Hello")
        check("the Translate page lists one row per target", answered.items.map(\.id) == ["ja", "fr"])
        check(
            "the Translate page's rows are copyable",
            answered.items.allSatisfy { $0.primaryActionTitle.hasPrefix("Copy ") })
        let edited = page(
            .translated(
                TranslationResult(
                    original: "Hello", sourceLanguage: "en",
                    rows: [TranslationRow(code: "ja", name: "Japanese", text: "こんにちは")])),
            "Hello there")
        check("editing the text drops a stale answer", edited.items.isEmpty)
        let stalled = page(.loading(original: "Hello", targets: pageTargets), "Hello there")
        check("a run for older text never claims the newly typed text", stalled.items.isEmpty)
        check(
            "superseded text is never shown as loading",
            !stalled.isLoading)

        let retry = page(.failed("Google Cloud Translation failed (HTTP 403)."), "Hello")
        check("a failed page offers exactly one row", retry.items.map(\.id) == ["translate-retry"])
        check(
            "a failed page says why in the row",
            retry.items.first?.subtitle == "Google Cloud Translation failed (HTTP 403).")
        check("a failed row reads as a retry", retry.items.first?.primaryActionTitle == "Try Again")
        check("a failure message is never truncated", retry.items.first?.subtitleLineLimit == nil)

        check(
            "a missing key explains where to add one",
            GoogleTranslationError.missingAPIKey.localizedDescription.contains("Translate settings"))
        check(
            "an empty target list explains itself",
            GoogleTranslationError.noTargets.localizedDescription.contains("Translate settings"))

        print(failures == 0 ? "\nTranslate: ALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
