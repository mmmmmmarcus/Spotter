import AppKit
import SwiftUI

// Only the app-wide selection-capture identifier is stubbed; the editor and its TextKit stack are real.
enum SelectedTextCapture {
    static let localSourceIdentifier = NSUserInterfaceItemIdentifier("note-editor-test")
}

@main
@MainActor
struct NoteEditorTests {
    static var failures = 0
    static var checks = 0

    @MainActor final class Document {
        let id = UUID()
        var text: String
        init(_ text: String) { self.text = text }
        var editor: NoteMarkdownEditor {
            NoteMarkdownEditor(
                text: Binding(get: { self.text }, set: { self.text = $0 }), noteID: id,
                tint: nil, autoSizes: true, onContentHeightChange: { _ in }, onNavigate: { _ in })
        }
    }

    static func expect(_ condition: Bool, _ message: String) {
        checks += 1
        if !condition { failures += 1; print("FAIL: \(message)") }
    }

    static func main() {
        _ = NSApplication.shared
        for (source, caret) in [("中文正文", 4), ("- 第一项\n- 第二项", 5), ("**粗体**", 4)] {
            compositionSurvivesRefresh(source, caret: caret)
        }
        documentSwitch()
        externalUpdate()
        print("\(checks - failures)/\(checks) passed")
        if failures > 0 { exit(1) }
    }

    static func compositionSurvivesRefresh(_ source: String, caret: Int) {
        let document = Document(source)
        let editor = document.editor
        let coordinator = editor.makeCoordinator()
        let scroll = editor.makeScrollView(coordinator: coordinator)
        let view = scroll.documentView as! NSTextView
        view.setSelectedRange(NSRange(location: caret, length: 0))
        let unspecified = NSRange(location: NSNotFound, length: 0)
        for candidate in ["n", "ni", "nihao"] {
            view.setMarkedText(
                candidate, selectedRange: NSRange(location: candidate.utf16.count, length: 0),
                replacementRange: unspecified)
            let draft = view.string
            let marked = view.markedRange()
            let selection = view.selectedRange()
            coordinator.update(from: document.editor)
            expect(view.string == draft, "refresh preserves \(candidate) in \(source)")
            expect(view.hasMarkedText() && view.markedRange() == marked, "refresh preserves marked range")
            expect(view.selectedRange() == selection, "refresh preserves candidate selection")
            guard view.string == draft, view.hasMarkedText() else { return }
        }
        view.insertText("你好", replacementRange: unspecified)
        let expected = (source as NSString).replacingCharacters(
            in: NSRange(location: caret, length: 0), with: "你好")
        expect(view.string == expected, "commit preserves surrounding text and line breaks")
        expect(document.text == expected, "commit reaches the document binding")
        coordinator.update(from: document.editor)
        expect(view.string == expected && !view.hasMarkedText(), "refresh after commit is stable")
    }

    static func documentSwitch() {
        let first = Document("第一篇")
        let next = Document("第二篇")
        let editor = first.editor
        let coordinator = editor.makeCoordinator()
        let scroll = editor.makeScrollView(coordinator: coordinator)
        let view = scroll.documentView as! NSTextView
        view.setSelectedRange(NSRange(location: 3, length: 0))
        view.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0),
                           replacementRange: NSRange(location: NSNotFound, length: 0))
        coordinator.update(from: next.editor)
        expect(view.string == next.text, "switching notes loads the requested document")
        expect(!view.hasMarkedText(), "switching notes clears the old marked range")
        expect(first.text == "第一篇", "switch does not persist unfinished pinyin")
    }

    static func externalUpdate() {
        let document = Document("原文")
        let editor = document.editor
        let coordinator = editor.makeCoordinator()
        let scroll = editor.makeScrollView(coordinator: coordinator)
        let view = scroll.documentView as! NSTextView
        document.text = "同步后的正文"
        coordinator.update(from: document.editor)
        expect(view.string == document.text, "external edits apply outside composition")
    }
}
