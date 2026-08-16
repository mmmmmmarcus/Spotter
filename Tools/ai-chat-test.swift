// Compile: swiftc -swift-version 6 Spotter/Plugins/AIChat/AIChatTypes.swift Spotter/Plugins/AIChat/AIChatMarkdown.swift Spotter/Plugins/AIChat/AIChatSelectionPrompts.swift Spotter/Core/OpenRouterModelCatalog.swift Tools/ai-chat-test.swift -o /tmp/ai-chat-test && /tmp/ai-chat-test
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

        let portableSession = AIChatSession(
            messages: [message(.user, "同步这个对话"), message(.assistant, "好的")],
            startedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let encodedSession = try! JSONEncoder().encode(portableSession)
        let decodedSession = try! JSONDecoder().decode(AIChatSession.self, from: encodedSession)
        check("a chat session round-trips through sync JSON", decodedSession == portableSession)

        check("an empty ChatGPT prompt has no URL", AIChatEngine.chatGPTURL(for: " \n ") == nil)
        let chatGPTPrompt = "  Explain Swift & Objective-C?\n用中文回答  "
        let chatGPTURL = AIChatEngine.chatGPTURL(for: chatGPTPrompt)
        let chatGPTComponents = chatGPTURL.flatMap {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)
        }
        check("ChatGPT handoff uses HTTPS", chatGPTComponents?.scheme == "https")
        check("ChatGPT handoff targets chatgpt.com", chatGPTComponents?.host == "chatgpt.com")
        check("ChatGPT handoff targets the root path", chatGPTComponents?.path == "/")
        check(
            "ChatGPT handoff uses the q query shape",
            chatGPTURL?.absoluteString.hasPrefix("https://chatgpt.com/?q=") == true)
        check(
            "ChatGPT handoff round-trips Unicode, reserved bytes and newlines",
            chatGPTComponents?.queryItems == [
                URLQueryItem(name: "q", value: "Explain Swift & Objective-C?\n用中文回答")
            ])

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
            "selected-text prompts invite follow-ups",
            AIChatSelectionPrompts.defaultDefinition.contains("follow-up")
                && AIChatSelectionPrompts.defaultGrammar.contains("later messages"))

        // Markdown block splitting: inline spans stay in the text, structure becomes blocks.
        check("plain text is one paragraph", AIChatMarkdown.blocks(in: "just an answer") == [
            .paragraph("just an answer")
        ])
        check("empty text has no blocks", AIChatMarkdown.blocks(in: "  \n\n ").isEmpty)
        check(
            "inline emphasis is left to the inline parser",
            AIChatMarkdown.blocks(in: "**bold** and `code`") == [.paragraph("**bold** and `code`")])
        check(
            "a blank line splits paragraphs",
            AIChatMarkdown.blocks(in: "first\n\nsecond") == [
                .paragraph("first"), .paragraph("second"),
            ])
        check(
            "soft-wrapped lines stay one paragraph",
            AIChatMarkdown.blocks(in: "first\nsecond") == [.paragraph("first\nsecond")])

        check(
            "headings carry their level",
            AIChatMarkdown.blocks(in: "## Title ##") == [.heading(level: 2, text: "Title")])
        check("a bare hash is not a heading", AIChatMarkdown.blocks(in: "#tag") == [.paragraph("#tag")])
        check(
            "seven hashes are not a heading",
            AIChatMarkdown.blocks(in: "####### deep") == [.paragraph("####### deep")])

        check(
            "dash bullets become list items",
            AIChatMarkdown.blocks(in: "- **Waste disposal** – trash\n- Data dumping") == [
                .listItem(marker: "•", text: "**Waste disposal** – trash", depth: 0),
                .listItem(marker: "•", text: "Data dumping", depth: 0),
            ])
        check(
            "numbered lists keep their numbers",
            AIChatMarkdown.blocks(in: "1. one\n2) two") == [
                .listItem(marker: "1.", text: "one", depth: 0),
                .listItem(marker: "2.", text: "two", depth: 0),
            ])
        check(
            "indentation becomes depth, capped",
            AIChatMarkdown.blocks(in: "  - two spaces\n            - very deep") == [
                .listItem(marker: "•", text: "two spaces", depth: 1),
                .listItem(marker: "•", text: "very deep", depth: 3),
            ])
        check(
            "a marker needs its space",
            AIChatMarkdown.blocks(in: "-not a list") == [.paragraph("-not a list")])
        check(
            "task boxes replace the raw brackets",
            AIChatMarkdown.blocks(in: "- [ ] todo\n- [x] done") == [
                .listItem(marker: "☐", text: "todo", depth: 0),
                .listItem(marker: "☑", text: "done", depth: 0),
            ])

        check(
            "fenced code keeps its language and body verbatim",
            AIChatMarkdown.blocks(in: "```swift\nlet x = 1\n\n  indented\n```") == [
                .code(language: "swift", text: "let x = 1\n\n  indented")
            ])
        check(
            "an unterminated fence still renders as code",
            AIChatMarkdown.blocks(in: "```\nlet x = 1") == [.code(language: nil, text: "let x = 1")])
        check(
            "a fence interrupts the paragraph around it",
            AIChatMarkdown.blocks(in: "before\n```\ncode\n```\nafter") == [
                .paragraph("before"), .code(language: nil, text: "code"), .paragraph("after"),
            ])
        check(
            "an inline code span never opens a fence",
            AIChatMarkdown.blocks(in: "``code`` here") == [.paragraph("``code`` here")])

        check(
            "consecutive quoted lines are one block",
            AIChatMarkdown.blocks(in: "> first\n> second") == [.quote("first\nsecond")])
        check("a rule is its own block", AIChatMarkdown.blocks(in: "a\n\n---\n\nb") == [
            .paragraph("a"), .rule, .paragraph("b"),
        ])

        check(
            "a delimiter row makes a table",
            AIChatMarkdown.blocks(in: "| A | B |\n| --- | :-: |\n| 1 | 2 |\n| 3 |") == [
                .table(header: ["A", "B"], rows: [["1", "2"], ["3"]])
            ])
        check(
            "a pipe without a delimiter row stays prose",
            AIChatMarkdown.blocks(in: "use a | pipe\nnot a table") == [
                .paragraph("use a | pipe\nnot a table")
            ])

        // The OpenRouter model catalog behind the Settings brand → model menus.
        let payload = """
            {"data": [
              {"id": "openai/gpt-legacy", "name": "OpenAI: GPT Legacy", "created": 100,
               "architecture": {"output_modalities": ["text"]}},
              {"id": "anthropic/claude-old", "name": "Anthropic: Claude Old", "created": 200,
               "architecture": {"output_modalities": ["text"]}},
              {"id": "anthropic/claude-new", "name": "Anthropic: Claude New", "created": 900,
               "architecture": {"output_modalities": ["text"]}},
              {"id": "black-forest-labs/flux", "name": "Black Forest Labs: FLUX", "created": 800,
               "architecture": {"output_modalities": ["image"]}},
              {"id": "anthropic/claude-new", "name": "Anthropic: Duplicate", "created": 950,
               "architecture": {"output_modalities": ["text"]}},
              {"id": "deep-mind/bare-id", "created": 300}
            ]}
            """
        let brands = (try? OpenRouterModelCatalog.brands(fromJSON: Data(payload.utf8))) ?? []
        check("brands are grouped by the id prefix", brands.map(\.id) == [
            "anthropic", "deep-mind", "openai",
        ])
        check("brands sort by title", brands.map(\.title) == ["Anthropic", "Deep Mind", "OpenAI"])
        check(
            "an image-only model can't answer a chat turn",
            !brands.contains { $0.id == "black-forest-labs" })
        check(
            "models are newest first with the brand prefix stripped",
            brands.first?.models.map(\.name) == ["Claude New", "Claude Old"])
        check(
            "a repeated id keeps only its first entry",
            brands.first?.models.count == 2)
        check(
            "a nameless entry falls back to the id tail and a prettified brand",
            brands[1].models.map(\.name) == ["bare-id"])
        check(
            "a catalogued id gets a brand-qualified label",
            OpenRouterModelCatalog.label(for: "anthropic/claude-new", in: brands)
                == "Anthropic · Claude New")
        check(
            "an unknown id has no catalog label",
            OpenRouterModelCatalog.label(for: "anthropic/claude-gone", in: brands) == nil)
        check(
            "an empty payload yields no brands",
            (try? OpenRouterModelCatalog.brands(fromJSON: Data(#"{"data": []}"#.utf8)))?.isEmpty
                == true)
        check(
            "a malformed payload throws instead of guessing",
            (try? OpenRouterModelCatalog.brands(fromJSON: Data("not json".utf8))) == nil)

        print(failures == 0 ? "\nAI Chat: ALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
