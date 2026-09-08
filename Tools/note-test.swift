import Foundation

@main
struct NoteTests {
    @MainActor
    static func main() async {
        var failures = 0

        func check<T: Equatable>(_ message: String, _ expected: T, _ actual: T) {
            if expected == actual {
                print("PASS  \(message)")
            } else {
                failures += 1
                print("FAIL  \(message): expected \(expected), got \(actual)")
            }
        }

        check("heading title", "Meeting Notes", NoteEngine.title(in: "# Meeting Notes\nAgenda"))
        check("todo title", "Ship the plugin", NoteEngine.title(in: "- [ ] Ship the plugin"))
        check("empty title", "Untitled Note", NoteEngine.title(in: " \n\t"))
        check(
            "only first line is title", "Untitled Note",
            NoteEngine.title(in: "\nSecond line is body"))
        check(
            "sidebar excerpt skips title", "First point Second point",
            NoteEngine.excerpt(in: "# Plan\n- First point\n- Second point"))
        check("empty editor has three rows", 3, NoteEngine.editorLineCount(in: ""))
        check("editor follows line count", 7, NoteEngine.editorLineCount(in: "1\n2\n3\n4\n5\n6\n7"))
        check(
            "editor caps at twenty rows", 20,
            NoteEngine.editorLineCount(in: Array(repeating: "line", count: 24).joined(separator: "\n")))
        check(
            "bullet continues", .continueWith("- "),
            NoteEngine.listContinuation(after: "- first"))
        check(
            "indented checklist continues unchecked", .continueWith("  - [ ] "),
            NoteEngine.listContinuation(after: "  - [x] done"))
        check(
            "numbered list increments", .continueWith("10. "),
            NoteEngine.listContinuation(after: "9. ninth"))
        check(
            "empty bullet exits list", .endList,
            NoteEngine.listContinuation(after: "- "))
        check(
            "plain line does not continue", nil,
            NoteEngine.listContinuation(after: "plain text"))

        let bold = NoteEngine.applying(
            .bold, to: "hello world", selection: NSRange(location: 6, length: 5))
        check("bold text", "hello **world**", bold.text)
        check("bold selection", NSRange(location: 8, length: 5), bold.selection)
        let unbold = NoteEngine.applying(.bold, to: bold.text, selection: bold.selection)
        check("toggle bold", "hello world", unbold.text)

        let unicode = "hello 👋"
        let waveRange = (unicode as NSString).range(of: "👋")
        check(
            "unicode range", "hello *👋*",
            NoteEngine.applying(.italic, to: unicode, selection: waveRange).text)

        check(
            "checklist lines", "- [ ] one\n- [ ] two",
            NoteEngine.applying(
                .checklist, to: "one\ntwo", selection: NSRange(location: 0, length: 7)
            ).text)
        check(
            "toggle checklist", "one\ntwo",
            NoteEngine.applying(
                .checklist, to: "- [ ] one\n- [ ] two", selection: NSRange(location: 0, length: 19)
            ).text)
        check(
            "numbered lines", "1. one\n2. two",
            NoteEngine.applying(
                .numberedList, to: "one\ntwo", selection: NSRange(location: 0, length: 7)
            ).text)
        check(
            "context format converts mixed blocks to body text", "one\ntwo\nthree\nfour",
            NoteEngine.applyingBlockFormat(
                NoteBlockFormat.text, to: "# one\n- two\n3. three\n- [ ] four",
                selection: NSRange(location: 0, length: 33)
            ).text)
        check(
            "context format converts lines to heading 1", "# one\n# two",
            NoteEngine.applyingBlockFormat(
                NoteBlockFormat.heading1, to: "one\n2. two",
                selection: NSRange(location: 0, length: 10)
            ).text)
        check(
            "context format converts heading 1 to heading 2", "## one",
            NoteEngine.applyingBlockFormat(
                NoteBlockFormat.heading2, to: "# one",
                selection: NSRange(location: 0, length: 5)
            ).text)
        check(
            "context format converts heading 2 to heading 3", "### one",
            NoteEngine.applyingBlockFormat(
                NoteBlockFormat.heading3, to: "## one",
                selection: NSRange(location: 0, length: 6)
            ).text)
        check(
            "context format converts lines to bullets", "- one\n  - two",
            NoteEngine.applyingBlockFormat(
                NoteBlockFormat.bulletedList, to: "## one\n  7. two",
                selection: NSRange(location: 0, length: 15)
            ).text)
        check(
            "context format renumbers nonempty lines", "1. one\n\n2. two",
            NoteEngine.applyingBlockFormat(
                NoteBlockFormat.numberedList, to: "- one\n\n# two",
                selection: NSRange(location: 0, length: 13)
            ).text)
        check(
            "link", "Read [Spotter](https://)",
            NoteEngine.applying(
                .link, to: "Read Spotter", selection: NSRange(location: 5, length: 7)
            ).text)

        check("bare brackets become a todo", "- [ ] ", NoteEngine.checklistInputRule(forLinePrefix: "[]"))
        check(
            "brackets keep their indentation", "  - [ ] ",
            NoteEngine.checklistInputRule(forLinePrefix: "  []"))
        check(
            "brackets replace an existing bullet", "- [ ] ",
            NoteEngine.checklistInputRule(forLinePrefix: "- []"))
        check(
            "Chinese brackets become a todo after space", "- [ ] ",
            NoteEngine.checklistInputRule(forLinePrefix: "【】"))
        check(
            "spaced Chinese brackets become a todo when closed", "- [ ] ",
            NoteEngine.checklistInputRule(forLinePrefix: "【 ", inserting: "】"))
        check(
            "full-width spaced Chinese brackets become a todo when closed", "  - [ ] ",
            NoteEngine.checklistInputRule(forLinePrefix: "  【　", inserting: "】"))
        check(
            "full-width brackets become a todo after space", "- [ ] ",
            NoteEngine.checklistInputRule(forLinePrefix: "［］"))
        check(
            "spaced full-width brackets become a todo when closed", "- [ ] ",
            NoteEngine.checklistInputRule(forLinePrefix: "［　", inserting: "］"))
        check("text before brackets is left alone", nil, NoteEngine.checklistInputRule(forLinePrefix: "a []"))
        check("a lone bracket is not a todo", nil, NoteEngine.checklistInputRule(forLinePrefix: "["))

        check("plain sum", "129+92", NoteEngine.arithmeticExpression(inLinePrefix: "129+92"))
        check(
            "sum after prose", "129+92",
            NoteEngine.arithmeticExpression(inLinePrefix: "Total: 129+92"))
        check(
            "a bullet is not a negation", "12+3",
            NoteEngine.arithmeticExpression(inLinePrefix: "- 12+3"))
        check(
            "a numbered marker is not part of the sum", "12+3",
            NoteEngine.arithmeticExpression(inLinePrefix: "3. 12+3"))
        check("a decimal survives", "1.5*2", NoteEngine.arithmeticExpression(inLinePrefix: "1.5*2"))
        check("digits glued to a word are an identifier", nil, NoteEngine.arithmeticExpression(inLinePrefix: "rev2+3"))
        check("a bare number is not a sum", nil, NoteEngine.arithmeticExpression(inLinePrefix: "129"))
        check("prose does not calculate", nil, NoteEngine.arithmeticExpression(inLinePrefix: "meeting"))
        check("a trailing operator is incomplete", nil, NoteEngine.arithmeticExpression(inLinePrefix: "129+"))
        check(
            "a sum glued to Chinese text is still a sum", "12+3",
            NoteEngine.arithmeticExpression(inLinePrefix: "总计12+3"))
        check(
            "a full-width colon ends the word before a sum", "12+3",
            NoteEngine.arithmeticExpression(inLinePrefix: "总计：12+3"))
        check(
            "a sum after Japanese text is still a sum", "1.5*2",
            NoteEngine.arithmeticExpression(inLinePrefix: "ごうけい1.5*2"))
        check(
            "an ASCII word still swallows the digits glued to it", nil,
            NoteEngine.arithmeticExpression(inLinePrefix: "total12+3"))
        check("an ASCII equals answers a sum", true, NoteEngine.isArithmeticEquals("="))
        check("a full-width equals answers a sum", true, NoteEngine.isArithmeticEquals("＝"))
        check("a letter is not an equals", false, NoteEngine.isArithmeticEquals("e"))

        let blocks = "Title\n> quoted\n---\n```swift\n- kept\n```\n| a | b |\n| --- | --- |\n| 1 | 2 |"
        let spans = NoteEngine.blockSpans(in: blocks)
        check(
            "block kinds in source order",
            [.quote, .rule, .codeBlock, .codeFence, .codeFence, .tableRow, .tableRow, .tableRow],
            spans.map(\.kind))
        check("quote marker covers \"> \"", NSRange(location: 6, length: 2), spans[0].markerRange)
        check("rule spans its own line", NSRange(location: 15, length: 3), spans[1].range)
        check("code block spans both fences", NSRange(location: 19, length: 19), spans[2].range)
        check("table starts at its header", NSRange(location: 39, length: 9), spans[5].range)
        check(
            "a fence shadows the blocks inside it", [.codeBlock, .codeFence, .codeFence],
            NoteEngine.blockSpans(in: "```\n---\n> not a quote\n```").map(\.kind))
        check(
            "an unterminated fence runs to the end", [.codeBlock, .codeFence],
            NoteEngine.blockSpans(in: "```\nstill code").map(\.kind))
        check("a bullet is not a rule", [], NoteEngine.blockSpans(in: "- item\n- item").map(\.kind))
        check(
            "a pipe needs a delimiter row to be a table", [],
            NoteEngine.blockSpans(in: "cats | dogs\nboth are fine").map(\.kind))

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spotter-note-tests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("notes.json")
        let suiteName = "spotter.note.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let store = NoteStore(fileURL: fileURL, defaults: defaults, now: { fixedDate })
        check("window transparency defaults to zero", 0.0, store.windowTransparency)
        store.setWindowTransparency(0.35)
        check("window transparency updates", 0.35, store.windowTransparency)
        store.updateSelectedContent("# Persisted\nBody")
        await store.flush()
        let reopened = NoteStore(fileURL: fileURL, defaults: defaults, now: { fixedDate })
        check("persist count", 1, reopened.notes.count)
        check("persist content", "# Persisted\nBody", reopened.selectedNote?.content)
        check("window transparency persists", 0.35, reopened.windowTransparency)

        let secondID = reopened.createNote(content: "Second")
        await reopened.flush()
        check("create selects", secondID, reopened.selectedID)
        let previousNote = reopened.selectAdjacent(.previous)
        check("previous note wraps backward through note order", "# Persisted\nBody", previousNote?.content)
        let nextNote = reopened.selectAdjacent(.next)
        check("next note wraps forward through note order", secondID, nextNote?.id)
        if let selected = reopened.selectedNote { reopened.delete(selected) }
        await reopened.flush()
        check("delete note", 1, reopened.notes.count)
        check("delete persists tombstone", 1, reopened.syncSnapshot.tombstones.count)
        let afterDelete = NoteStore(fileURL: fileURL, defaults: defaults, now: { fixedDate })
        check("reopen keeps tombstone", reopened.syncSnapshot.tombstones, afterDelete.syncSnapshot.tombstones)

        let emptyID = reopened.createNote(content: " \n\t")
        check("exit cleanup removes whitespace-only notes", 1, reopened.deleteEmptyNotes())
        check("exit cleanup preserves nonempty notes", 1, reopened.notes.count)
        check("exit cleanup selects a remaining note", reopened.notes.first?.id, reopened.selectedID)
        check(
            "exit cleanup records a tombstone", true,
            reopened.syncSnapshot.tombstones.contains { $0.id == emptyID })

        let synced = SpotterNote(content: "# Synced", createdAt: fixedDate)
        reopened.replace(notes: [synced], selectedID: synced.id)
        await reopened.flush()
        check("sync replaces notes", [synced], reopened.notes)
        check("sync restores selected note", synced.id, reopened.selectedID)

        let document = NoteSyncDocument(notes: reopened.notes, selectedID: reopened.selectedID)
        let encodedDocument = try! document.encoded()
        let decodedDocument = try! NoteSyncDocument(json: encodedDocument)
        check("legacy sync document round-trips", document, decodedDocument)
        check("legacy sync document keeps selection", synced.id, decodedDocument.selectedID)

        let newerDate = fixedDate.addingTimeInterval(60)
        let remoteEdit = SpotterNote(
            id: synced.id, content: "# Remote", createdAt: fixedDate, updatedAt: newerDate)
        reopened.applyRemoteSnapshot(NoteSyncSnapshot(notes: [remoteEdit], tombstones: []))
        check("newer remote edit wins", "# Remote", reopened.selectedNote?.content)
        let tiedDeletion = NoteTombstone(id: synced.id, deletedAt: newerDate)
        reopened.applyRemoteSnapshot(NoteSyncSnapshot(notes: [], tombstones: [tiedDeletion]))
        check("deletion wins an exact timestamp tie", nil, reopened.selectedNote)

        let olderEdit = SpotterNote(
            id: synced.id, content: "# Older", createdAt: fixedDate, updatedAt: fixedDate)
        let merged = NoteSyncMerge.merging(
            NoteSyncSnapshot(notes: [], tombstones: [tiedDeletion]),
            with: NoteSyncSnapshot(notes: [olderEdit], tombstones: []))
        check("older edit cannot resurrect a deletion", 0, merged.notes.count)

        let futureDocument = Data(
            "{\"version\":2,\"notes\":[],\"selectedID\":null}".utf8)
        let rejectsFutureDocument: Bool
        do {
            _ = try NoteSyncDocument(json: futureDocument)
            rejectsFutureDocument = false
        } catch {
            rejectsFutureDocument = true
        }
        check("newer sync documents are rejected", true, rejectsFutureDocument)

        check(
            "a third dash completes a rule and opens the line under it", "-\n",
            NoteEngine.horizontalRuleCompletion(forLinePrefix: "--", inserting: "-"))
        check(
            "a fourth dash is just a dash", nil,
            NoteEngine.horizontalRuleCompletion(forLinePrefix: "---", inserting: "-"))
        check(
            "a bullet is not a rule", nil,
            NoteEngine.horizontalRuleCompletion(forLinePrefix: "- item", inserting: "-"))
        check(
            "underscores rule too", "_\n",
            NoteEngine.horizontalRuleCompletion(forLinePrefix: "__", inserting: "_"))

        check(
            "an answered sum reports its expression", "129+92",
            NoteEngine.arithmeticAnswer(inLine: "129+92=221")?.expression)
        check(
            "an answered sum reports its answer", "221",
            NoteEngine.arithmeticAnswer(inLine: "129+92=221")?.result)
        check(
            "a broken formula still reports, so the editor can mark it", "12+",
            NoteEngine.arithmeticAnswer(inLine: "12+=(?)")?.expression)
        check(
            "an answer inside a list item drops its marker when evaluated", "2+2",
            NoteEngine.arithmeticAnswer(inLine: "- [ ] 2+2=4")
                .flatMap { NoteEngine.arithmeticExpression(inLinePrefix: $0.expression) })
        check(
            "prose with an equals sign is not an answer", nil,
            NoteEngine.arithmeticAnswer(inLine: "todo = ship it"))
        check(
            "an unanswered sum is left alone", nil,
            NoteEngine.arithmeticAnswer(inLine: "129+92="))
        check(
            "a dangling operator is still a formula", "12+",
            NoteEngine.arithmeticCandidate(inLinePrefix: "12+"))
        check(
            "prose is not a formula", nil,
            NoteEngine.arithmeticCandidate(inLinePrefix: "ship it "))
        check(
            "a quantity is not a formula", nil,
            NoteEngine.arithmeticCandidate(inLinePrefix: "5 kg "))
        check(
            "a URL is not an answer", nil,
            NoteEngine.arithmeticAnswer(inLine: "https://example.com/x=1"))
        check(
            "a full-width equals keeps its line answered", "129+92",
            NoteEngine.arithmeticAnswer(inLine: "129+92＝221")?.expression)
        check(
            "a full-width equals reports its answer", "221",
            NoteEngine.arithmeticAnswer(inLine: "129+92＝221")?.result)
        check(
            "a Chinese line keeps its answer", "12+3",
            NoteEngine.arithmeticAnswer(inLine: "总计：12+3=15")
                .flatMap { NoteEngine.arithmeticExpression(inLinePrefix: $0.expression) })
        check(
            "Chinese prose with an equals sign is not an answer", nil,
            NoteEngine.arithmeticAnswer(inLine: "待办＝发布"))
        check("a Chinese title survives markup stripping", "会议记录", NoteEngine.title(in: "# 会议记录\n正文"))
        check(
            "a Chinese checklist continues", .continueWith("- [ ] "),
            NoteEngine.listContinuation(after: "- [ ] 写文档"))
        // Return on an item that "looks" empty deletes the whole line, so what counts as empty may
        // only ever be the ASCII blanks Markdown pads with. An input method in full-width mode types
        // U+3000 for the space bar, and `CharacterSet.whitespaces` counts it — and a non-breaking
        // space — as blank, which silently deleted a character the user had typed.
        check(
            "an ideographic space is content, not an empty item", .continueWith("- "),
            NoteEngine.listContinuation(after: "- \u{3000}"))
        check(
            "an ideographic space keeps a checklist item", .continueWith("- [ ] "),
            NoteEngine.listContinuation(after: "- [ ] \u{3000}\u{3000}"))
        check(
            "an ideographic space keeps a numbered item", .continueWith("3. "),
            NoteEngine.listContinuation(after: "2. \u{3000}"))
        check(
            "a non-breaking space is content too", .continueWith("- "),
            NoteEngine.listContinuation(after: "- \u{00A0}"))
        check(
            "ASCII padding still exits the list", .endList,
            NoteEngine.listContinuation(after: "-  \t "))

        // Decorations are collected by a pass that stands down while an input method holds a
        // composition, so they have to be moved onto the text as it stands now. An insertion before
        // a marker shifts it, one after it leaves it alone, and an edit through it drops it — a disc
        // drawn from an unadjusted range lands on the composing text while its own marker, cleared
        // by the same pass, is never drawn at all.
        let marker = NSRange(location: 4, length: 1)
        check(
            "a marker after an insertion shifts", NSRange(location: 9, length: 1),
            NoteEngine.adjusting(
                marker, forEdit: NSRange(location: 3, length: 0), changeInLength: 5,
                documentLength: 20))
        check(
            "a marker before an insertion stays", marker,
            NoteEngine.adjusting(
                marker, forEdit: NSRange(location: 6, length: 0), changeInLength: 5,
                documentLength: 20))
        check(
            "an insertion at a marker's own start shifts it", NSRange(location: 6, length: 1),
            NoteEngine.adjusting(
                marker, forEdit: NSRange(location: 4, length: 0), changeInLength: 2,
                documentLength: 20))
        check(
            "an insertion at a marker's own end leaves it", marker,
            NoteEngine.adjusting(
                marker, forEdit: NSRange(location: 5, length: 0), changeInLength: 2,
                documentLength: 20))
        check(
            "a marker the edit ran through is dropped", nil,
            NoteEngine.adjusting(
                marker, forEdit: NSRange(location: 3, length: 3), changeInLength: -2,
                documentLength: 8))
        check(
            "a marker past the end of the document is dropped", nil,
            NoteEngine.adjusting(
                marker, forEdit: NSRange(location: 0, length: 6), changeInLength: -6,
                documentLength: 0))
        check(
            "a block grows around an edit inside it", NSRange(location: 2, length: 12),
            NoteEngine.adjusting(
                NSRange(location: 2, length: 10), forEdit: NSRange(location: 5, length: 0),
                changeInLength: 2, documentLength: 20))
        check(
            "a block shrinks around a deletion inside it", NSRange(location: 2, length: 7),
            NoteEngine.adjusting(
                NSRange(location: 2, length: 10), forEdit: NSRange(location: 5, length: 3),
                changeInLength: -3, documentLength: 17))

        // Tints: a color is a user modification that syncs, but never one that reorders the list.
        let tintFile = directory.appendingPathComponent("tints.json")
        let tintSuite = "spotter.note.tint.tests.\(UUID().uuidString)"
        let tintDefaults = UserDefaults(suiteName: tintSuite)!
        defer { tintDefaults.removePersistentDomain(forName: tintSuite) }
        var clock = fixedDate
        let tinted = NoteStore(fileURL: tintFile, defaults: tintDefaults, now: { clock })
        tinted.updateSelectedContent("First")
        let firstID = tinted.selectedID!
        clock = fixedDate.addingTimeInterval(10)
        let latestID = tinted.createNote(content: "Second")
        check("a new note starts untinted", nil, tinted.selectedNote?.tint)

        clock = fixedDate.addingTimeInterval(20)
        tinted.setTint(.blue, for: firstID)
        let recolored = tinted.notes.first { $0.id == firstID }
        check("tint applies", NoteTint.blue, recolored?.tint)
        check("tint bumps the sync timestamp", clock, recolored?.updatedAt)
        check("tint leaves the order timestamp alone", fixedDate, recolored?.contentUpdatedAt)
        check("tint does not reorder the list", latestID, tinted.notes.first?.id)
        await tinted.flush()
        let reopenedTints = NoteStore(fileURL: tintFile, defaults: tintDefaults, now: { clock })
        check("tint persists", NoteTint.blue, reopenedTints.notes.first { $0.id == firstID }?.tint)
        check("reopening keeps the untinted order", latestID, reopenedTints.notes.first?.id)
        reopenedTints.setTint(nil, for: firstID)
        check("a tint can be cleared", nil, reopenedTints.notes.first { $0.id == firstID }?.tint)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let legacyNote = Data(
            """
            {"id":"\(firstID.uuidString)","content":"Legacy","createdAt":"2023-11-14T22:13:20Z",\
            "updatedAt":"2023-11-14T22:13:20Z"}
            """.utf8)
        let decodedLegacy = try! decoder.decode(SpotterNote.self, from: legacyNote)
        check("a pre-tint note decodes untinted", nil, decodedLegacy.tint)
        check(
            "a pre-tint note orders by its edit time", decodedLegacy.updatedAt,
            decodedLegacy.contentUpdatedAt)
        let futureTint = Data(
            """
            {"id":"\(firstID.uuidString)","content":"Future","createdAt":"2023-11-14T22:13:20Z",\
            "updatedAt":"2023-11-14T22:13:20Z","tint":"chartreuse"}
            """.utf8)
        let decodedFutureTint = try? decoder.decode(SpotterNote.self, from: futureTint)
        check("an unknown tint reads as untinted rather than failing", "Future", decodedFutureTint?.content)
        check("an unknown tint reads as no tint", nil, decodedFutureTint?.tint ?? nil)

        let redTwin = SpotterNote(
            id: firstID, content: "Same", createdAt: fixedDate, updatedAt: fixedDate, tint: .red)
        let blueTwin = SpotterNote(
            id: firstID, content: "Same", createdAt: fixedDate, updatedAt: fixedDate, tint: .blue)
        check(
            "identical notes with different tints converge",
            NoteSyncMerge.preferred(.note(redTwin), .note(blueTwin)),
            NoteSyncMerge.preferred(.note(blueTwin), .note(redTwin)))

        let bulletLine = "- alpha\n- beta\n"
        let indented = NoteEngine.applyingListIndent(
            .indent, to: bulletLine, selection: NSRange(location: 4, length: 0))
        check(
            "tab mid-line nests the caret's list line",
            "  - alpha\n- beta\n", indented?.text ?? "")
        check(
            "the caret rides its line through the indent",
            NSRange(location: 6, length: 0), indented?.selection ?? NSRange())
        let outdented = NoteEngine.applyingListIndent(
            .outdent, to: "  - alpha\n", selection: NSRange(location: 6, length: 0))
        check("shift-tab removes one indent unit", "- alpha\n", outdented?.text ?? "")
        let tabOutdent = NoteEngine.applyingListIndent(
            .outdent, to: "\t1. one\n", selection: NSRange(location: 3, length: 0))
        check("a legacy tab level outdents whole", "1. one\n", tabOutdent?.text ?? "")
        let span = NoteEngine.applyingListIndent(
            .indent, to: "- a\nplain\n- b\n", selection: NSRange(location: 0, length: 12))
        check(
            "a spanning selection indents only its list lines",
            "  - a\nplain\n  - b\n", span?.text ?? "")
        check(
            "tab on prose is not an indent",
            true, NoteEngine.applyingListIndent(
                .indent, to: "just prose\n", selection: NSRange(location: 3, length: 0)) == nil)

        func deletion(_ text: String, _ caret: Int, _ length: Int = 0) -> NSRange? {
            NoteEngine.listMarkerDeletion(
                in: text, selection: NSRange(location: caret, length: length))
        }
        check("delete takes a whole todo marker", NSRange(location: 0, length: 6), deletion("- [ ] task", 6))
        check("delete takes a whole bullet marker", NSRange(location: 0, length: 2), deletion("- item", 2))
        check("delete takes a starred bullet marker", NSRange(location: 0, length: 2), deletion("* item", 2))
        check("delete takes a whole ordered marker", NSRange(location: 0, length: 3), deletion("1. item", 3))
        check("delete takes a two-digit ordered marker", NSRange(location: 0, length: 4), deletion("10. item", 4))
        check(
            "delete takes an indented todo's indentation with it",
            NSRange(location: 0, length: 8), deletion("  - [ ] task", 8))
        check(
            "delete takes a twice-nested bullet's indentation with it",
            NSRange(location: 0, length: 6), deletion("    - item", 6))
        check(
            "delete takes a legacy tab indent with it",
            NSRange(location: 0, length: 4), deletion("\t1. item", 4))
        check("delete empties an empty item", NSRange(location: 0, length: 2), deletion("- ", 2))
        check("delete empties an empty todo", NSRange(location: 0, length: 6), deletion("- [ ] ", 6))
        check(
            "delete finds the marker on a later line",
            NSRange(location: 6, length: 2), deletion("intro\n- item", 8))
        check("a caret in the item's text deletes normally", nil, deletion("- item", 4))
        check("a caret at the line's start deletes normally", nil, deletion("- item", 0))
        check("a caret opening a later line deletes normally", nil, deletion("intro\n- item", 6))
        check("a caret inside the todo marker deletes normally", nil, deletion("- [ ] task", 4))
        check("a selection deletes normally", nil, deletion("- [ ] task", 6, 4))
        check("prose deletes normally", nil, deletion("plain text", 5))
        check(
            "a marker inside a fence is literal text", nil,
            deletion("```\n- item\n```", 6))
        check("a caret past the end deletes normally", nil, deletion("- item", 99))

        // ── Notes folder sync: format, naming and reconciliation ────────────────────────────────
        // Every removal the reconciler can emit must be one of these two provably safe cases.
        func removalsAreSafe(_ plan: NoteFolderPlan) -> Bool {
            plan.removals.values.allSatisfy {
                switch $0 {
                case .deleted, .redundantDuplicate: true
                }
            }
        }

        let folderClock = fixedDate.addingTimeInterval(1_000)
        var forkCounter = 0
        let formatID = UUID(uuidString: "00000000-0000-0000-0000-0000000000FF")!
        func nextID() -> UUID {
            forkCounter += 1
            return UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", forkCounter))!
        }

        // Round-trip fidelity: the body is the user's Markdown and must come back byte-for-byte.
        let hostileBody = """
            # Title

            ---
            not: front matter
            ---

            ```
            ---
            ```
            trailing spaces   \u{000D}
            emoji 👋 and a tab\tinside

            """
        let roundTripNote = SpotterNote(
            id: formatID, content: hostileBody, createdAt: fixedDate,
            updatedAt: fixedDate.addingTimeInterval(5),
            contentUpdatedAt: fixedDate.addingTimeInterval(5), tint: .mint)
        let roundTripFile = NoteFolderDocument.serialize(roundTripNote)
        switch NoteFolderDocument.parse(roundTripFile, newID: nextID, now: { folderClock }) {
        case .note(let parsed, let extras):
            check("a note round-trips its body byte-for-byte", hostileBody, parsed.content)
            check("a note round-trips its id", roundTripNote.id, parsed.id)
            check("a note round-trips its tint", NoteTint.mint, parsed.tint)
            check("a note round-trips created", roundTripNote.createdAt, parsed.createdAt)
            check("a note round-trips updated", roundTripNote.updatedAt, parsed.updatedAt)
            check(
                "a note round-trips content-updated", roundTripNote.contentUpdatedAt,
                parsed.contentUpdatedAt)
            check("a Spotter header leaves no extras", [], extras)
            check(
                "serialising a parsed note reproduces the file", roundTripFile,
                NoteFolderDocument.serialize(parsed))
        default:
            failures += 1
            print("FAIL  a serialized note parses back as a note")
        }

        // Hostile inputs: nothing here may drop a byte the user wrote.
        func parsedContent(_ text: String) -> String? {
            switch NoteFolderDocument.parse(text, newID: nextID, now: { folderClock }) {
            case .note(let note, _): note.content
            case .adopted(let note): note.content
            case .ignored: nil
            }
        }
        let plainMarkdown = "# Shopping\n- milk\n"
        check("a hand-written file becomes a note", plainMarkdown, parsedContent(plainMarkdown))
        let humanFrontMatter = "---\ntitle: Mine\ntags: [a]\n---\nBody\n"
        check(
            "front matter without a spotter id is body, not a header", humanFrontMatter,
            parsedContent(humanFrontMatter))
        let unclosed = "---\nspotter-id: \(formatID.uuidString)\nstill open\n"
        check("an unclosed fence keeps the whole file", unclosed, parsedContent(unclosed))
        let badID = "---\nspotter-id: not-a-uuid\n---\nBody\n"
        check("a malformed id keeps the whole file", badID, parsedContent(badID))
        check("an empty file is not a note", nil, parsedContent(""))
        check("a whitespace-only file is not a note", nil, parsedContent("  \n\t\n"))
        let unknownTint = "---\nspotter-id: \(formatID.uuidString)\ntint: chartreuse\n---\nBody"
        check("an unknown tint keeps the note", "Body", parsedContent(unknownTint))
        switch NoteFolderDocument.parse(unknownTint, newID: nextID, now: { folderClock }) {
        case .note(let note, _): check("an unknown tint reads as untinted", nil, note.tint)
        default:
            failures += 1
            print("FAIL  an unknown tint still parses as a note")
        }
        let missingDates = "---\nspotter-id: \(formatID.uuidString)\n---\nBody"
        switch NoteFolderDocument.parse(missingDates, newID: nextID, now: { folderClock }) {
        case .note(let note, _):
            check("a header with no dates reads as just-appeared", folderClock, note.updatedAt)
        default:
            failures += 1
            print("FAIL  a header with no dates still parses as a note")
        }
        let withExtras = "---\nspotter-id: \(formatID.uuidString)\nauthor: me\n---\nBody"
        switch NoteFolderDocument.parse(withExtras, newID: nextID, now: { folderClock }) {
        case .note(let note, let extras):
            check("a foreign header line is kept", ["author: me"], extras)
            check(
                "a foreign header line survives a rewrite", true,
                NoteFolderDocument.serialize(note, extras: extras).contains("author: me"))
            check(
                "a foreign line can never close the block", false,
                NoteFolderDocument.serialize(note, extras: ["---", "spotter-id: x"])
                    .contains("spotter-id: x"))
        default:
            failures += 1
            print("FAIL  a foreign header line still parses as a note")
        }

        // Naming.
        check(
            "a name is derived from the title", "Meeting Notes",
            NoteFileName.sanitizedBase(for: "Meeting Notes"))
        check(
            "path separators never reach a name", "Q3 plan 2026",
            NoteFileName.sanitizedBase(for: "Q3/plan: 2026"))
        check("a blank title falls back", "Untitled Note", NoteFileName.sanitizedBase(for: "   "))
        check(
            "a long title is truncated", 60,
            NoteFileName.sanitizedBase(for: String(repeating: "a", count: 200)).count)
        let twins = [
            SpotterNote(id: nextID(), content: "# Same", createdAt: fixedDate),
            SpotterNote(id: nextID(), content: "# Same", createdAt: fixedDate.addingTimeInterval(1)),
        ]
        let twinNames = NoteFileName.names(for: twins)
        check("the oldest note keeps the bare name", "Same.md", twinNames[twins[0].id])
        check("a colliding note takes a suffix", "Same 2.md", twinNames[twins[1].id])
        check(
            "collision resolution is deterministic", twinNames,
            NoteFileName.names(for: twins.reversed()))
        check(
            "a reserved name is stepped over", "Same 2.md",
            NoteFileName.names(for: [twins[0]], reserved: ["same.md"])[twins[0].id])

        // Reconciliation.
        let noteA = SpotterNote(
            id: nextID(), content: "# Alpha\nbody", createdAt: fixedDate, updatedAt: fixedDate)
        let localOnly = NoteSyncSnapshot(notes: [noteA], tombstones: [])

        // A folder that has never seen this note gets it written, not the note dropped.
        let emptyFolderPlan = NoteFolderReconciler.plan(
            local: localOnly, scan: NoteFolderScan(files: []), pass: .steady, newID: nextID,
            now: { folderClock })
        check("an empty folder keeps every local note", 1, emptyFolderPlan.snapshot.notes.count)
        check("an empty folder is written, not read as deletions", 0, emptyFolderPlan.removals.count)
        check(
            "a note with no file yet is written", true,
            emptyFolderPlan.placements.first?.needsWrite == true)
        check(
            "a new file gets the title's name", "Alpha.md",
            emptyFolderPlan.placements.first?.desiredName)

        let blankPlan = NoteFolderReconciler.plan(
            local: NoteSyncSnapshot(
                notes: [SpotterNote(id: nextID(), content: "  ", createdAt: fixedDate)],
                tombstones: []),
            scan: NoteFolderScan(files: []), pass: .steady, newID: nextID, now: { folderClock })
        check("a blank note writes no file", false, blankPlan.hasFileWork)
        check("a blank note is still a note", 1, blankPlan.snapshot.notes.count)

        // A file that exists but has not downloaded is present, not gone.
        let placeholderScan = NoteFolderScan(files: [NoteFolderFile(name: "Alpha.md", contents: nil)])
        let placeholderPlan = NoteFolderReconciler.plan(
            local: localOnly, scan: placeholderScan, pass: .steady, newID: nextID,
            now: { folderClock })
        check("an undownloaded file is deferred", ["Alpha.md"], placeholderPlan.deferred)
        check("an undownloaded file is never removed", 0, placeholderPlan.removals.count)
        check("an undownloaded file keeps its local note", 1, placeholderPlan.snapshot.notes.count)
        check(
            "an undownloaded file's name is not stolen", "Alpha 2.md",
            placeholderPlan.placements.first?.desiredName)

        // A missing file is not a deletion; only the ledger is.
        let liveFile = NoteFolderFile(
            name: "Alpha.md", contents: NoteFolderDocument.serialize(noteA))
        let deletion = NoteTombstone(id: noteA.id, deletedAt: fixedDate.addingTimeInterval(30))
        let deletionPlan = NoteFolderReconciler.plan(
            local: localOnly,
            scan: NoteFolderScan(files: [liveFile], ledger: .readable([deletion])),
            pass: .steady, newID: nextID, now: { folderClock })
        check("a ledger deletion removes the note", 0, deletionPlan.snapshot.notes.count)
        check("a ledger deletion removes its file", 1, deletionPlan.removals.count)
        check(
            "a removal is always an explicit deletion", NoteFolderRemoval.deleted(noteA.id),
            deletionPlan.removals["Alpha.md"])
        check("removals stay provably safe", true, removalsAreSafe(deletionPlan))

        // A newer edit outlives an older deletion, and the ledger follows.
        let revived = SpotterNote(
            id: noteA.id, content: "# Alpha again", createdAt: fixedDate,
            updatedAt: fixedDate.addingTimeInterval(60))
        let revivePlan = NoteFolderReconciler.plan(
            local: NoteSyncSnapshot(notes: [revived], tombstones: []),
            scan: NoteFolderScan(files: [], ledger: .readable([deletion])),
            pass: .steady, newID: nextID, now: { folderClock })
        check("a newer edit outlives an older deletion", 1, revivePlan.snapshot.notes.count)
        check("the ledger drops a beaten tombstone", [], revivePlan.ledger)

        // An unreadable ledger is never rewritten and never deletes anything.
        let blindPlan = NoteFolderReconciler.plan(
            local: localOnly,
            scan: NoteFolderScan(files: [liveFile], ledger: .unavailable),
            pass: .steady, newID: nextID, now: { folderClock })
        check("an unreadable ledger is left alone", nil, blindPlan.ledger)
        check("an unreadable ledger deletes nothing", 0, blindPlan.removals.count)
        check("an unreadable ledger keeps every note", 1, blindPlan.snapshot.notes.count)

        // A retitle is a move, never a delete plus a create.
        let retitled = SpotterNote(
            id: noteA.id, content: "# Beta\nbody", createdAt: fixedDate,
            updatedAt: fixedDate.addingTimeInterval(90))
        let retitlePlan = NoteFolderReconciler.plan(
            local: NoteSyncSnapshot(notes: [retitled], tombstones: []),
            scan: NoteFolderScan(files: [liveFile]), pass: .steady, newID: nextID,
            now: { folderClock })
        check("a retitle moves the file", true, retitlePlan.placements.first?.needsMove == true)
        check("a retitle keeps the same file", "Alpha.md", retitlePlan.placements.first?.currentName)
        check(
            "a retitle renames to the new title", "Beta.md",
            retitlePlan.placements.first?.desiredName)
        check("a retitle removes nothing", 0, retitlePlan.removals.count)

        // Two files under one id.
        let identicalTwin = NoteFolderFile(
            name: "Alpha copy.md", contents: NoteFolderDocument.serialize(noteA))
        let duplicatePlan = NoteFolderReconciler.plan(
            local: localOnly, scan: NoteFolderScan(files: [liveFile, identicalTwin]),
            pass: .steady, newID: nextID, now: { folderClock })
        check("an identical duplicate collapses to one note", 1, duplicatePlan.snapshot.notes.count)
        check("exactly one of the two files is removed", 1, duplicatePlan.removals.count)
        check(
            "the removed copy is the redundant one",
            [NoteFolderRemoval.redundantDuplicate(noteA.id)], Array(duplicatePlan.removals.values))
        check(
            "the survivor still takes the canonical name", "Alpha.md",
            duplicatePlan.placements.first?.desiredName)
        check("removals stay provably safe for duplicates", true, removalsAreSafe(duplicatePlan))

        let divergentTwin = NoteFolderFile(
            name: "Alpha copy.md",
            contents: NoteFolderDocument.serialize(
                SpotterNote(
                    id: noteA.id, content: "# Alpha\ndifferent", createdAt: fixedDate,
                    updatedAt: fixedDate.addingTimeInterval(1))))
        let forkPlan = NoteFolderReconciler.plan(
            local: localOnly, scan: NoteFolderScan(files: [liveFile, divergentTwin]),
            pass: .steady, newID: nextID, now: { folderClock })
        check("a divergent duplicate id keeps both texts", 2, forkPlan.snapshot.notes.count)
        check("a divergent duplicate removes nothing", 0, forkPlan.removals.count)
        check("a divergent duplicate is reported as a fork", 1, forkPlan.forked.count)

        // The first pass after a folder is adopted keeps both sides; every pass after it merges.
        let writtenHere = "# Alpha\nwritten here"
        let writtenThere = "# Alpha\nwritten on the other Mac"
        let divergedLocally = NoteSyncSnapshot(
            notes: [
                SpotterNote(
                    id: noteA.id, content: writtenHere, createdAt: fixedDate,
                    updatedAt: fixedDate.addingTimeInterval(200))
            ], tombstones: [])
        let divergedFile = NoteFolderFile(
            name: "Alpha.md",
            contents: NoteFolderDocument.serialize(
                SpotterNote(
                    id: noteA.id, content: writtenThere, createdAt: fixedDate,
                    updatedAt: fixedDate.addingTimeInterval(100))))
        let adoptionPlan = NoteFolderReconciler.plan(
            local: divergedLocally, scan: NoteFolderScan(files: [divergedFile]), pass: .adoption,
            newID: nextID, now: { folderClock })
        check(
            "the first pass keeps both sides of a divergence", 2, adoptionPlan.snapshot.notes.count)
        check("the first pass reports the loser as a fork", 1, adoptionPlan.forked.count)
        check(
            "the first pass keeps this Mac's text", true,
            adoptionPlan.snapshot.notes.contains { $0.content == writtenHere })
        check(
            "the first pass keeps the folder's text", true,
            adoptionPlan.snapshot.notes.contains { $0.content == writtenThere })
        check("the first pass removes nothing", 0, adoptionPlan.removals.count)
        check("both sides of a divergence get a file", 2, adoptionPlan.placements.count)
        check("removals stay provably safe on the first pass", true, removalsAreSafe(adoptionPlan))

        let steadyPlan = NoteFolderReconciler.plan(
            local: divergedLocally, scan: NoteFolderScan(files: [divergedFile]), pass: .steady,
            newID: nextID, now: { folderClock })
        check("a steady pass still merges to one note", 1, steadyPlan.snapshot.notes.count)
        check(
            "a steady pass lets the newer edit win", writtenHere,
            steadyPlan.snapshot.notes.first?.content)
        check("a steady pass forks nothing", 0, steadyPlan.forked.count)

        // The other direction: the folder is newer, so the copy on this Mac is the one forked.
        let folderIsNewer = NoteFolderFile(
            name: "Alpha.md",
            contents: NoteFolderDocument.serialize(
                SpotterNote(
                    id: noteA.id, content: writtenThere, createdAt: fixedDate,
                    updatedAt: fixedDate.addingTimeInterval(400))))
        let losingLocalPlan = NoteFolderReconciler.plan(
            local: divergedLocally, scan: NoteFolderScan(files: [folderIsNewer]), pass: .adoption,
            newID: nextID, now: { folderClock })
        check(
            "a local copy that loses the first pass is kept too", 2,
            losingLocalPlan.snapshot.notes.count)
        check(
            "the winning file stays where it is", "Alpha.md",
            losingLocalPlan.placements.first { $0.id == noteA.id }?.currentName)
        check(
            "the forked text gets a file of its own", 1,
            losingLocalPlan.placements.filter { $0.currentName == nil }.count)

        // Nothing differs, so the first pass must not manufacture a duplicate.
        let identicalAdoptionPlan = NoteFolderReconciler.plan(
            local: localOnly, scan: NoteFolderScan(files: [liveFile]), pass: .adoption,
            newID: nextID, now: { folderClock })
        check(
            "the first pass keeps one note when nothing differs", 1,
            identicalAdoptionPlan.snapshot.notes.count)
        check(
            "the first pass forks nothing when nothing differs", 0,
            identicalAdoptionPlan.forked.count)
        check(
            "the first pass writes nothing when nothing differs", false,
            identicalAdoptionPlan.hasFileWork)

        // An empty folder has no divergence to keep, so both passes must plan the same thing.
        let emptyAdoptionPlan = NoteFolderReconciler.plan(
            local: localOnly, scan: NoteFolderScan(files: []), pass: .adoption, newID: nextID,
            now: { folderClock })
        check("an empty folder plans the same either way", emptyFolderPlan, emptyAdoptionPlan)

        // An explicit deletion is a decision, not a divergence: the first pass must not undo it.
        let lateDeletion = NoteTombstone(id: noteA.id, deletedAt: fixedDate.addingTimeInterval(500))
        let deletedDivergencePlan = NoteFolderReconciler.plan(
            local: localOnly,
            scan: NoteFolderScan(files: [divergedFile], ledger: .readable([lateDeletion])),
            pass: .adoption, newID: nextID, now: { folderClock })
        check(
            "a won deletion survives the first pass", 0, deletedDivergencePlan.snapshot.notes.count)
        check("a won deletion is never forked back to life", 0, deletedDivergencePlan.forked.count)

        // An external editor changes the body without touching the header.
        let externallyEdited = NoteFolderFile(
            name: "Alpha.md",
            contents: NoteFolderDocument.serialize(
                SpotterNote(
                    id: noteA.id, content: "# Alpha\nedited in BBEdit", createdAt: fixedDate,
                    updatedAt: fixedDate)),
            modifiedAt: fixedDate.addingTimeInterval(500))
        let externalPlan = NoteFolderReconciler.plan(
            local: localOnly, scan: NoteFolderScan(files: [externallyEdited]),
            pass: .steady, newID: nextID, now: { folderClock })
        check(
            "an outside edit is not overwritten", "# Alpha\nedited in BBEdit",
            externalPlan.snapshot.notes.first?.content)

        // A hand-written file joins the folder as a note without disturbing anything else.
        let strayScan = NoteFolderScan(files: [
            liveFile,
            NoteFolderFile(name: "scratch.md", contents: "just some thoughts"),
            NoteFolderFile(name: "empty.md", contents: "\n\n"),
            NoteFolderFile(name: "readme.txt", contents: "not a note"),
        ])
        let strayPlan = NoteFolderReconciler.plan(
            local: localOnly, scan: strayScan, pass: .steady, newID: nextID, now: { folderClock })
        check("a stray Markdown file is adopted", 2, strayPlan.snapshot.notes.count)
        check("a blank stray file is left alone", true, strayPlan.deferred.contains("empty.md"))
        check("nothing stray is ever removed", 0, strayPlan.removals.count)

        // ── Notes folder sync: a real temporary directory ───────────────────────────────────────
        let folder = directory.appendingPathComponent("notes-folder", isDirectory: true)
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let io = NoteFolderIO(trashesRemovedFiles: false)

        let liveNote = SpotterNote(
            id: nextID(), content: hostileBody, createdAt: fixedDate, updatedAt: fixedDate,
            contentUpdatedAt: fixedDate, tint: .blue)
        var diskLocal = NoteSyncSnapshot(notes: [liveNote], tombstones: [])
        var diskPlan = NoteFolderReconciler.plan(
            local: diskLocal, scan: try! await io.scan(folder: folder), pass: .steady,
            newID: nextID, now: { folderClock })
        try! await io.apply(diskPlan, in: folder)
        check(
            "the note reaches the folder under its title", true,
            FileManager.default.fileExists(atPath: folder.appendingPathComponent("Title.md").path))

        let reread = NoteFolderReconciler.plan(
            local: diskLocal, scan: try! await io.scan(folder: folder), pass: .steady,
            newID: nextID, now: { folderClock })
        check("a written folder needs no further work", false, reread.hasFileWork)
        check("a written folder changes no note", diskLocal.notes, reread.snapshot.notes)
        check(
            "the body survives the real write and read", hostileBody,
            reread.snapshot.notes.first?.content)
        check(
            "the tint survives the real write and read", NoteTint.blue,
            reread.snapshot.notes.first?.tint)

        // A retitle on disk moves the file rather than creating a second one.
        let renamedNote = SpotterNote(
            id: liveNote.id, content: "# Renamed\nbody", createdAt: fixedDate,
            updatedAt: fixedDate.addingTimeInterval(120),
            contentUpdatedAt: fixedDate.addingTimeInterval(120), tint: .blue)
        diskLocal = NoteSyncSnapshot(notes: [renamedNote], tombstones: [])
        diskPlan = NoteFolderReconciler.plan(
            local: diskLocal, scan: try! await io.scan(folder: folder), pass: .steady,
            newID: nextID, now: { folderClock })
        try! await io.apply(diskPlan, in: folder)
        let afterRename = try! FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.hasSuffix(".md") }.sorted()
        check("a retitle leaves exactly one file", ["Renamed.md"], afterRename)

        // A file dropped into the folder by hand becomes a note on the next pass.
        try! "# Dropped in\nby hand".write(
            to: folder.appendingPathComponent("dropped.md"), atomically: true, encoding: .utf8)
        diskPlan = NoteFolderReconciler.plan(
            local: diskLocal, scan: try! await io.scan(folder: folder), pass: .steady,
            newID: nextID, now: { folderClock })
        try! await io.apply(diskPlan, in: folder)
        check("a dropped file becomes a note", 2, diskPlan.snapshot.notes.count)
        diskLocal = diskPlan.snapshot
        check(
            "an adopted file is renamed to its title", true,
            FileManager.default.fileExists(
                atPath: folder.appendingPathComponent("Dropped in.md").path))
        let adoptedRoundTrip = NoteFolderReconciler.plan(
            local: diskLocal, scan: try! await io.scan(folder: folder), pass: .steady,
            newID: nextID, now: { folderClock })
        check("an adopted file settles immediately", false, adoptedRoundTrip.hasFileWork)
        check(
            "an adopted file keeps its text", "# Dropped in\nby hand",
            adoptedRoundTrip.snapshot.notes.first { $0.content.hasPrefix("# Dropped in") }?.content)

        // Deleting a note removes its file and records the deletion in the ledger.
        let deletedNote = diskLocal.notes.first { $0.content.hasPrefix("# Dropped in") }!
        diskLocal = NoteSyncSnapshot(
            notes: diskLocal.notes.filter { $0.id != deletedNote.id },
            tombstones: [
                NoteTombstone(id: deletedNote.id, deletedAt: folderClock.addingTimeInterval(300))
            ])
        diskPlan = NoteFolderReconciler.plan(
            local: diskLocal, scan: try! await io.scan(folder: folder), pass: .steady,
            newID: nextID, now: { folderClock })
        try! await io.apply(diskPlan, in: folder)
        check(
            "a deleted note's file goes away", false,
            FileManager.default.fileExists(
                atPath: folder.appendingPathComponent("Dropped in.md").path))
        check(
            "the deletion is recorded in the ledger", true,
            FileManager.default.fileExists(
                atPath: folder.appendingPathComponent(NoteFolderFormat.ledgerFileName).path))

        // A second Mac reading that folder learns the deletion and does not resurrect the note.
        let otherMac = NoteSyncSnapshot(notes: [deletedNote, renamedNote], tombstones: [])
        let otherPlan = NoteFolderReconciler.plan(
            local: otherMac, scan: try! await io.scan(folder: folder), pass: .steady,
            newID: nextID, now: { folderClock })
        check("another Mac applies the deletion", 1, otherPlan.snapshot.notes.count)
        check(
            "another Mac keeps the surviving note", renamedNote.id, otherPlan.snapshot.notes.first?.id)

        // ── The adoption flag, against real defaults and a real folder ──────────────────────────
        let adoptionSuite = "spotter.note.adoption.\(UUID().uuidString)"
        let adoptionDefaults = UserDefaults(suiteName: adoptionSuite)!
        defer { adoptionDefaults.removePersistentDomain(forName: adoptionSuite) }
        let adoption = NoteFolderAdoption(defaults: adoptionDefaults)
        check(
            "a folder nobody just chose reconciles normally", NoteFolderPass.steady, adoption.pass)
        adoption.begin()
        check("choosing a folder starts an adoption", NoteFolderPass.adoption, adoption.pass)
        // A relaunch is nothing more than a second reader over the same persisted defaults.
        check(
            "the adoption survives a relaunch", NoteFolderPass.adoption,
            NoteFolderAdoption(defaults: UserDefaults(suiteName: adoptionSuite)!).pass)

        let adoptedFolder = directory.appendingPathComponent("adopted", isDirectory: true)
        try! FileManager.default.createDirectory(
            at: adoptedFolder, withIntermediateDirectories: true)
        let sharedID = nextID()
        let sharedFile = NoteFolderDocument.serialize(
            SpotterNote(
                id: sharedID, content: "# Shared\nfrom the other Mac", createdAt: fixedDate,
                updatedAt: fixedDate.addingTimeInterval(50)))
        try! sharedFile.write(
            to: adoptedFolder.appendingPathComponent("Shared.md"), atomically: true,
            encoding: .utf8)
        let adoptingLocal = NoteSyncSnapshot(
            notes: [
                SpotterNote(
                    id: sharedID, content: "# Shared\nfrom this Mac", createdAt: fixedDate,
                    updatedAt: fixedDate.addingTimeInterval(80))
            ], tombstones: [])
        let firstPass = NoteFolderReconciler.plan(
            local: adoptingLocal, scan: try! await io.scan(folder: adoptedFolder),
            pass: adoption.pass, newID: nextID, now: { folderClock })
        check("an adopted folder's divergence is kept whole", 2, firstPass.snapshot.notes.count)

        // The folder vanishes between the plan and the write, which is the manager's failure path:
        // it clears the flag only past `io.apply`, so the pass stays an adoption.
        try! FileManager.default.removeItem(at: adoptedFolder)
        var applyFailed = false
        do { try await io.apply(firstPass, in: adoptedFolder) } catch { applyFailed = true }
        if !applyFailed { adoption.finish() }
        check("a pass that cannot write fails", true, applyFailed)
        check("a failed pass leaves the adoption pending", NoteFolderPass.adoption, adoption.pass)

        try! FileManager.default.createDirectory(
            at: adoptedFolder, withIntermediateDirectories: true)
        try! sharedFile.write(
            to: adoptedFolder.appendingPathComponent("Shared.md"), atomically: true,
            encoding: .utf8)
        let retriedPass = NoteFolderReconciler.plan(
            local: firstPass.snapshot, scan: try! await io.scan(folder: adoptedFolder),
            pass: adoption.pass, newID: nextID, now: { folderClock })
        try! await io.apply(retriedPass, in: adoptedFolder)
        adoption.finish()
        check(
            "a retried adoption does not fork the same text twice", 2,
            retriedPass.snapshot.notes.count)
        check(
            "both texts reach the folder", 2,
            try! FileManager.default.contentsOfDirectory(atPath: adoptedFolder.path)
                .filter { $0.hasSuffix(".md") }.count)
        check("a completed pass clears the flag", NoteFolderPass.steady, adoption.pass)
        check(
            "the cleared flag survives a relaunch too", NoteFolderPass.steady,
            NoteFolderAdoption(defaults: UserDefaults(suiteName: adoptionSuite)!).pass)

        // The whole folder disappearing is an error, never a set of deletions.
        try! FileManager.default.removeItem(at: folder)
        var scanFailed = false
        do { _ = try await io.scan(folder: folder) } catch { scanFailed = true }
        check("an unreachable folder fails loudly", true, scanFailed)
        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
