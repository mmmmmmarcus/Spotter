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

        print(failures == 0 ? "\nAI Chat: ALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
