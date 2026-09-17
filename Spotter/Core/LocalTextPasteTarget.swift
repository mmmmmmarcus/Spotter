import AppKit

@MainActor
protocol LocalPasteEditor: AnyObject {
    var pasteDocumentID: UUID { get }
}

@MainActor
final class LocalTextPasteTarget {
    private weak var editor: NSTextView?
    private let documentID: UUID
    private var source: String
    private var selection: NSRange

    init?(editor: NSTextView) {
        guard let local = editor as? any LocalPasteEditor, editor.isEditable else { return nil }
        self.editor = editor
        documentID = local.pasteDocumentID
        source = editor.string
        selection = editor.selectedRange()
    }

    @discardableResult
    func insert(_ text: String, restoringFocus: Bool) -> Bool {
        guard let editor, let local = editor as? any LocalPasteEditor,
            local.pasteDocumentID == documentID, editor.string == source,
            !editor.hasMarkedText(), editor.isEditable,
            NSMaxRange(selection) <= editor.string.utf16.count
        else { return false }
        editor.insertText(text, replacementRange: selection)
        source = editor.string
        selection = editor.selectedRange()
        if restoringFocus { restoreFocus() }
        return true
    }

    func restoreFocus() {
        guard let editor, editor.window?.isVisible == true else { return }
        editor.window?.makeKeyAndOrderFront(nil)
        editor.window?.makeFirstResponder(editor)
    }
}
