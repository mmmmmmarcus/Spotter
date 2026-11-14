import SwiftUI
import UIKit

/// The Markdown editor: one `UITextView` holding the raw source, styled in place. Input rules come from `NoteInputRules`, styling from `NoteEditorStyler`; this type only connects them to UIKit.
struct NoteTextEditor: UIViewRepresentable {
    @Binding var text: String
    let noteID: UUID
    let tint: NoteTint?
    var focusRequest = 0
    var onNavigate: (NoteNavigationDirection) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> NoteTextView {
        let textView = NoteTextView()
        textView.text = text
        context.coordinator.attach(textView)
        return textView
    }

    func updateUIView(_ textView: NoteTextView, context: Context) {
        context.coordinator.update(from: self)
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        private var parent: NoteTextEditor
        private weak var textView: NoteTextView?
        private let styler = NoteEditorStyler()
        private var isApplyingEdit = false
        private var isAdjustingSelection = false

        private static let titlePrefixLength = (NoteEngine.requiredTitlePrefix as NSString).length

        init(parent: NoteTextEditor) {
            self.parent = parent
        }

        func attach(_ textView: NoteTextView) {
            self.textView = textView
            textView.delegate = self
            textView.commandHandler = { [weak self] in self?.apply($0) ?? false }
            textView.restyleHandler = { [weak self] in self?.restyle() }
            textView.navigationHandler = { [weak self] in self?.parent.onNavigate($0) }
            textView.inputAccessoryView = NoteAccessoryBar(
                handler: { [weak self] in _ = self?.apply($0) },
                dismiss: { [weak textView] in textView?.resignFirstResponder() })
            let tap = UITapGestureRecognizer(target: self, action: #selector(toggleCheckbox(_:)))
            tap.delegate = self
            textView.addGestureRecognizer(tap)
            applyTint()
            restyle()
            placeCaretInDraft()
        }

        func update(from incoming: NoteTextEditor) {
            let focusRequested = parent.focusRequest != incoming.focusRequest
            let noteChanged = parent.noteID != incoming.noteID
            let tintChanged = parent.tint != incoming.tint
            parent = incoming
            guard let textView else { return }
            if tintChanged { applyTint() }
            // A composition's marked text is not in the binding yet; only a switch of Note may discard it.
            if noteChanged || (textView.markedTextRange == nil && textView.text != incoming.text) {
                let caret = textView.selectedRange.location
                if textView.markedTextRange != nil {
                    // Committing the abandoned composition must not publish the old document into the Note that replaces it.
                    isApplyingEdit = true
                    textView.unmarkText()
                    isApplyingEdit = false
                }
                textView.text = incoming.text
                if noteChanged {
                    textView.undoManager?.removeAllActions()
                    textView.selectedRange = NSRange(location: Self.titlePrefixLength, length: 0)
                    textView.setContentOffset(
                        CGPoint(x: 0, y: -textView.adjustedContentInset.top), animated: false)
                } else {
                    textView.selectedRange = NSRange(
                        location: min(caret, (incoming.text as NSString).length), length: 0)
                }
                restyle()
                if noteChanged { placeCaretInDraft() }
            }
            if focusRequested { textView.becomeFirstResponder() }
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingEdit else { return }
            contentChanged()
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isApplyingEdit, !isAdjustingSelection, textView.markedTextRange == nil else { return }
            let selection = textView.selectedRange
            // The hidden `# ` has no width, so a tap at the title's start can land inside it; typing there must begin after it.
            if selection.length == 0, selection.location < Self.titlePrefixLength,
                textView.text.hasPrefix(NoteEngine.requiredTitlePrefix)
            {
                isAdjustingSelection = true
                textView.selectedRange = NSRange(location: Self.titlePrefixLength, length: 0)
                isAdjustingSelection = false
            }
            textView.typingAttributes = styler.typingAttributes(for: textView.selectedRange)
        }

        func textView(
            _ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String
        ) -> Bool {
            guard !isApplyingEdit else { return true }
            // An input method writes its uncommitted composition through this callback; a rule firing there would rewrite text the user has not chosen yet.
            guard textView.markedTextRange == nil else {
                return range.location >= Self.titlePrefixLength
                    || text.hasPrefix(NoteEngine.requiredTitlePrefix)
            }
            let decision = NoteInputRules.decision(
                replacing: range, with: text, in: textView.text, selection: textView.selectedRange,
                concealedSuffixes: styler.concealedSuffixes, evaluate: Self.evaluate)
            switch decision {
            case .allow:
                // Typing must never inherit the hidden syntax beside the caret.
                textView.typingAttributes = styler.typingAttributes(
                    for: NSRange(location: range.location, length: 0))
                return true
            case .reject:
                return false
            case .replace(let replaced, let replacement):
                replace(replaced, with: replacement)
                return false
            }
        }

        func textView(
            _ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            guard range.length > 0 else { return UIMenu(children: suggestedActions) }
            let format = NoteAccessoryBar.menu(title: "Format", items: NoteAccessoryBar.inlineItems) {
                [weak self] in _ = self?.apply($0)
            }
            return UIMenu(children: suggestedActions + [format])
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch
        ) -> Bool {
            guard let textView else { return false }
            return checkbox(at: touch.location(in: textView)) != nil
        }

        /// A tap on a todo box toggles it and nothing else: the text view's own taps wait for this one, so the caret does not jump and the keyboard does not rise.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        /// Returns whether the command changed the Note, so a hardware Tab can fall through to a plain tab.
        @discardableResult
        func apply(_ command: NoteTouchCommand) -> Bool {
            // A command reshapes text under the caret; mid-composition that would strand the input method's marked range.
            guard let textView, textView.markedTextRange == nil,
                let result = NoteInputRules.applying(
                    command, to: textView.text, selection: textView.selectedRange)
            else { return false }
            let change = NoteInputRules.difference(from: textView.text, to: result.text)
            replace(change.range, with: change.replacement, selecting: result.selection)
            return true
        }

        @objc private func toggleCheckbox(_ recognizer: UITapGestureRecognizer) {
            guard let textView, textView.markedTextRange == nil,
                let checkbox = checkbox(at: recognizer.location(in: textView))
            else { return }
            // The range is the last pass's, so it must still be a state character before anything is written over it.
            let source = textView.text as NSString
            guard NSMaxRange(checkbox.range) <= source.length,
                [" ", "x", "X"].contains(source.substring(with: checkbox.range))
            else { return }
            replace(
                checkbox.range, with: checkbox.isDone ? " " : "x", selecting: textView.selectedRange)
        }

        private func checkbox(at point: CGPoint) -> NoteLayoutManager.Checkbox? {
            guard let textView, let layout = textView.layoutManager as? NoteLayoutManager else {
                return nil
            }
            return layout.checkbox(
                at: CGPoint(
                    x: point.x - textView.textContainerInset.left,
                    y: point.y - textView.textContainerInset.top),
                slop: NotesTheme.Size.checkboxTapSlop)
        }

        private func replace(_ range: NSRange, with string: String, selecting selection: NSRange? = nil) {
            perform(range, string, selecting: selection)
            contentChanged()
        }

        /// Goes through the text view's own editing path, so the change is undoable like typing.
        private func perform(_ range: NSRange, _ string: String, selecting selection: NSRange?) {
            guard let textView,
                let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
                let end = textView.position(from: start, offset: range.length),
                let textRange = textView.textRange(from: start, to: end)
            else { return }
            isApplyingEdit = true
            textView.replace(textRange, withText: string)
            textView.selectedRange =
                selection
                ?? NSRange(location: range.location + (string as NSString).length, length: 0)
            isApplyingEdit = false
        }

        private func contentChanged() {
            guard let textView else { return }
            // A composition is not text yet: it is neither published nor restyled until it commits.
            guard textView.markedTextRange == nil else { return }
            if let refresh = NoteInputRules.arithmeticRefresh(
                in: textView.text, caret: textView.selectedRange, evaluate: Self.evaluate)
            {
                perform(refresh.range, refresh.answer, selecting: textView.selectedRange)
            }
            if parent.text != textView.text { parent.text = textView.text }
            restyle()
        }

        private func restyle() {
            guard let textView, textView.markedTextRange == nil,
                let layout = textView.layoutManager as? NoteLayoutManager
            else { return }
            isApplyingEdit = true
            styler.style(textView.textStorage, layout: layout)
            isApplyingEdit = false
            textView.typingAttributes = styler.typingAttributes(for: textView.selectedRange)
            textView.showsTitlePlaceholder = NoteEngine.isEmptyDraft(textView.text)
        }

        /// The caret and selection wear the Note's own colour, as its completed todos do.
        private func applyTint() {
            textView?.tintColor = parent.tint.map(NotesTheme.Colors.tintAccent)
        }

        /// A fresh draft is for typing its title: the caret goes after the marker and the keyboard comes up.
        private func placeCaretInDraft() {
            guard let textView, NoteEngine.isEmptyDraft(textView.text) else { return }
            textView.selectedRange = NSRange(location: Self.titlePrefixLength, length: 0)
            textView.focusWhenShown()
        }

        private static func evaluate(_ expression: String) -> String? {
            guard let result = CalcEngine.evaluate(expression),
                case .value(let display, _) = result.payload
            else { return nil }
            return display
        }
    }
}

final class NoteTextView: UITextView {
    /// Returns whether the command changed the Note.
    var commandHandler: ((NoteTouchCommand) -> Bool)?
    var restyleHandler: (() -> Void)?
    var navigationHandler: ((NoteNavigationDirection) -> Void)?
    var showsTitlePlaceholder = false {
        didSet { placeholder.isHidden = !showsTitlePlaceholder }
    }

    private let placeholder = UILabel()
    private var wantsFocus = false

    init() {
        // TextKit 1, built by hand so the layout manager is ours: decorations are drawn behind the text, never inserted into it.
        let storage = NSTextStorage()
        let layout = NoteLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)
        backgroundColor = .clear
        alwaysBounceVertical = true
        keyboardDismissMode = .interactive
        textContainerInset = UIEdgeInsets(
            top: NotesTheme.Spacing.xl, left: NotesTheme.Spacing.xxl, bottom: NotesTheme.Spacing.xxl,
            right: NotesTheme.Spacing.xxl)
        // The source is Markdown, so nothing may rewrite its punctuation or spacing.
        smartDashesType = .no
        smartQuotesType = .no
        smartInsertDeleteType = .no

        placeholder.text = "Title"
        placeholder.textColor = .placeholderText
        placeholder.isHidden = true
        addSubview(placeholder)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: NoteTextView, _) in
            view.restyleHandler?()
            view.setNeedsLayout()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("NoteTextView is built in code")
    }

    override var keyCommands: [UIKeyCommand]? {
        let commands = [
            UIKeyCommand(title: "Bold", action: #selector(formatBold), input: "b", modifierFlags: .command),
            UIKeyCommand(
                title: "Italic", action: #selector(formatItalic), input: "i", modifierFlags: .command),
            UIKeyCommand(title: "Link", action: #selector(formatLink), input: "k", modifierFlags: .command),
            UIKeyCommand(
                title: "Previous Note", action: #selector(previousNote), input: "[", modifierFlags: .command),
            UIKeyCommand(title: "Next Note", action: #selector(nextNote), input: "]", modifierFlags: .command),
            UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(indent)),
            UIKeyCommand(input: "\t", modifierFlags: .shift, action: #selector(outdent)),
        ]
        for command in commands { command.wantsPriorityOverSystemBehavior = true }
        return commands
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        placeholder.font = NotesTheme.Fonts.heading(level: 1)
        placeholder.sizeToFit()
        placeholder.frame.origin = CGPoint(x: textContainerInset.left, y: textContainerInset.top)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        focusIfWanted()
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        guard let layout = layoutManager as? NoteLayoutManager else { return }
        layout.accent = tintColor
        layout.invalidateDisplay(forCharacterRange: NSRange(location: 0, length: textStorage.length))
    }

    func focusWhenShown() {
        wantsFocus = true
        focusIfWanted()
    }

    /// Deferred a turn: becoming first responder in the middle of a navigation push is dropped.
    private func focusIfWanted() {
        guard wantsFocus, window != nil else { return }
        wantsFocus = false
        DispatchQueue.main.async { [weak self] in self?.becomeFirstResponder() }
    }

    @objc private func formatBold() {
        _ = commandHandler?(.inline(.bold))
    }

    @objc private func formatItalic() {
        _ = commandHandler?(.inline(.italic))
    }

    @objc private func formatLink() {
        _ = commandHandler?(.inline(.link))
    }

    @objc private func previousNote() {
        navigationHandler?(.previous)
    }

    @objc private func nextNote() {
        navigationHandler?(.next)
    }

    @objc private func indent() {
        if commandHandler?(.indent(.indent)) != true { insertText("\t") }
    }

    @objc private func outdent() {
        _ = commandHandler?(.indent(.outdent))
    }
}
