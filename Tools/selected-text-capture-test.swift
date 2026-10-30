import AppKit
import Carbon.HIToolbox

enum ClipboardManager {
    static let internalType = NSPasteboard.PasteboardType("spotter.selection-test.internal")
}
enum Permissions {
    static func ensureAccessibility() -> Bool { fatalError("Tests must never ask for Accessibility") }
}
enum HyperKeyTap {
    static let syntheticTag: Int64 = 0x5459_4354
}
enum Paster {
    static func copyString(_ text: String) { fatalError("Tests must not alter the system clipboard") }
    static func postCommandV(toPid: pid_t) { fatalError("Tests must not paste into another app") }
}

@MainActor
private final class UndoTextView: NSTextView {
    let testUndo = UndoManager()
    override var undoManager: UndoManager? { testUndo }
}

@main
@MainActor
struct SelectedTextCaptureTests {
    static func main() async {
        var failures = 0
        func check(_ name: String, _ passed: Bool) {
            print("\(passed ? "PASS" : "FAIL")  \(name)")
            if !passed { failures += 1 }
        }
        var markerRead = false
        let native = SelectedTextReader.resolveSelection(primary: { "  你好 🧭  " }, marker: {
            markerRead = true
            return "other"
        })
        check("native selection retains whitespace and bypasses markers", native == "  你好 🧭  " && !markerRead)
        check("empty AX text still tries the Chromium marker range", SelectedTextReader.resolveSelection(
            primary: { "" }, marker: { "selected words" }) == "selected words")
        check("empty Chromium marker cannot short-circuit copy fallback", SelectedTextReader.resolveSelection(
            primary: { nil }, marker: { "" }) == nil)
        check("whitespace-only selection cannot short-circuit copy fallback", SelectedTextReader.resolveSelection(
            primary: { " \n" }, marker: { "\t" }) == nil)

        let events = SelectionCopyCapture.commandCEvents()
        check("copy produces a down and up pair", events.map(\.type) == [.keyDown, .keyUp])
        check("copy does not inherit Hyper modifiers", events.count == 2 && events.allSatisfy { $0.flags == .maskCommand })
        check("copy targets C and bypasses Hyper rewriting", events.count == 2 && events.allSatisfy {
            $0.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_ANSI_C)
                && $0.getIntegerValueField(.eventSourceUserData) == HyperKeyTap.syntheticTag
        })

        let board = NSPasteboard(name: .init("spotter-selection-test-" + UUID().uuidString))
        defer { board.releaseGlobally() }
        func seed() {
            board.clearContents()
            board.setString("original", forType: .string)
            board.setData(Data([1, 2, 3]), forType: .rtf)
        }
        seed()
        let delayed = await SelectionCopyCapture.read(pasteboard: board) {
            board.clearContents()
            board.setString("", forType: .string)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(180))
                board.setString("选中的文字", forType: .string)
            }
        }
        check("copy waits through an early empty clipboard update", delayed == .copied("选中的文字"))
        check("original plain and rich clipboard content are restored", board.string(forType: .string) == "original"
            && board.data(forType: .rtf) == Data([1, 2, 3]))
        check("restoration is marked to skip clipboard history", board.types?.contains(ClipboardManager.internalType) == true)
        seed()
        let untouchedCount = board.changeCount
        let unchanged = await SelectionCopyCapture.read(pasteboard: board) {}
        check("no copy never translates stale clipboard text", unchanged == .nothingCopied)
        check("no copy leaves clipboard untouched", board.changeCount == untouchedCount)
        let nontext = await SelectionCopyCapture.read(pasteboard: board) {
            board.clearContents()
            board.setData(Data([4, 5]), forType: .png)
        }
        check("non-text copy is reported as unavailable", nontext == .noText)
        check("non-text copy restores original data", board.string(forType: .string) == "original")
        let cancelled = Task { @MainActor in
            await SelectionCopyCapture.read(pasteboard: board) { fatalError("Cancelled capture must not copy") }
        }
        cancelled.cancel()
        let cancelledResult = await cancelled.value
        check("cancelled capture never synthesizes a key", cancelledResult == .nothingCopied)
        let editor = UndoTextView()
        editor.string = "🧭 teh first, teh second"
        let originalRange = (editor.string as NSString).range(of: "teh")
        editor.setSelectedRange(originalRange)
        check("replacement matches the captured UTF-16 selection", AISelectionReplacement.localSelectionMatches(editor, range: originalRange, text: "teh"))
        editor.setSelectedRange((editor.string as NSString).range(of: "teh", options: .backwards))
        check("same word in a different position is not the captured selection", !AISelectionReplacement.localSelectionMatches(editor, range: originalRange, text: "teh"))
        editor.setSelectedRange(originalRange)
        editor.string = "🧭 new first, teh second"
        check("edited text cannot receive a stale spelling result", !AISelectionReplacement.localSelectionMatches(editor, range: originalRange, text: "teh"))
        editor.string = "🧭 teh first, teh second"
        editor.setSelectedRange(originalRange)
        editor.isEditable = false
        check("read-only selections cannot be replaced", !AISelectionReplacement.localSelectionMatches(editor, range: originalRange, text: "teh"))
        editor.isEditable = true
        check("stale out-of-bounds ranges cannot crash replacement", !AISelectionReplacement.localSelectionMatches(editor, range: NSRange(location: NSNotFound, length: 3), text: "teh"))
        var state = AISelectionReplacement.Snapshot(value: "🧭 teh word", selection: NSRange(location: 3, length: 3))
        var focused = true
        var acceptsWrites = true
        var writes = 0
        let original = state
        func transaction() -> AISelectionReplacement {
            AISelectionReplacement(original: state, text: NSAttributedString(string: "teh"), read: { state },
                write: { expected, range, text, selection, _ in
                    guard acceptsWrites, state == expected else { return false }
                    writes += 1
                    state = .init(value: (state.value as NSString).replacingCharacters(in: range, with: text.string), selection: selection)
                    return true
                }, isFocused: { focused })
        }
        let pending = transaction()
        try! pending.showProgress()
        check("progress immediately replaces only the captured UTF-16 range", state.value == "🧭 {Fixing} word")
        try! pending.replace(with: "the")
        check("completed text replaces the placeholder, not the old selection length", state.value == "🧭 the word" && state.selection == NSRange(location: 6, length: 0))
        let writesAfterSuccess = writes
        pending.restoreOriginal()
        check("completed work cannot be rolled back by late cleanup", writes == writesAfterSuccess)

        state = original
        let failed = transaction()
        try! failed.showProgress()
        check("failure or cancellation restores original selection", failed.restoreOriginal() && state == original)
        state = original
        let moved = transaction()
        try! moved.showProgress()
        focused = false
        do { try moved.replace(with: "the"); check("focus change rejects result", false) }
        catch { check("focus change rejects result", true) }
        state = .init(value: state.value, selection: NSRange(location: (state.value as NSString).length, length: 0))
        check("cleanup can restore the original control without activating it", moved.restoreOriginal() && state.value == original.value && state.selection.location == (original.value as NSString).length)

        focused = true
        state = original
        let edited = transaction()
        try! edited.showProgress()
        state = .init(value: "user's newer text", selection: NSRange(location: 17, length: 0))
        let userEdit = state
        do { try edited.replace(with: "the"); check("edited document rejects stale answer", false) }
        catch { check("edited document rejects stale answer", true) }
        check("cleanup never overwrites the user's newer text", !edited.restoreOriginal() && state == userEdit)
        state = original
        acceptsWrites = false
        do { try transaction().showProgress(); check("failed insertion is rejected", false) }
        catch { check("failed insertion leaves original intact", state == original) }

        editor.isRichText = true
        editor.string = "teh word"
        editor.setSelectedRange(NSRange(location: 0, length: 3))
        let font = NSFont.boldSystemFont(ofSize: 16)
        editor.textStorage?.addAttribute(.font, value: font, range: editor.selectedRange())
        let local = AISelectionReplacement.captureLocal(editor, isFocused: { true })
        try! local.showProgress()
        check("native editor displays progress", editor.string == "{Fixing} word")
        local.restoreOriginal()
        check("native failure restoration preserves rich text", editor.string == "teh word" && editor.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont == font)
        editor.allowsUndo = true
        editor.testUndo.removeAllActions()
        editor.testUndo.groupsByEvent = false
        editor.testUndo.beginUndoGrouping()
        let localSuccess = AISelectionReplacement.captureLocal(editor, isFocused: { true })
        try! localSuccess.showProgress()
        try! localSuccess.replace(with: "the")
        check("native editor receives corrected text with its formatting", editor.string == "the word" && editor.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont == font)
        editor.testUndo.endUndoGrouping()
        editor.testUndo.undo()
        check("native Undo skips progress and restores the original selection text", editor.string == "teh word")
        var pasted: [String] = []
        var currentTarget = true
        var cleanupCount = 0
        func fallback() -> AISelectionPasteFallback {
            AISelectionPasteFallback(original: "teh", isCurrent: { currentTarget },
                paste: { pasted.append($0) }, cleanup: { cleanupCount += 1 })
        }
        let pasteOnly = fallback()
        do { try await pasteOnly.replace(with: "the", readSelection: { "teh" }) }
        catch { check("copy-only selection can be replaced", false) }
        check("copy-only editors paste the result without AX setters or a full document", pasted == ["the"] && cleanupCount == 1)
        pasteOnly.cancel()
        check("fallback cleanup is exactly once", cleanupCount == 1)
        let stalePaste = fallback()
        do { try await stalePaste.replace(with: "the", readSelection: { "new selection" }); check("changed clipboard selection is rejected", false) }
        catch { check("changed clipboard selection is rejected", pasted.count == 1) }
        let movedPaste = fallback()
        do {
            try await movedPaste.replace(with: "the", readSelection: { currentTarget = false; return "teh" })
            check("focus changes during copy are rejected", false)
        } catch { check("focus changes during copy are rejected", pasted.count == 1) }
        currentTarget = true
        let stoppedPaste = fallback()
        stoppedPaste.cancel()
        do { try await stoppedPaste.replace(with: "the", readSelection: { fatalError("Cancelled work must not copy") }); check("cancelled fallback is rejected", false) }
        catch { check("cancelled fallback is rejected", pasted.count == 1) }
        let cancelledPaste = fallback()
        let cancelledWrite = Task { @MainActor in
            try await cancelledPaste.replace(with: "the", readSelection: { "teh" })
        }
        cancelledWrite.cancel()
        do { try await cancelledWrite.value; check("superseded completion task cannot paste", false) }
        catch { check("superseded completion task cannot paste", pasted.count == 1) }
        let unchangedPaste = fallback()
        do { try await unchangedPaste.replace(with: "teh", readSelection: { "teh" }) }
        catch { check("unchanged result is accepted", false) }
        check("unchanged result leaves both document and clipboard untouched", pasted.count == 1)
        state = original
        var nativeRetryCount = 0
        var nativeRetryResult = ""
        func ignoredSetterTarget(mutates: Bool) -> AISelectionReplacement {
            AISelectionReplacement(original: original, text: NSAttributedString(string: "teh"), read: { state },
                write: { _, _, _, _, _ in
                    if mutates { state = .init(value: "unexpected editor change", selection: .init(location: 0, length: 0)) }
                    return false
                }, isFocused: { true }, makePasteFallback: {
                    nativeRetryCount += 1
                    return AISelectionPasteFallback(original: "teh", isCurrent: { true }, paste: { nativeRetryResult = $0 })
                })
        }
        let ignoredSetter = ignoredSetterTarget(mutates: false)
        do {
            try ignoredSetter.showProgress()
            check("ignored AX writes use native paste only with the original selection intact", !ignoredSetter.usesInlineProgress && state == original)
            try await ignoredSetter.complete(with: "the", readSelection: { "teh" })
        } catch { check("ignored setter can fall back to native replacement", false) }
        check("ignored setter completes through guarded native paste", nativeRetryCount == 1 && nativeRetryResult == "the")
        state = original
        let changedSetter = ignoredSetterTarget(mutates: true)
        do { try changedSetter.showProgress(); check("partially applied writes cannot retry as paste", false) }
        catch { check("partially applied writes cannot retry as paste", nativeRetryCount == 1 && changedSetter.usesInlineProgress) }
        print("Selected text capture: \(failures) failure(s)")
        exit(failures == 0 ? 0 : 1)
    }
}
