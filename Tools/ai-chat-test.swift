// Compile: swiftc -swift-version 6 Spotter/Plugins/AIChat/AIChatTypes.swift Spotter/Plugins/AIChat/AIChatMarkdown.swift Spotter/Plugins/AIChat/AIChatSelectionPrompts.swift Spotter/Plugins/AIChat/AICommand.swift Spotter/Plugins/AIChat/AICommandStore.swift Spotter/Core/OpenRouterModelCatalog.swift Tools/ai-chat-test.swift -o /tmp/ai-chat-test && /tmp/ai-chat-test
import Foundation

@main
struct AIChatTests {
    @MainActor
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
            "the untitled fallback is that same one string",
            AIChatEngine.untitledSessionTitle == AIChatEngine.sessionTitle(for: []))
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

        // A session's own title is what names its background-task row: an override wins, otherwise
        // the first user turn, and only a conversation with no user turn falls back to untitled.
        check(
            "a session titles itself from its first user turn",
            AIChatSession(messages: [message(.user, "why is the sky blue?")]).title
                == "why is the sky blue?")
        check(
            "an override wins over the derived title",
            AIChatSession(
                messages: [message(.user, "sky")], titleOverride: "Definition"
            ).title == "Definition")
        check(
            "a conversation with no user turn falls back to the untitled name",
            AIChatSession().title == AIChatEngine.untitledSessionTitle)

        // The background-task row's subtitle uses this vocabulary and nothing else.
        check(
            "the request statuses are distinct and non-empty",
            !AIChatEngine.waitingStatus.isEmpty && !AIChatEngine.replyReadyStatus.isEmpty
                && AIChatEngine.waitingStatus != AIChatEngine.replyReadyStatus)

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

        // The rendered prompt is the first user turn, so the conversation can simply continue.
        check(
            "the shipped prompts still invite follow-ups",
            AIChatSelectionPrompts.defaultDefinition.contains("follow-up")
                && AIChatSelectionPrompts.defaultGrammar.contains("if asked"))

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

        // The brand-free name behind the launcher's "Ask <model>…" row.
        check(
            "a catalogued id uses the catalog's own model name",
            OpenRouterModelCatalog.modelName(for: "anthropic/claude-new", in: brands)
                == "Claude New")
        check(
            "an uncatalogued id is prettified from its tail",
            OpenRouterModelCatalog.modelName(for: "google/gemini-2.0-flash", in: brands)
                == "Gemini 2.0 Flash")
        check(
            "short vowel-free words stay acronyms",
            OpenRouterModelCatalog.modelName(for: "openai/gpt-5.1", in: []) == "GPT 5.1"
                && OpenRouterModelCatalog.modelName(for: "deepseek/deepseek-r1", in: [])
                    == "Deepseek R1")
        check(
            "an id without a vendor prefix is used whole",
            OpenRouterModelCatalog.modelName(for: "sonar-pro", in: []) == "Sonar Pro")
        check(
            "a blank id has no name",
            OpenRouterModelCatalog.modelName(for: "  ", in: brands) == nil)
        check(
            "an empty payload yields no brands",
            (try? OpenRouterModelCatalog.brands(fromJSON: Data(#"{"data": []}"#.utf8)))?.isEmpty
                == true)
        check(
            "a malformed payload throws instead of guessing",
            (try? OpenRouterModelCatalog.brands(fromJSON: Data("not json".utf8))) == nil)


        // MARK: AI commands

        // Substitution is a template render, not a chat setup: the rendered text is the turn sent.
        check(
            "the placeholder is the selection's slot",
            AICommandEngine.render(prompt: "Define {selection} briefly.", selection: "gumption")
                == "Define gumption briefly.")
        check(
            "every occurrence is substituted",
            AICommandEngine.render(
                prompt: "{selection} — now translate {selection}.", selection: "hi")
                == "hi — now translate hi.")
        check(
            "a prompt without the token gets the selection appended",
            AICommandEngine.render(prompt: "Proofread this.", selection: "teh cat")
                == "Proofread this.\n\nteh cat")
        // The pre-AI-Commands prompts had no token; appending is what makes them keep working.
        check(
            "an appended prompt is trimmed before the blank line",
            AICommandEngine.render(prompt: "  Summarize.  ", selection: "text")
                == "Summarize.\n\ntext")
        // One pass: inserted text is never rescanned, so a selection quoting the token survives.
        check(
            "a selection containing the token is inserted, not rescanned",
            AICommandEngine.render(
                prompt: "Explain {selection}.", selection: "the {selection} token")
                == "Explain the {selection} token.")
        check(
            "a selection that is only the token stays literal",
            AICommandEngine.render(prompt: "{selection}", selection: "{selection}")
                == "{selection}")
        check(
            "an empty prompt sends the selection alone",
            AICommandEngine.render(prompt: "   ", selection: "just this") == "just this")
        check(
            "an empty selection leaves no dangling blank line",
            AICommandEngine.render(prompt: "Summarize.", selection: "") == "Summarize.")
        check(
            "the placeholder is the single-brace shape quicklinks use",
            AICommand.placeholder == "{selection}")
        check(
            "both shipped prompts carry the placeholder",
            AIBuiltInCommand.allCases.allSatisfy {
                AICommandEngine.hasPlaceholder($0.defaultPrompt)
            })

        // Identity: the shipped commands keep every key they had as Selection Tools actions.
        check(
            "Define keeps its historical shortcut key",
            AICommand.shortcutDefaultsKey(forID: AIBuiltInCommand.define.id)
                == "KeyboardShortcuts_plugin.selection-tools.define")
        check(
            "Grammar keeps its historical shortcut key",
            AICommand.shortcutDefaultsKey(forID: AIBuiltInCommand.grammar.id)
                == "KeyboardShortcuts_plugin.selection-tools.grammar")
        check(
            "the shipped launcher entry ids are unchanged",
            AIBuiltInCommand.allCases.map(\.entryID) == [
                "command:selection-tools:define", "command:selection-tools:grammar",
            ])
        check(
            "a shipped entry id resolves to its fixed command id",
            AICommand.id(fromEntryID: "command:selection-tools:grammar")
                == AIBuiltInCommand.grammar.id)
        check(
            "the two shipped ids are distinct",
            AIBuiltInCommand.define.id != AIBuiltInCommand.grammar.id)

        let userCommand = AICommand(name: "Summarize", prompt: "Summarize {selection}.")
        check(
            "a user command gets its own shortcut namespace",
            userCommand.shortcutDefaultsKey
                == "KeyboardShortcuts_aiCommandHotkey." + userCommand.id.uuidString.lowercased())
        check(
            "a user command's entry id round-trips",
            AICommand.id(fromEntryID: userCommand.entryID) == userCommand.id)
        check(
            "an unrelated entry id is not an AI command",
            AICommand.id(fromEntryID: "command:quit") == nil)

        // A command follows the chat model unless it pins one, and a pinned id is never rewritten —
        // a model the key can no longer reach stays the command's choice.
        check(
            "no pinned model means the chat model",
            userCommand.resolvedModel(chatModel: "anthropic/claude-sonnet-5")
                == "anthropic/claude-sonnet-5")
        check(
            "a blank pinned model falls back to the chat model",
            AICommand(name: "Blank", prompt: "p", model: "   ")
                .resolvedModel(chatModel: "chat/model") == "chat/model")
        check(
            "a withdrawn model stays the command's choice",
            AICommand(name: "Pinned", prompt: "p", model: "vendor/retired-model")
                .resolvedModel(chatModel: "chat/model") == "vendor/retired-model")
        check(
            "a withdrawn model still has a name to show",
            OpenRouterModelCatalog.modelName(for: "vendor/retired-model", in: [])
                == "Retired Model")

        // Repair: whatever was decoded, both shipped commands exist once and lead.
        let fresh = AICommandEngine.normalized([])
        check(
            "an empty list rebuilds both shipped commands, in order",
            fresh.map(\.builtIn) == [.define, .grammar])
        check(
            "the rebuilt commands carry the shipped prompts",
            fresh[0].prompt == AIBuiltInCommand.define.defaultPrompt)
        check(
            "the rebuilt commands pin the shipped fast model",
            fresh.allSatisfy { $0.model == AICommand.defaultBuiltInModel })

        let seeded = AICommandEngine.normalized(
            [],
            seed: AICommandSeed(
                prompts: [.define: "my own definition prompt"],
                models: [.grammar: "vendor/my-model"]))
        check(
            "a pre-AI-Commands prompt seeds its command",
            seeded[0].prompt == "my own definition prompt")
        check(
            "an unseeded prompt stays the shipped one",
            seeded[1].prompt == AIBuiltInCommand.grammar.defaultPrompt)
        check("a pre-AI-Commands model seeds its command", seeded[1].model == "vendor/my-model")

        let mixed = AICommandEngine.normalized([
            AICommand(name: "  Summarize  ", prompt: "  Summarize {selection}.  "),
            AICommand(name: "Summarize", prompt: "a duplicate name"),
            AICommand(name: "Define Selected Text", prompt: "shadowing a built-in"),
            AICommand(name: "Broken", prompt: "   "),
            AICommand(
                id: UUID(), name: "renamed by a hand-edit", prompt: "kept prompt",
                model: nil, builtIn: .define),
        ])
        check("shipped commands still lead", mixed.map(\.builtIn) == [.define, .grammar, nil])
        check(
            "a built-in record with the wrong id is repaired onto the fixed one",
            mixed[0].id == AIBuiltInCommand.define.id && mixed[0].prompt == "kept prompt")
        check("a built-in keeps Spotter's name", mixed[0].name == "Define Selected Text")
        check("names and prompts are trimmed", mixed[2].name == "Summarize")
        check("a duplicate name drops out", mixed.filter { $0.name == "Summarize" }.count == 1)
        check("a command with no prompt drops out", !mixed.contains { $0.name == "Broken" })
        check(
            "a user command cannot shadow a built-in's name",
            mixed.filter { $0.name == "Define Selected Text" }.count == 1)

        check(
            "a command round-trips through sync JSON",
            (try? JSONDecoder().decode(
                AICommand.self, from: JSONEncoder().encode(userCommand))) == userCommand)

        // MARK: AI command store

        let suiteName = "com.spotter.ai-command-tests.\(UUID().uuidString)"
        guard let commandDefaults = UserDefaults(suiteName: suiteName) else {
            print("FAIL  could not create an isolated UserDefaults suite")
            exit(1)
        }
        commandDefaults.removePersistentDomain(forName: suiteName)
        defer { commandDefaults.removePersistentDomain(forName: suiteName) }

        // The upgrade an existing install actually takes: prompts and models under their old keys.
        commandDefaults.set("my definition prompt", forKey: "selection-tools.definition-prompt")
        commandDefaults.set("vendor/definition-model", forKey: "openrouter.definition-model")
        commandDefaults.set("vendor/shared-model", forKey: "openrouter.model")
        let store = AICommandStore(defaults: commandDefaults)
        check("the store starts with both shipped commands", store.commands.count == 2)
        check(
            "a customized prompt migrates onto its command",
            store.command(.define)?.prompt == "my definition prompt")
        check(
            "a customized model migrates onto its command",
            store.command(.define)?.model == "vendor/definition-model")
        check(
            "the one-shared-model release still migrates",
            store.command(.grammar)?.model == "vendor/shared-model")
        check(
            "a migrated prompt without the token still renders",
            store.command(.define)?.rendered(selection: "word")
                == "my definition prompt\n\nword")

        let added = try? store.add(AICommand(name: " Summarize ", prompt: " {selection} "))
        check("add trims the name", added?.name == "Summarize")
        check("add appends after the shipped commands", store.commands.last?.id == added?.id)
        check(
            "a duplicate name is refused",
            (try? store.add(AICommand(name: "summarize", prompt: "p"))) == nil)
        check(
            "an empty prompt is refused",
            (try? store.add(AICommand(name: "Blank", prompt: "  "))) == nil)
        check(
            "a name colliding with a built-in is refused",
            (try? store.add(AICommand(name: "Define Selected Text", prompt: "p"))) == nil)

        store.setModel(nil, for: AIBuiltInCommand.define.id)
        check("a command can go back to the chat model", store.command(.define)?.model == nil)
        store.reset(.define)
        check(
            "reset restores the shipped prompt",
            store.command(.define)?.prompt == AIBuiltInCommand.define.defaultPrompt)
        check("reset restores the shipped model", store.command(.define)?.isDefault == true)
        check(
            "a shipped command cannot be removed",
            store.remove(id: AIBuiltInCommand.define.id) == nil)
        check("the shipped command is still there", store.commands.count == 3)

        let reloaded = AICommandStore(defaults: commandDefaults)
        check("commands persist across a relaunch", reloaded.commands == store.commands)
        check("a user command survives the relaunch", reloaded.commands.last?.name == "Summarize")

        if let addedID = added?.id {
            check("a user command can be removed", store.remove(id: addedID) != nil)
        }
        check("removal leaves the shipped pair", store.commands.count == 2)

        check(
            "replace repairs an imported list",
            store.replace(with: [AICommand(name: "Imported", prompt: "{selection}")]) == 3)
        check(
            "an import can never drop a shipped command",
            store.commands.map(\.builtIn) == [.define, .grammar, nil])

        print(failures == 0 ? "\nAI Chat: ALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
