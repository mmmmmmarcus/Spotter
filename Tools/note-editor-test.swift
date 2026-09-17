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
                tint: nil, onNavigate: { _ in })
        }
    }

    static func expect(_ condition: Bool, _ message: String) {
        checks += 1
        if !condition { failures += 1; print("FAIL: \(message)") }
    }

    static func main() {
        _ = NSApplication.shared
        for (source, caret) in [("# 中文正文", 6), ("# 清单\n- 第一项\n- 第二项", 10), ("# **粗体**", 6)] {
            compositionSurvivesRefresh(source, caret: caret)
        }
        titlePrefixIsProtected()
        chineseTitleComposition()
        documentSwitch()
        externalUpdate()
        emptyTitleCaret()
        listSplitting()
        listGeometry()
        localEmojiPaste()
        print("\(checks - failures)/\(checks) passed")
        if failures > 0 { exit(1) }
    }

    static func emptyTitleCaret() {
        let document = Document("# ")
        let editor = document.editor
        let coordinator = editor.makeCoordinator()
        let scroll = editor.makeScrollView(coordinator: coordinator)
        let view = scroll.documentView as! NSTextView
        expect(view.selectedRange() == NSRange(location: 2, length: 0), "new title starts after H1 syntax")
        let font = view.textStorage?.attribute(.font, at: 1, effectiveRange: nil) as? NSFont
        expect(font?.pointSize == NSFont.preferredFont(forTextStyle: .largeTitle).pointSize,
               "empty title keeps a full height line and caret")
        expect((view.typingAttributes[.foregroundColor] as? NSColor) == .labelColor,
               "typing into empty title has visible ink")
    }

    static func listSplitting() {
        for (marker, next) in [("- ", "- "), ("12. ", "13. "), ("- [x] ", "- [ ] "),
                               ("  * [X] ", "  * [ ] "), ("  + ", "  + ")] {
            let document = Document("# 标题\n" + marker + "前半后半")
            let editor = document.editor
            let coordinator = editor.makeCoordinator()
            let scroll = editor.makeScrollView(coordinator: coordinator)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 360),
                                  styleMask: [.titled], backing: .buffered, defer: true)
            window.contentView = scroll
            defer { withExtendedLifetime(window) {} }
            let view = scroll.documentView as! NSTextView
            let caret = ("# 标题\n" + marker + "前半").utf16.count
            view.setSelectedRange(NSRange(location: caret, length: 0))
            view.insertNewline(nil)
            expect(view.string == "# 标题\n" + marker + "前半\n" + next + "后半",
                   "Return splits the middle of \(marker) into another list item")
            expect(document.text == view.string, "split reaches the document binding")
            view.undoManager?.undo()
            expect(view.string == "# 标题\n" + marker + "前半后半", "list split undoes in one step")
        }
    }

    static func listGeometry() {
        let document = Document("# Lists\n- bullet\n1. number\n- [ ] todo\n  - nested\n  2. nested\n  - [x] done")
        let editor = document.editor
        let coordinator = editor.makeCoordinator()
        let scroll = editor.makeScrollView(coordinator: coordinator)
        let view = scroll.documentView as! NSTextView
        scroll.frame = NSRect(x: 0, y: 0, width: 440, height: 360)
        view.frame.size.width = 440
        view.textContainer?.containerSize.width = 400
        view.layoutManager?.ensureLayout(for: view.textContainer!)
        let source = view.string as NSString
        func indent(_ text: String) -> CGFloat {
            let style = view.textStorage?.attribute(.paragraphStyle, at: source.range(of: text).location,
                                                    effectiveRange: nil) as? NSParagraphStyle
            return style?.headIndent ?? -1
        }
        func textX(_ text: String) -> CGFloat {
            let layout = view.layoutManager!
            let glyph = layout.glyphIndexForCharacter(at: source.range(of: text).location)
            return layout.location(forGlyphAt: glyph).x
                + layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minX
        }
        expect(abs(textX("bullet") - textX("number")) < 1,
               "rendered bullet and number text align")
        expect(abs(textX("bullet") - textX("todo")) < 1,
               "rendered bullet and todo text align")
        expect(abs(textX("nested") - textX("bullet") - 20) < 1,
               "rendered nested text moves twenty points")
        expect(abs(textX("Lists")) < 1, "heading syntax occupies no visible horizontal space: \(textX("Lists"))")
        let slot = indent("bullet")
        expect(slot == indent("number") && slot == indent("todo"), "all list markers share one content edge")
        expect(slot < 24, "one digit markers occupy a compact slot")
        expect(indent("nested") - slot == 20, "one nesting level advances twenty points")
        let color = view.textStorage?.attribute(.foregroundColor, at: source.range(of: "done").location,
                                                effectiveRange: nil) as? NSColor
        expect(color == .tertiaryLabelColor, "completed task text is subdued")
    }

    static func localEmojiPaste() {
        let document = Document("# Hello\nworld")
        let editor = document.editor
        let coordinator = editor.makeCoordinator()
        let scroll = editor.makeScrollView(coordinator: coordinator)
        let view = scroll.documentView as! NSTextView
        view.setSelectedRange(NSRange(location: 2, length: 5))
        let target = LocalTextPasteTarget(editor: view)!
        expect(target.insert("🧑🏽‍💻", restoringFocus: false), "emoji inserts in the captured Note editor")
        expect(document.text == "# 🧑🏽‍💻\nworld", "emoji replaces the captured UTF16 selection")
        expect(target.insert("🎉", restoringFocus: false), "picker can paste again while staying open")
        expect(document.text == "# 🧑🏽‍💻🎉\nworld", "repeated emoji paste advances the caret")
        let next = Document(document.text)
        coordinator.update(from: next.editor)
        expect(!target.insert("❌", restoringFocus: false), "a stale target cannot paste into a different Note")
        let target2 = LocalTextPasteTarget(editor: view)!
        view.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0),
                           replacementRange: NSRange(location: NSNotFound, length: 0))
        expect(!target2.insert("❌", restoringFocus: false), "paste does not overwrite an IME composition")
    }

    static func titlePrefixIsProtected() {
        let document = Document("# 标题\n正文")
        let editor = document.editor
        let coordinator = editor.makeCoordinator()
        let scroll = editor.makeScrollView(coordinator: coordinator)
        let view = scroll.documentView as! NSTextView
        view.setSelectedRange(NSRange(location: 0, length: (view.string as NSString).length))
        view.insertText("新标题", replacementRange: view.selectedRange())
        expect(view.string == "# 新标题", "replacing the document preserves the required H1 marker")
        expect(document.text == "# 新标题", "protected replacement reaches the binding")
    }

    static func chineseTitleComposition() {
        let document = Document(NoteEngine.requiredTitlePrefix)
        let editor = document.editor
        let coordinator = editor.makeCoordinator()
        let scroll = editor.makeScrollView(coordinator: coordinator)
        let view = scroll.documentView as! NSTextView
        view.setSelectedRange(NSRange(location: 2, length: 0))
        let unspecified = NSRange(location: NSNotFound, length: 0)
        view.setMarkedText(
            "biaoti", selectedRange: NSRange(location: 6, length: 0),
            replacementRange: unspecified)
        coordinator.update(from: document.editor)
        expect(view.hasMarkedText(), "title refresh preserves the Chinese input composition")
        view.insertText("标题", replacementRange: unspecified)
        expect(view.string == "# 标题", "Chinese title commit keeps the H1 marker")
        expect(document.text == "# 标题", "Chinese title commit reaches the binding")
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
