import Foundation

@main
@MainActor
struct TextReplacementTests {
    static var passed = 0
    static var failed = 0

    static func main() {
        let gmail = Snippet(name: "Gmail address", content: "abc@gmail.com", keyword: "gmail")
        let paletteOnly = Snippet(name: "Signature", content: "— Marcus")
        var engine = TextReplacementEngine(prefix: "@@", snippets: [gmail, paletteOnly])

        expect(engine.consume("ordinary text") == nil, "unrelated text does not match")
        expect(engine.pendingCharacterCount == 0, "unrelated text is not retained")
        expect(engine.consume("@") == nil, "partial prefix waits")
        expect(engine.pendingCharacterCount == 1, "only partial trigger is retained")
        expect(engine.consume("@GMAIL")?.replacement == "abc@gmail.com", "matching ignores case")
        expect(engine.pendingCharacterCount == 0, "a completed match clears pending input")
        expect(
            TextReplacementEngine(prefix: "@@", snippets: [paletteOnly]).isEmpty,
            "a palette-only snippet never becomes a trigger")

        engine.reset()
        _ = engine.consume("@@gmai")
        engine.deleteBackward()
        expect(engine.pendingCharacterCount == 5, "backspace updates partial trigger")
        expect(engine.consume("il")?.trigger == "@@gmail", "typing can continue after backspace")

        engine.reset()
        let match = engine.consume("prefix@@gmail")
        expect(match?.deletionCount == 7, "match deletes the complete trigger")
        expect(match?.replacement == "abc@gmail.com", "match returns replacement text")

        let trimmed = try! SnippetValidator.normalizedSnippet(
            Snippet(name: " Work ", content: "hello", keyword: "  work  "), among: [])
        expect(trimmed.keyword == "work", "keywords trim surrounding whitespace")
        expect(trimmed.name == "Work", "names trim surrounding whitespace")
        let blanked = try! SnippetValidator.normalizedSnippet(
            Snippet(name: "Plain", content: "hello", keyword: "   "), among: [])
        expect(blanked.keyword == nil, "an all-whitespace keyword becomes palette-only")
        expectThrows("duplicate keywords are rejected") {
            _ = try SnippetValidator.normalizedSnippet(
                Snippet(name: "Other", content: "other", keyword: "GMAIL"), among: [gmail])
        }
        expectThrows("prefix-conflicting keywords are rejected") {
            _ = try SnippetValidator.normalizedSnippet(
                Snippet(name: "Other", content: "other", keyword: "g"), among: [gmail])
        }
        expectThrows("whitespace inside a keyword is rejected") {
            _ = try SnippetValidator.normalizedSnippet(
                Snippet(name: "Other", content: "other", keyword: "work mail"), among: [])
        }
        expectThrows("a nameless snippet is rejected") {
            _ = try SnippetValidator.normalizedSnippet(
                Snippet(name: "  ", content: "other"), among: [])
        }
        expect(
            (try? SnippetValidator.normalizedSnippet(
                Snippet(name: "Also plain", content: "x"), among: [paletteOnly])) != nil,
            "two palette-only snippets never conflict")

        // The retired rule records decode as expanding snippets named after their keyword.
        let legacy = Data(
            #"[{"id":"11111111-1111-1111-1111-111111111111","keyword":"addr","replacement":"1 Main St"}]"#
                .utf8)
        let migrated = try! JSONDecoder().decode([Snippet].self, from: legacy)
        expect(migrated.first?.name == "addr", "a legacy rule is named after its keyword")
        expect(migrated.first?.content == "1 Main St", "a legacy rule keeps its text")
        expect(migrated.first?.keyword == "addr", "a legacy rule keeps expanding")
        let reencoded = try! JSONDecoder().decode(
            [Snippet].self, from: try! JSONEncoder().encode(migrated))
        expect(reencoded == migrated, "the current shape round-trips")

        let suiteName = "TextReplacementTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = TextReplacementStore(defaults: defaults)
        expect(store.prefix == "@@", "store starts with the default prefix")
        try! store.setPrefix(";;")
        try! store.add(gmail)
        try! store.add(paletteOnly)
        let restored = TextReplacementStore(defaults: defaults)
        expect(restored.prefix == ";;", "prefix persists")
        expect(restored.snippets == [gmail, paletteOnly], "snippets persist")

        print("Snippets: \(passed) passed, \(failed) failed")
        if failed > 0 { exit(1) }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passed += 1
        } else {
            failed += 1
            print("FAIL: \(message)")
        }
    }

    private static func expectThrows(_ message: String, _ operation: () throws -> Void) {
        do {
            try operation()
            failed += 1
            print("FAIL: \(message)")
        } catch {
            passed += 1
        }
    }
}
