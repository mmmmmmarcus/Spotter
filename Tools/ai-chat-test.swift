// Compile: swiftc -swift-version 6 Spotter/Plugins/AIChat/AIChatTypes.swift Tools/ai-chat-test.swift -o /tmp/ai-chat-test && /tmp/ai-chat-test
import Foundation

@main
struct AIChatTests {
    static func main() {
        var failures = 0
        func check(_ message: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS  \(message)")
            } else {
                failures += 1
                print("FAIL  \(message)")
            }
        }

        func message(_ role: AIChatMessage.Role, _ text: String) -> AIChatMessage {
            AIChatMessage(role: role, text: text)
        }

        check("empty transcript stays empty", AIChatEngine.transcriptWindow([]).isEmpty)

        let short = [
            message(.user, "hello"),
            message(.assistant, "hi"),
            message(.user, "what's Swift?"),
        ]
        check(
            "a transcript under budget survives whole",
            AIChatEngine.transcriptWindow(short) == short)

        // Oldest turns drop first; order is preserved.
        let long = [
            message(.user, String(repeating: "a", count: 90)),
            message(.assistant, String(repeating: "b", count: 90)),
            message(.user, "latest question"),
        ]
        let windowed = AIChatEngine.transcriptWindow(long, budget: 120)
        check("over budget drops the oldest first", windowed.count == 2)
        check("the kept turns stay in order", windowed.map(\.text) == [
            String(repeating: "b", count: 90), "latest question",
        ])

        // The newest message always survives, even alone over budget.
        let huge = [
            message(.user, "old context"),
            message(.user, String(repeating: "x", count: 500)),
        ]
        let hugeWindow = AIChatEngine.transcriptWindow(huge, budget: 100)
        check("the latest message survives over budget", hugeWindow.count == 1)
        check("and it is the latest one", hugeWindow.first?.text.first == "x")

        // Boundary: a message landing exactly on the budget is kept.
        let exact = [
            message(.user, String(repeating: "a", count: 50)),
            message(.user, String(repeating: "b", count: 50)),
        ]
        check(
            "an exact-budget fit keeps both", AIChatEngine.transcriptWindow(exact, budget: 100).count == 2)

        // Session titles derive from the first user turn, like Notes titles.
        check("empty session titles as New Session", AIChatEngine.sessionTitle(for: []) == "New Session")
        check(
            "title is the first user turn",
            AIChatEngine.sessionTitle(for: [
                message(.user, "what is Swift?"), message(.assistant, "a language"),
            ]) == "what is Swift?")
        check(
            "title skips a leading assistant turn",
            AIChatEngine.sessionTitle(for: [
                message(.assistant, "hello"), message(.user, "hi there"),
            ]) == "hi there")
        check(
            "title collapses whitespace",
            AIChatEngine.sessionTitle(for: [message(.user, "  a\n  b   c ")]) == "a b c")
        let longTitle = AIChatEngine.sessionTitle(
            for: [message(.user, String(repeating: "word ", count: 30))], limit: 20)
        check("long titles are capped with an ellipsis", longTitle.hasSuffix("…") && longTitle.count <= 22)

        check("system prompt is non-empty", !AIChatEngine.systemPrompt.isEmpty)
        check(
            "roles encode as OpenRouter role strings",
            AIChatMessage.Role.user.rawValue == "user"
                && AIChatMessage.Role.assistant.rawValue == "assistant")

        // One request owns the whole chat store even while the user browses another session.
        let firstSession = UUID()
        let secondSession = UUID()
        var requests = AIChatRequestLedger()
        check("the first request begins", requests.begin(sessionID: firstSession))
        check("another session cannot start concurrently", !requests.begin(sessionID: secondSession))
        check("the owner session shows waiting", requests.phase(for: firstSession) == .waiting)
        check("a background session stays idle", requests.phase(for: secondSession) == .idle)
        check(
            "a stale completion cannot clear the owner",
            !requests.finish(sessionID: secondSession, failure: nil)
                && requests.waitingSessionID == firstSession)
        check(
            "a failure is stored on the asking session",
            requests.finish(sessionID: firstSession, failure: "Offline")
                && requests.phase(for: firstSession) == .failed("Offline"))
        check("the second session can start after completion", requests.begin(sessionID: secondSession))
        requests.cancel()
        check("cancel clears only the active request", requests.waitingSessionID == nil)
        check("an earlier session's failure survives switching", requests.phase(for: firstSession) == .failed("Offline"))
        requests.remove(sessionID: firstSession)
        check("deleting a session drops its failure", requests.phase(for: firstSession) == .idle)

        check(
            "selection translation targets the first preferred language",
            AIChatSelectionPrompts.targetLanguage(
                preferred: ["zh-Hans-CN", "en-US"], detectedSource: "en") == "zh")
        check(
            "selection translation skips the source language",
            AIChatSelectionPrompts.targetLanguage(
                preferred: ["zh-Hans-CN", "en-US"], detectedSource: "zh") == "en")
        check(
            "selection translation falls back to English",
            AIChatSelectionPrompts.targetLanguage(
                preferred: ["fr-FR"], detectedSource: "fr") == "en")
        check(
            "translation prompt expands the target language",
            AIChatSelectionPrompts.translation(
                template: "Use {{target_language}} only.", targetLanguageName: "Japanese")
                == "Use Japanese only.")
        check(
            "selected-text prompts invite follow-ups",
            AIChatSelectionPrompts.defaultTranslation.contains("later messages")
                && AIChatSelectionPrompts.defaultDefinition.contains("follow-up")
                && AIChatSelectionPrompts.defaultGrammar.contains("later messages"))

        print(failures == 0 ? "\nAI Chat: ALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
