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

        let snapshot = SelectedTextSnapshot(
            text: "I has a apple.",
            source: SelectedTextSourceSnapshot(
                processIdentifier: 42, appName: "TextEdit", bundleIdentifier: "com.apple.TextEdit"),
            capturedAt: Date(timeIntervalSince1970: 100))
        var machine = SelectionToolsStateMachine()
        let translationRequest = machine.begin(action: .translate, snapshot: snapshot)
        let grammarRequest = machine.begin(action: .grammar, snapshot: snapshot)
        let staleTranslation = SelectionTranslationResult(
            originalText: snapshot.text, translatedText: "stale",
            sourceLanguageIdentifier: "en", targetLanguageIdentifier: "zh")
        check(
            "new request rejects old result",
            !machine.completeTranslation(staleTranslation, for: translationRequest))
        check(
            "old result cannot replace loading state",
            machine.state == .loading(grammarRequest))

        let grammarResult = SelectionGrammarResponseMapper.map(
            originalText: snapshot.text,
            rawIssues: [
                SelectionGrammarRawIssue(
                    location: 2, length: 3,
                    message: "Use plural agreement", suggestions: ["have"]),
                SelectionGrammarRawIssue(
                    location: 6, length: 1,
                    message: "Use an before a vowel sound", suggestions: ["an"]),
            ])
        check("grammar corrections map in stable ranges", grammarResult.correctedText == "I have an apple.")
        check("grammar issue mapping keeps descriptions", grammarResult.issues.map(\.message) == ["Use plural agreement", "Use an before a vowel sound"])
        check("current grammar result completes", machine.completeGrammar(grammarResult, for: grammarRequest))
        check("grammar completion publishes result", machine.state == .grammarChecked(grammarRequest, grammarResult))

        let nextRequest = machine.begin(action: .translate, snapshot: snapshot)
        check("active request cancels", machine.cancelActive())
        check(
            "cancellation publishes explicit failure",
            machine.state == .failed(action: .translate, snapshot: snapshot, error: .cancelled))
        check(
            "cancelled request cannot publish later",
            !machine.completeTranslation(staleTranslation, for: nextRequest))

        let mappedTranslation = SelectionTranslationResponseMapper.map(
            originalText: "Hello", translatedText: "你好",
            sourceLanguageIdentifier: "en", targetLanguageIdentifier: "zh")
        check("translation mapping keeps original", mappedTranslation.originalText == "Hello")
        check("translation mapping keeps target", mappedTranslation.translatedText == "你好")
        check("translation mapping keeps languages", mappedTranslation.sourceLanguageIdentifier == "en" && mappedTranslation.targetLanguageIdentifier == "zh")

        do {
            let liveGrammar = try await SystemSelectionGrammarService().check("I has a apple.")
            check("system grammar callback returns safely", liveGrammar.originalText == "I has a apple.")
        } catch {
            failures += 1
            print("FAIL  system grammar callback returns safely: \(error)")
        }

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
