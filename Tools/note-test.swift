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
        reopened.applyCloudSnapshot(NoteSyncSnapshot(notes: [remoteEdit], tombstones: []))
        check("newer remote edit wins", "# Remote", reopened.selectedNote?.content)
        let tiedDeletion = NoteTombstone(id: synced.id, deletedAt: newerDate)
        reopened.applyCloudSnapshot(NoteSyncSnapshot(notes: [], tombstones: [tiedDeletion]))
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

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
