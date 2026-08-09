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

        let grammarResult = SelectionGrammarResult(
            originalText: snapshot.text,
            correctedText: "I have an apple.",
            issues: [
                SelectionGrammarIssue(
                    location: 2, length: 3, originalText: "has",
                    message: "Use plural agreement", suggestions: ["have"])
            ])
        check("current grammar result completes", machine.completeGrammar(grammarResult, for: grammarRequest))
        check("grammar completion publishes result", machine.state == .grammarChecked(grammarRequest, grammarResult))

        let definitionRequest = machine.begin(action: .define, snapshot: snapshot)
        let definitionResult = SelectionDefinitionResult(
            originalText: snapshot.text,
            definitionText: "English: A sample.\n中文：一个示例。")
        check(
            "current definition result completes",
            machine.completeDefinition(definitionResult, for: definitionRequest))
        check(
            "definition completion publishes result",
            machine.state == .defined(definitionRequest, definitionResult))

        let nextRequest = machine.begin(action: .translate, snapshot: snapshot)
        check("active request cancels", machine.cancelActive())
        check(
            "cancellation publishes explicit failure",
            machine.state == .failed(action: .translate, snapshot: snapshot, error: .cancelled))
        check(
            "cancelled request cannot publish later",
            !machine.completeTranslation(staleTranslation, for: nextRequest))

        check(
            "LLM target is the first preferred language",
            SelectionLLM.targetLanguage(preferred: ["zh-Hans-CN", "en-US"], detectedSource: "en") == "zh")
        check(
            "LLM target skips the source language",
            SelectionLLM.targetLanguage(preferred: ["zh-Hans-CN", "en-US"], detectedSource: "zh") == "en")
        check(
            "LLM target falls back to English",
            SelectionLLM.targetLanguage(preferred: ["fr-FR"], detectedSource: "fr") == "en")
        check(
            "LLM target defaults to English with no preferences",
            SelectionLLM.targetLanguage(preferred: [], detectedSource: "de") == "en")
        check(
            "LLM English-only stays English",
            SelectionLLM.targetLanguage(preferred: ["en-US"], detectedSource: "en") == "en")

        check(
            "LLM translation prompt names the target",
            SelectionLLM.translationSystemPrompt(targetLanguageName: "French").contains("French"))
        check(
            "custom translation prompt expands target token",
            SelectionLLM.translationSystemPrompt(
                targetLanguageName: "Japanese", template: "Use {{target_language}} only.")
                == "Use Japanese only.")
        check(
            "LLM translation parse strips fences",
            SelectionLLM.parseTranslation("```\nBonjour\n```") == "Bonjour")
        check(
            "default definition prompt requires bilingual output",
            SelectionLLM.defaultDefinitionSystemPrompt.contains("English")
                && SelectionLLM.defaultDefinitionSystemPrompt.contains("Simplified Chinese"))
        check(
            "LLM definition parse strips fences",
            SelectionLLM.parseDefinition("```\nEnglish: Example.\n中文：示例。\n```")
                == "English: Example.\n中文：示例。")
        check(
            "custom grammar prompt is used verbatim",
            SelectionLLM.grammarSystemPrompt(template: "Return corrected text.")
                == "Return corrected text.")

        let grammarJSON = #"""
        ```json
        {"corrected": "I have an apple.", "issues": [
          {"original": "has", "message": "Agreement", "suggestion": "have"},
          {"original": "a", "message": "Article", "suggestion": "an"}
        ]}
        ```
        """#
        let llmGrammar = SelectionLLM.parseGrammar(grammarJSON, originalText: "I has a apple.")
        check("LLM grammar parse reads corrected text", llmGrammar.correctedText == "I have an apple.")
        check("LLM grammar parse keeps issues", llmGrammar.issues.map(\.message) == ["Agreement", "Article"])
        check(
            "LLM grammar issues anchor left to right",
            llmGrammar.issues.map(\.location) == [2, 6])
        check(
            "LLM grammar suggestion carries through",
            llmGrammar.issues.first?.suggestions == ["have"])
        let fallback = SelectionLLM.parseGrammar("Just a plain reply.", originalText: "x")
        check(
            "LLM grammar non-JSON degrades to corrected text",
            fallback.correctedText == "Just a plain reply." && fallback.issues.isEmpty)

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
