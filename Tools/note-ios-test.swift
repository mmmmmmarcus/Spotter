import Foundation

@main
struct NoteIOSTests {
    static func main() {
        var failures = 0

        func check<T: Equatable>(_ message: String, _ expected: T, _ actual: T) {
            if expected == actual {
                print("PASS  \(message)")
            } else {
                failures += 1
                print("FAIL  \(message): expected \(expected), got \(actual)")
            }
        }

        // The editor's real evaluator, so an answered line here is the one the app would write.
        func evaluate(_ expression: String) -> String? {
            guard let result = CalcEngine.evaluate(expression), case .value(let display, _) = result.payload
            else { return nil }
            return display
        }
        func length(_ text: String) -> Int { (text as NSString).length }
        func range(_ location: Int, _ length: Int = 0) -> NSRange { NSRange(location: location, length: length) }
        /// A key typed, or text pasted, at a bare caret.
        func typing(_ typed: String, into text: String, at caret: Int? = nil, concealed: [NSRange] = []) -> NoteInputDecision {
            let caret = range(caret ?? length(text))
            return NoteInputRules.decision(
                replacing: caret, with: typed, in: text, selection: caret, concealedSuffixes: concealed,
                evaluate: evaluate)
        }
        /// Backspace with a bare caret, as UIKit reports it: the one character before the caret.
        func backspace(in text: String, at caret: Int? = nil) -> NoteInputDecision {
            let caret = caret ?? length(text)
            return NoteInputRules.decision(
                replacing: range(caret - 1, 1), with: "", in: text, selection: range(caret), evaluate: evaluate)
        }
        func replacing(_ replaced: NSRange, with text: String, in source: String) -> NoteInputDecision {
            NoteInputRules.decision(
                replacing: replaced, with: text, in: source, selection: replaced, evaluate: evaluate)
        }
        func command(_ command: NoteTouchCommand, _ text: String, _ selection: NSRange) -> NoteEditResult? {
            NoteInputRules.applying(command, to: text, selection: selection)
        }

        check("ordinary typing is left to the keyboard", .allow, typing("a", into: "# Title\nbody"))

        // The leading `# ` is the Note's title marker and cannot be typed away.
        check("backspace cannot eat the title marker", .reject, backspace(in: "# Title", at: 2))
        check("backspace inside the marker is refused", .reject, backspace(in: "# Title", at: 1))
        check("typing before the marker lands after it", .replace(range(2), "a"), typing("a", into: "# Title", at: 0))
        check("deleting everything keeps the marker", .replace(range(2, 9), ""), replacing(range(0, 11), with: "", in: "# Title\nabc"))
        check("replacing everything keeps the marker", .replace(range(2, 5), "Hello"), replacing(range(0, 7), with: "Hello", in: "# Title"))
        check("pasting a whole titled Note is allowed", .allow, replacing(range(0, 7), with: "# New\nbody", in: "# Title"))
        check("backspace in the title's text is ordinary", .allow, backspace(in: "# Title"))

        check("Return is refused in an untitled Note", .reject, typing("\n", into: "# "))
        check("Return ends a written title", .allow, typing("\n", into: "# Title"))
        check("Return in the body of an untitled Note is ordinary", .allow, typing("\n", into: "# \nbody"))

        check("Return continues a bullet", .replace(range(11), "\n- "), typing("\n", into: "# T\n- first"))
        check("Return increments a number", .replace(range(11), "\n10. "), typing("\n", into: "# T\n9. nine"))
        check("Return resets a completed todo", .replace(range(14), "\n- [ ] "), typing("\n", into: "# T\n- [x] done"))
        check("Return keeps an indented list indented", .replace(range(9), "\n  - "), typing("\n", into: "# T\n  - a"))
        check("Return mid-item carries the suffix into a new item", .replace(range(8), "\n- "), typing("\n", into: "# T\n- abcd", at: 8))
        check("Return on an empty item ends the list", .replace(range(4, 2), ""), typing("\n", into: "# T\n- "))
        check("Return on an empty todo ends the list", .replace(range(4, 6), ""), typing("\n", into: "# T\n- [ ] "))
        check("Return inside a marker is ordinary", .allow, typing("\n", into: "# T\n- abc", at: 5))
        check("Return on prose is ordinary", .allow, typing("\n", into: "# T\nplain"))
        check("an ideographic space is not an empty item", .replace(range(7), "\n- "), typing("\n", into: "# T\n- \u{3000}"))

        // `**bold**` hides its closing marker; a Return at the visual end must not land inside it.
        check("Return steps over a hidden closing marker", .replace(range(12), "\n"),
            typing("\n", into: "# T\n**bold**", at: 10, concealed: [range(10, 2)]))
        check("Return steps over it before continuing a list", .replace(range(14), "\n- "),
            typing("\n", into: "# T\n- **bold**", at: 12, concealed: [range(12, 2)]))
        check("a stale hidden marker is ignored", .allow, typing("\n", into: "# T\nplain", at: 9, concealed: [range(9, 4)]))

        check("bare brackets become a todo", .replace(range(4, 2), "- [ ] "), typing(" ", into: "# T\n[]"))
        check("brackets replace an existing bullet", .replace(range(4, 4), "- [ ] "), typing(" ", into: "# T\n- []"))
        check("Chinese brackets become a todo", .replace(range(4, 2), "- [ ] "), typing(" ", into: "# T\n【】"))
        check("an indented todo keeps its indentation", .replace(range(4, 4), "  - [ ] "), typing(" ", into: "# T\n  []"))
        check("brackets in a sentence are ordinary", .allow, typing(" ", into: "# T\nsee []"))

        check("the third dash completes a rule", .replace(range(6), "-\n"), typing("-", into: "# T\n--"))
        check("a fourth dash is just a dash", .allow, typing("-", into: "# T\n---"))
        check("a rule is not completed mid-line", .allow, typing("-", into: "# T\n--x", at: 6))

        check("a sum answers itself", .replace(range(8), "=15"), typing("=", into: "# T\n12+3"))
        check("a full-width equals answers in kind", .replace(range(8), "＝15"), typing("＝", into: "# T\n12+3"))
        check("a list marker is not part of the sum", .replace(range(10), "=15"), typing("=", into: "# T\n- 12+3"))
        check("a sum after Chinese text answers", .replace(range(11), "=15"), typing("=", into: "# T\n总计：12+3"))
        check("a formula that cannot be answered says so", .replace(range(12), "=(?)"), typing("=", into: "# T\n12+3*(4+"))
        check("an equals after prose is ordinary", .allow, typing("=", into: "# T\nname"))
        check("an identifier is not a sum", .allow, typing("=", into: "# T\nrev2+3"))

        let refreshed = NoteInputRules.arithmeticRefresh(in: "# T\n12+4=15", caret: range(8), evaluate: evaluate)
        check("an edited sum rewrites its answer", range(9, 2), refreshed?.range)
        check("the rewritten answer is the new result", "16", refreshed?.answer)
        check("a correct answer is left alone", true,
            NoteInputRules.arithmeticRefresh(in: "# T\n12+3=15", caret: range(8), evaluate: evaluate) == nil)
        check("the answer itself is the user's to edit", true,
            NoteInputRules.arithmeticRefresh(in: "# T\n12+4=15", caret: range(10), evaluate: evaluate) == nil)
        check("a broken sum is marked unresolved", "(?)",
            NoteInputRules.arithmeticRefresh(in: "# T\n12+=15", caret: range(7), evaluate: evaluate)?.answer)
        check("a line that is not a sum is never rewritten", true,
            NoteInputRules.arithmeticRefresh(in: "# T\nplain", caret: range(6), evaluate: evaluate) == nil)

        check("backspace after a todo marker takes the whole marker", .replace(range(4, 6), ""), backspace(in: "# T\n- [ ] "))
        check("backspace after an indented bullet takes its indentation too", .replace(range(4, 6), ""), backspace(in: "# T\n    - "))
        check("backspace in an item's text is ordinary", .allow, backspace(in: "# T\n- ab"))
        check("deleting a selected character is ordinary", .allow, replacing(range(9, 1), with: "", in: "# T\n- [ ] "))
        check("backspace inside a fence is ordinary", .allow, backspace(in: "# T\n```\n- ", at: 10))

        check("a pasted list replaces the empty item it lands in", .replace(range(4, 2), "- a\n- b"),
            replacing(range(6), with: "- a\n- b", in: "# T\n- "))
        check("a pasted list after text is ordinary", .allow, replacing(range(8), with: "- a\n- b", in: "# T\n- ab"))
        check("pasted prose is ordinary", .allow, replacing(range(6), with: "plain text", in: "# T\n- "))
        check("an autocorrection is ordinary", .allow, replacing(range(4, 3), with: "the", in: "# T\nteh"))

        // The accessory bar: a blank line is where a list starts, and a caret stays a caret.
        check("checklist starts a todo on a blank line", NoteEditResult(text: "# T\n- [ ] ", selection: range(10)),
            command(.checklist, "# T\n", range(4)))
        check("checklist starts a todo on a blank middle line", NoteEditResult(text: "# T\n- [ ] \nend", selection: range(10)),
            command(.checklist, "# T\n\nend", range(4)))
        check("checklist replaces a bullet rather than nesting", NoteEditResult(text: "# T\n- [ ] milk", selection: range(14)),
            command(.checklist, "# T\n- milk", range(7)))
        check("checklist replaces a number", NoteEditResult(text: "# T\n- [ ] milk", selection: range(14)),
            command(.checklist, "# T\n1. milk", range(7)))
        check("checklist on a todo takes the marker off", NoteEditResult(text: "# T\nmilk", selection: range(8)),
            command(.checklist, "# T\n- [x] milk", range(12)))
        check("checklist covers every selected line", NoteEditResult(text: "# T\n- [ ] a\n- [ ] b", selection: range(4, 15)),
            command(.checklist, "# T\na\nb", range(4, 3)))
        check("bullets start a list on a blank line", NoteEditResult(text: "# T\n- ", selection: range(6)),
            command(.block(.bulletedList), "# T\n", range(4)))
        check("bullets format a written line", NoteEditResult(text: "# T\n- milk", selection: range(10)),
            command(.block(.bulletedList), "# T\nmilk", range(6)))
        check("bullets on a bullet take the marker off", NoteEditResult(text: "# T\nmilk", selection: range(8)),
            command(.block(.bulletedList), "# T\n- milk", range(8)))
        check("bullets turn a todo into a bullet", NoteEditResult(text: "# T\n- milk", selection: range(10)),
            command(.block(.bulletedList), "# T\n- [ ] milk", range(12)))
        check("numbers stay continuous across a selection", NoteEditResult(text: "# T\n1. a\n2. b", selection: range(4, 9)),
            command(.block(.numberedList), "# T\na\nb", range(4, 3)))
        check("numbers on a numbered list take the markers off", NoteEditResult(text: "# T\na\nb", selection: range(4, 3)),
            command(.block(.numberedList), "# T\n1. a\n2. b", range(4, 9)))
        check("a heading starts on a blank line", NoteEditResult(text: "# T\n## ", selection: range(7)),
            command(.block(.heading2), "# T\n", range(4)))
        check("a heading replaces a list marker", NoteEditResult(text: "# T\n### milk", selection: range(12)),
            command(.block(.heading3), "# T\n- milk", range(8)))
        check("Text takes a heading off", NoteEditResult(text: "# T\nmilk", selection: range(8)),
            command(.block(.text), "# T\n## milk", range(8)))
        check("Text on plain text changes nothing", nil, command(.block(.text), "# T\nmilk", range(6)))

        check("the title line refuses a list", nil, command(.block(.bulletedList), "# Title", range(7)))
        check("an empty title refuses a todo", nil, command(.checklist, "# ", range(2)))
        check("the title line refuses another heading level", nil, command(.block(.heading2), "# Title\nbody", range(3)))
        check("a selection from the title formats only the body", NoteEditResult(text: "# T\n- a\n- b", selection: range(4, 7)),
            command(.block(.bulletedList), "# T\na\nb", range(0, 7)))
        check("the title line cannot be indented", nil, command(.indent(.indent), "# T\n- a", range(2)))

        check("bold wraps a selection", NoteEditResult(text: "# T\n**milk**", selection: range(6, 4)),
            command(.inline(.bold), "# T\nmilk", range(4, 4)))
        check("bold at a caret offers a placeholder", NoteEditResult(text: "# T\n**bold text**", selection: range(6, 9)),
            command(.inline(.bold), "# T\n", range(4)))
        check("bold on bold text takes the markers off", NoteEditResult(text: "# T\nmilk", selection: range(4, 4)),
            command(.inline(.bold), "# T\n**milk**", range(6, 4)))
        check("select-all bold never wraps the title marker", NoteEditResult(text: "# **Title**", selection: range(4, 5)),
            command(.inline(.bold), "# Title", range(0, 7)))
        check("a link keeps its label selected", NoteEditResult(text: "# T\n[site](https://)", selection: range(5, 4)),
            command(.inline(.link), "# T\nsite", range(4, 4)))

        check("indent nests a list line", NoteEditResult(text: "# T\n  - a", selection: range(9)),
            command(.indent(.indent), "# T\n- a", range(7)))
        check("outdent un-nests it", NoteEditResult(text: "# T\n- a", selection: range(7)),
            command(.indent(.outdent), "# T\n  - a", range(9)))
        check("indent leaves prose alone", nil, command(.indent(.indent), "# T\nplain", range(6)))

        func difference(_ old: String, _ new: String) -> NoteEditResult {
            let change = NoteInputRules.difference(from: old, to: new)
            return NoteEditResult(text: change.replacement, selection: change.range)
        }
        check("an insertion is its own smallest edit", NoteEditResult(text: "- ", selection: range(4)), difference("# T\nmilk", "# T\n- milk"))
        check("a removal is its own smallest edit", NoteEditResult(text: "", selection: range(4, 2)), difference("# T\n- milk", "# T\nmilk"))
        check("identical text is an empty edit", NoteEditResult(text: "", selection: range(4)), difference("# T\n", "# T\n"))
        check("a repeated character is not replaced twice", NoteEditResult(text: "a", selection: range(2)), difference("aa", "aaa"))
        check("an emoji is replaced whole, never half", NoteEditResult(text: "😁", selection: range(1, 2)), difference("a😀b", "a😁b"))
        for (old, new) in [("# T\n- [ ] a\nb", "# T\na\nb"), ("# 周会 📝", "# 周会 ✅ 📝"), ("", "# "), ("# x", "")] {
            let change = NoteInputRules.difference(from: old, to: new)
            check("applying the edit to \(old.debugDescription) gives \(new.debugDescription)", new,
                (old as NSString).replacingCharacters(in: change.range, with: change.replacement))
        }

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
