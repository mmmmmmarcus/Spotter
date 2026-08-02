import Foundation

@main
@MainActor
struct TextReplacementTests {
    static var passed = 0
    static var failed = 0

    static func main() {
        let gmail = TextReplacementRule(keyword: "gmail", replacement: "abc@gmail.com")
        var engine = TextReplacementEngine(prefix: "@@", rules: [gmail])

        expect(engine.consume("ordinary text") == nil, "unrelated text does not match")
        expect(engine.pendingCharacterCount == 0, "unrelated text is not retained")
        expect(engine.consume("@") == nil, "partial prefix waits")
        expect(engine.pendingCharacterCount == 1, "only partial trigger is retained")
        expect(engine.consume("@GMAIL")?.replacement == "abc@gmail.com", "matching ignores case")
        expect(engine.pendingCharacterCount == 0, "a completed match clears pending input")

        engine.reset()
        _ = engine.consume("@@gmai")
        engine.deleteBackward()
        expect(engine.pendingCharacterCount == 5, "backspace updates partial trigger")
        expect(engine.consume("il")?.trigger == "@@gmail", "typing can continue after backspace")

        engine.reset()
        let match = engine.consume("prefix@@gmail")
        expect(match?.deletionCount == 7, "match deletes the complete trigger")
        expect(match?.replacement == "abc@gmail.com", "match returns replacement text")

        let trimmed = try! TextReplacementValidator.normalizedRule(
            TextReplacementRule(keyword: "  work  ", replacement: "hello"), among: [])
        expect(trimmed.keyword == "work", "keywords trim surrounding whitespace")
        expectThrows("duplicate keywords are rejected") {
            _ = try TextReplacementValidator.normalizedRule(
                TextReplacementRule(keyword: "GMAIL", replacement: "other"), among: [gmail])
        }
        expectThrows("prefix-conflicting keywords are rejected") {
            _ = try TextReplacementValidator.normalizedRule(
                TextReplacementRule(keyword: "g", replacement: "other"), among: [gmail])
        }
        expectThrows("whitespace inside a keyword is rejected") {
            _ = try TextReplacementValidator.normalizedRule(
                TextReplacementRule(keyword: "work mail", replacement: "other"), among: [])
        }

        let suiteName = "TextReplacementTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = TextReplacementStore(defaults: defaults)
        expect(store.prefix == "@@", "store starts with the default prefix")
        try! store.setPrefix(";;")
        try! store.add(gmail)
        let restored = TextReplacementStore(defaults: defaults)
        expect(restored.prefix == ";;", "prefix persists")
        expect(restored.rules == [gmail], "replacement pairs persist")

        print("Text Replacement: \(passed) passed, \(failed) failed")
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
