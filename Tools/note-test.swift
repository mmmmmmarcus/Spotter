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
            "link", "Read [Spotter](https://)",
            NoteEngine.applying(
                .link, to: "Read Spotter", selection: NSRange(location: 5, length: 7)
            ).text)

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
        store.updateSelectedContent("# Persisted\nBody")
        await store.flush()
        let reopened = NoteStore(fileURL: fileURL, defaults: defaults, now: { fixedDate })
        check("persist count", 1, reopened.notes.count)
        check("persist content", "# Persisted\nBody", reopened.selectedNote?.content)

        let secondID = reopened.createNote(content: "Second")
        await reopened.flush()
        check("create selects", secondID, reopened.selectedID)
        if let selected = reopened.selectedNote { reopened.delete(selected) }
        await reopened.flush()
        check("delete note", 1, reopened.notes.count)

        let synced = SpotterNote(content: "# Synced", createdAt: fixedDate)
        reopened.replace(notes: [synced], selectedID: synced.id)
        await reopened.flush()
        check("sync replaces notes", [synced], reopened.notes)
        check("sync restores selected note", synced.id, reopened.selectedID)

        let document = NoteSyncDocument(notes: reopened.notes, selectedID: reopened.selectedID)
        let encodedDocument = try! document.encoded()
        let decodedDocument = try! NoteSyncDocument(json: encodedDocument)
        check("standalone sync document round-trips", document, decodedDocument)
        check("sync document keeps selected note", synced.id, decodedDocument.selectedID)
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

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
