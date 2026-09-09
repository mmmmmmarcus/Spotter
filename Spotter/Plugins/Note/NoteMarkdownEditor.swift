import AppKit
import SwiftUI

@MainActor
enum NoteEditorMetrics {
    static let minimumLines = 3
    static let maximumLines = 20
    /// Room below the last line, on top of the text inset. The inset is symmetric while the window
    /// is not — the toolbar sits above the text and nothing sits below it — so an auto-sized note
    /// ends a hair under its final descender without this.
    static let trailingRoom: CGFloat = Theme.Spacing.xl

    private static var bodyLineHeight: CGFloat {
        let font = NSFont.preferredFont(forTextStyle: .body)
        return ceil(font.ascender - font.descender + font.leading)
    }

    static var minimumTextHeight: CGFloat { bodyLineHeight * CGFloat(minimumLines) }

    static func editorHeight(forTextHeight textHeight: CGFloat) -> CGFloat {
        textHeight + Theme.Spacing.xxl * 2 + trailingRoom
    }

    static var minimumEditorHeight: CGFloat {
        editorHeight(forTextHeight: minimumTextHeight)
    }

    static var maximumEditorHeight: CGFloat {
        editorHeight(forTextHeight: bodyLineHeight * CGFloat(maximumLines))
    }

    static func estimatedEditorHeight(for markdown: String) -> CGFloat {
        let lines = NoteEngine.editorLineCount(
            in: markdown, minimum: minimumLines, maximum: maximumLines)
        return editorHeight(forTextHeight: bodyLineHeight * CGFloat(lines))
    }

    static func windowHeight(forEditorHeight editorHeight: CGFloat) -> CGFloat {
        Theme.Size.noteToolbarHeight + editorHeight
    }
}

/// The one fixed cell every list marker occupies. A todo, a bullet and an ordered number have three
/// different natural widths, so a note mixing them starts its text at three different x positions;
/// kerning each marker out to this cell gives the note one content edge. All of it is presentation:
/// kerning and paragraph style are attributes, so the source stays exactly the Markdown typed.
@MainActor
private enum NoteListMarker {
    /// Breathing room between the widest decoration and the text after it.
    private static let minimumGap: CGFloat = 4

    static var bodyFont: NSFont { .preferredFont(forTextStyle: .body) }

    static var monospacedFont: NSFont {
        .monospacedSystemFont(ofSize: bodyFont.pointSize, weight: .regular)
    }

    /// The square the todo box and the bullet disc are both laid out in — one metric, so neither
    /// decoration can drift in size or position away from the other.
    static var decorationSide: CGFloat { (bodyFont.ascender - bodyFont.descender).rounded() }

    /// Wide enough for a one-digit ordered marker in the monospaced font it keeps, and never
    /// narrower than a decoration and its gap. A wider marker anywhere in the note raises it for
    /// every list line, so item ten does not cost the note its content edge.
    static var baseSlot: CGFloat {
        max(decorationSide + minimumGap, width(of: "1. ", in: monospacedFont))
    }

    static var indentUnit: CGFloat { width(of: NoteEngine.listIndentUnit, in: bodyFont) }

    /// A nesting level is the same step whether it was written as spaces or as a legacy tab.
    static func indentationWidth(_ indentation: String) -> CGFloat {
        let spaces = indentation.filter { $0 == " " }.count
        let tabs = indentation.count - spaces
        return CGFloat(spaces) * width(of: " ", in: bodyFont) + CGFloat(tabs) * indentUnit
    }

    static func width(of text: String, in font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }
}

struct NoteMarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    let noteID: UUID
    let tint: NoteTint?
    /// Whether the window grows with the text; when it does not, the editor scrolls inside it.
    let autoSizes: Bool
    let onContentHeightChange: (CGFloat) -> Void
    let onNavigate: (NoteNavigationDirection) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        makeScrollView(coordinator: context.coordinator)
    }

    func makeScrollView(coordinator: Coordinator) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        // The TextKit 1 stack is built by hand so the layout manager can be ours: block decorations
        // are drawn behind the text rather than inserted into it, which keeps the source Markdown.
        let storage = NSTextStorage()
        let layout = NoteLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(
            size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        // Zero, so `textContainerInset` is the only horizontal inset. AppKit's default 5 stacks on
        // top of it, which pushes the text off every other measure taken from the same token —
        // including the empty-note placeholder drawn over this view.
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)

        let textView = NoteTextView(frame: .zero, textContainer: container)
        textView.identifier = SelectedTextCapture.localSourceIdentifier
        textView.markdownCommandHandler = { [weak coordinator] command in
            coordinator?.apply(command)
        }
        textView.blockFormatHandler = { [weak coordinator] format in
            coordinator?.apply(format)
        }
        textView.checkboxClickHandler = { [weak coordinator] index in
            coordinator?.toggleCheckbox(atCharacterIndex: index) ?? false
        }
        textView.indentHandler = { [weak coordinator] direction in
            coordinator?.applyIndent(direction) ?? false
        }
        textView.deleteHandler = { [weak coordinator] in
            coordinator?.deleteListMarker() ?? false
        }
        textView.navigationHandler = { [weak coordinator] direction in
            coordinator?.navigate(direction)
        }
        textView.delegate = coordinator
        textView.string = text
        textView.drawsBackground = false
        textView.textColor = .labelColor
        textView.font = .preferredFont(forTextStyle: .body)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        // The note's source is Markdown, so pasted text lands verbatim: smart insert would add or
        // eat a space around it, which is both wrong for syntax and wrong for scripts without spaces.
        textView.smartInsertDeleteEnabled = false
        textView.textContainerInset = NSSize(width: Theme.Spacing.xxl, height: Theme.Spacing.xxl)
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        scrollView.documentView = textView
        coordinator.textView = textView
        coordinator.applyTint()
        coordinator.highlight()

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
            coordinator.reportContentHeight()
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(from: self)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteMarkdownEditor
        weak var textView: NSTextView?
        private var highlightWork: DispatchWorkItem?
        private var isApplyingInputRule = false
        private var isRewritingAnswer = false
        /// Closing markers the last pass collapsed, so the caret can be stepped out of one.
        private var concealedSuffixes: [NSRange] = []
        private var lastReportedHeight: CGFloat = 0
        private var codeRanges: [NSRange] = []
        private var isHighlighting = false
        private var taskMarkers: [(range: NSRange, state: NSRange, isDone: Bool)] = []

        /// The plain slate every pass starts from, and the attributes typing inherits.
        static let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.preferredFont(forTextStyle: .body),
            .foregroundColor: NSColor.labelColor,
        ]

        init(parent: NoteMarkdownEditor) {
            self.parent = parent
        }

        func update(from incoming: NoteMarkdownEditor) {
            let noteChanged = parent.noteID != incoming.noteID
            let tintChanged = parent.tint != incoming.tint
            parent = incoming
            guard let textView else { return }
            if tintChanged { applyTint() }
            // Marked-text updates need not publish textDidChange; the binding is stale until commit.
            guard noteChanged || !textView.hasMarkedText() else { return }
            if noteChanged || textView.string != incoming.text {
                // Only switching documents may abandon the input method's live composition.
                if textView.hasMarkedText() { textView.inputContext?.discardMarkedText() }
                let selection = textView.selectedRange()
                textView.string = incoming.text
                textView.setSelectedRange(
                    NSRange(location: min(selection.location, (incoming.text as NSString).length), length: 0))
                highlight()
            }
            reportContentHeight()
        }

        /// The caret and selection wear the note's own color: the tint is the note's identity, and
        /// a system-blue caret on a red note reads as a different app's text field.
        func applyTint() {
            guard let textView else { return }
            let accent = parent.tint.map { NSColor(Theme.Colors.noteTintAccent($0)) }
            textView.insertionPointColor = accent ?? .textInsertionPointColor
            textView.selectedTextAttributes = [
                .backgroundColor: accent?.withAlphaComponent(0.35) ?? .selectedTextBackgroundColor
            ]
        }

        func textDidChange(_ notification: Notification) {
            guard let textView, !isHighlighting else { return }
            refreshArithmeticAnswer()
            // AppKit may omit this notification while marked text changes; update(from:) protects that draft.
            parent.text = textView.string
            reportContentHeight()
            // Synchronous, not debounced: a deferred pass leaves a frame where a new line's dash is
            // plain text and every disc below the edit draws from stale ranges — the list "blink"
            // on Return and delete. Caret-only moves keep the debounce in the selection handler.
            highlightWork?.cancel()
            // An uncommitted composition has nothing to restyle yet, and the debounced pass is what
            // guarantees one lands after the commit however the input method finishes it.
            if textView.hasMarkedText() { scheduleHighlight() } else { highlight() }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isHighlighting else { return }
            scheduleHighlight()
        }

        func textView(
            _ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            // An input method inserts its uncommitted composition through this same callback, so the
            // pinyin on its way to a Chinese character would otherwise be read as typing: a rule
            // firing there rewrites text the user has not chosen yet and drops the composition.
            guard !isApplyingInputRule, !textView.hasMarkedText(), affectedCharRange.length == 0,
                let typed = replacementString
            else { return true }
            if applyChecklistInputRule(in: textView, at: affectedCharRange, inserting: typed) {
                return false
            }
            if applyRuleInputRule(in: textView, at: affectedCharRange, inserting: typed) {
                return false
            }
            if typed == "\n" { return insertNewline(in: textView, at: affectedCharRange) }
            if NoteEngine.isArithmeticEquals(typed) {
                return evaluateArithmetic(in: textView, at: affectedCharRange, inserting: typed)
            }
            return true
        }

        /// A Return typed at the visual end of a bold or italic run lands *inside* its hidden closing
        /// marker, which splits `**bold**` across two lines and exposes the syntax it hides. The caret
        /// steps over the marker first, so the run stays whole and the new line starts clean.
        private func insertNewline(in textView: NSTextView, at caret: NSRange) -> Bool {
            let escaped = escapedCaret(for: caret)
            guard escaped.location != caret.location else {
                return continueList(in: textView, at: caret)
            }
            textView.setSelectedRange(escaped)
            guard continueList(in: textView, at: escaped) else { return false }
            return !applyInputRule("\n", over: escaped, in: textView)
        }

        /// Steps a caret out of any concealed closing marker it is sitting at the front of.
        private func escapedCaret(for caret: NSRange) -> NSRange {
            // The markers are the last pass's, so one that no longer fits the document is ignored
            // rather than followed: the caret this returns is set on the text view.
            let length = (textView?.string as NSString?)?.length ?? 0
            var location = caret.location
            while let suffix = concealedSuffixes.first(where: { $0.location == location }),
                NSMaxRange(suffix) <= length
            {
                location = NSMaxRange(suffix)
            }
            return NSRange(location: location, length: 0)
        }

        /// `---` draws a divider, and what follows belongs under it — so completing one opens the
        /// next line rather than leaving the caret stranded on the rule itself.
        private func applyRuleInputRule(
            in textView: NSTextView, at caret: NSRange, inserting typedText: String
        ) -> Bool {
            let source = textView.string as NSString
            guard caret.location == NSMaxRange(lineContentRange(before: caret, in: source)),
                let replacement = NoteEngine.horizontalRuleCompletion(
                    forLinePrefix: source.substring(with: linePrefixRange(before: caret, in: source)),
                    inserting: typedText)
            else { return false }
            return applyInputRule(replacement, over: caret, in: textView)
        }

        /// Keeps an answered line answered: edit the sum and the number after the `=` follows, and a
        /// formula that stops resolving says so rather than leaving a stale answer standing.
        private func refreshArithmeticAnswer() {
            // Rewriting the storage under the caret mid-composition takes the marked text with it.
            guard let textView, !isRewritingAnswer, !textView.hasMarkedText() else { return }
            let source = textView.string as NSString
            let caret = textView.selectedRange()
            guard caret.length == 0, caret.location <= source.length else { return }
            var line = source.lineRange(for: NSRange(location: caret.location, length: 0))
            if line.length > 0, source.substring(with: line).hasSuffix("\n") { line.length -= 1 }
            guard let answer = NoteEngine.arithmeticAnswer(inLine: source.substring(with: line))
            else { return }
            let resultRange = NSRange(
                location: line.location + answer.resultRange.location,
                length: answer.resultRange.length)
            // The user is editing the answer itself — theirs to write, not ours to overwrite.
            guard caret.location < resultRange.location else { return }

            let display = self.answer(for: answer.expression)
            guard display != answer.result,
                textView.shouldChangeText(in: resultRange, replacementString: display)
            else { return }
            isRewritingAnswer = true
            textView.textStorage?.replaceCharacters(in: resultRange, with: display)
            textView.didChangeText()
            textView.setSelectedRange(caret)
            isRewritingAnswer = false
        }

        private func continueList(in textView: NSTextView, at caret: NSRange) -> Bool {
            let source = textView.string as NSString
            let contentRange = lineContentRange(before: caret, in: source)
            guard caret.location == NSMaxRange(contentRange),
                let continuation = NoteEngine.listContinuation(
                    after: source.substring(with: contentRange))
            else { return true }

            let replacementRange: NSRange
            let replacement: String
            switch continuation {
            case .continueWith(let prefix):
                replacementRange = caret
                replacement = "\n" + prefix
            case .endList:
                replacementRange = contentRange
                replacement = ""
            }
            return !applyInputRule(replacement, over: replacementRange, in: textView)
        }

        /// ASCII or Chinese brackets become the same visual todo while the source stays Markdown.
        private func applyChecklistInputRule(
            in textView: NSTextView, at caret: NSRange, inserting typedText: String
        ) -> Bool {
            let source = textView.string as NSString
            let prefixRange = linePrefixRange(before: caret, in: source)
            guard let replacement = NoteEngine.checklistInputRule(
                forLinePrefix: source.substring(with: prefixRange), inserting: typedText)
            else { return false }
            return applyInputRule(replacement, over: prefixRange, in: textView)
        }

        /// `129+92=` answers itself. The calculator engine already owns arithmetic, so a note gets it
        /// for free — and typing `=` after anything that isn't a sum still just types an `=`.
        private func evaluateArithmetic(
            in textView: NSTextView, at caret: NSRange, inserting equals: String
        ) -> Bool {
            let source = textView.string as NSString
            let prefix = source.substring(with: linePrefixRange(before: caret, in: source))
            // A formula that cannot be answered is still a formula: it gets the unresolved marker,
            // where prose ending in an `=` just gets its equals sign.
            guard NoteEngine.arithmeticCandidate(inLinePrefix: prefix) != nil else { return true }
            return !applyInputRule(equals + answer(for: prefix), over: caret, in: textView)
        }

        private func answer(for expressionPrefix: String) -> String {
            guard let expression = NoteEngine.arithmeticExpression(inLinePrefix: expressionPrefix),
                let result = CalcEngine.evaluate(expression),
                case .value(let display, _) = result.payload
            else { return NoteEngine.unresolvedArithmeticResult }
            return display
        }

        /// The line's text from its start up to the caret.
        private func linePrefixRange(before caret: NSRange, in source: NSString) -> NSRange {
            let line = source.lineRange(for: NSRange(location: caret.location, length: 0))
            return NSRange(location: line.location, length: caret.location - line.location)
        }

        /// The line the caret sits on, without its trailing break.
        private func lineContentRange(before caret: NSRange, in source: NSString) -> NSRange {
            var range = source.lineRange(for: NSRange(location: caret.location, length: 0))
            if range.length > 0, source.substring(with: range).hasSuffix("\n") { range.length -= 1 }
            return range
        }

        /// Returns whether the rule was applied, so each caller can report it as "handled".
        private func applyInputRule(
            _ replacement: String, over range: NSRange, in textView: NSTextView
        ) -> Bool {
            isApplyingInputRule = true
            textView.insertText(replacement, replacementRange: range)
            isApplyingInputRule = false
            return true
        }

        /// Tab / Shift-Tab: nest or un-nest the caret's list line; false lets the tab insert.
        func applyIndent(_ direction: NoteIndentDirection) -> Bool {
            // Mid-composition the tab belongs to the input method's own handling, not to the list.
            guard let textView, !textView.hasMarkedText(),
                let result = NoteEngine.applyingListIndent(
                    direction, to: textView.string, selection: textView.selectedRange())
            else { return false }
            apply(result, to: textView)
            return true
        }

        /// Delete with the caret just past a list marker takes the whole marker, so a todo never
        /// erodes through `- [ ]`, `- [` and out the other side as plain text. False everywhere
        /// else, so the key deletes exactly as it always has.
        func deleteListMarker() -> Bool {
            // Mid-composition the delete belongs to the input method, which is still writing the
            // marked run this would rewrite the storage under.
            guard let textView, !textView.hasMarkedText(),
                let marker = NoteEngine.listMarkerDeletion(
                    in: textView.string, selection: textView.selectedRange()),
                textView.shouldChangeText(in: marker, replacementString: "")
            else { return false }
            textView.textStorage?.replaceCharacters(in: marker, with: "")
            textView.didChangeText()
            textView.setSelectedRange(NSRange(location: marker.location, length: 0))
            return true
        }

        func apply(_ command: NoteMarkdownCommand) {
            guard let textView else { return }
            let result = NoteEngine.applying(
                command, to: textView.string, selection: textView.selectedRange())
            apply(result, to: textView)
        }

        func apply(_ format: NoteBlockFormat) {
            guard let textView else { return }
            let result = NoteEngine.applyingBlockFormat(
                format, to: textView.string, selection: textView.selectedRange())
            apply(result, to: textView)
        }

        private func apply(_ result: NoteEditResult, to textView: NSTextView) {
            // Every one of these replaces the whole document; doing that under a live composition
            // leaves the input method holding a marked range into text that no longer exists.
            guard !textView.hasMarkedText() else { return }
            let wholeDocument = NSRange(location: 0, length: (textView.string as NSString).length)
            guard textView.shouldChangeText(in: wholeDocument, replacementString: result.text) else {
                return
            }
            textView.textStorage?.replaceCharacters(in: wholeDocument, with: result.text)
            textView.didChangeText()
            textView.setSelectedRange(result.selection)
            textView.window?.makeFirstResponder(textView)
            highlight()
        }

        func navigate(_ direction: NoteNavigationDirection) {
            parent.onNavigate(direction)
            DispatchQueue.main.async { [weak textView] in
                textView?.window?.makeFirstResponder(textView)
            }
        }

        /// Styling lives in the text storage's *attributes*, never in temporary layout-manager
        /// attributes: those are drawing-only, so a heading would render large while its line box and
        /// caret stayed body-height. Attributes are not characters — `textView.string`, and therefore
        /// everything persisted, is still exactly the Markdown the user typed.
        func highlight() {
            guard let textView, let layout = textView.layoutManager as? NoteLayoutManager,
                let storage = textView.textStorage
            else { return }
            // The text storage is the input method's canvas while a composition is live: resetting
            // attributes across the document strips the marked run's underline, `typingAttributes`
            // is what its next update inherits, and a concealed range would collapse pinyin the user
            // is still choosing from. The commit posts both a text change and a selection change, so
            // the pass this skips runs the moment the characters are real.
            guard !textView.hasMarkedText() else { return }
            let source = textView.string as NSString
            let wholeDocument = NSRange(location: 0, length: source.length)
            var typingAttributes = Self.baseAttributes
            layout.decorations = []
            layout.checkboxes = []
            layout.bullets = []
            taskMarkers = []
            concealedSuffixes = []

            isHighlighting = true
            storage.beginEditing()
            storage.setAttributes(Self.baseAttributes, range: wholeDocument)
            defer {
                storage.endEditing()
                isHighlighting = false
                textView.typingAttributes = typingAttributes
                reportContentHeight()
            }

            guard source.length > 0, source.length <= 200_000 else {
                codeRanges = []
                return
            }

            let spans = NoteEngine.blockSpans(in: textView.string)
            codeRanges = spans.filter { $0.kind == .codeBlock }.map(\.range)

            let bodyFont = NSFont.preferredFont(forTextStyle: .body)

            applyBlocks(spans, storage: storage, layout: layout)

            apply(Self.bold, to: textView.string) { match in
                guard let range = self.firstCapture(in: match) else { return }
                storage.addAttribute(
                    .font,
                    value: NSFontManager.shared.convert(bodyFont, toHaveTrait: .boldFontMask),
                    range: range)
                self.concealSyntax(around: range, in: match.range, storage: storage)
            }
            apply(Self.strikethrough, to: textView.string) { match in
                guard let range = self.firstCapture(in: match) else { return }
                storage.addAttribute(
                    .strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                self.concealSyntax(around: range, in: match.range, storage: storage)
            }
            apply(Self.italic, to: textView.string) { match in
                guard let range = self.firstCapture(in: match) else { return }
                storage.addAttribute(
                    .font,
                    value: NSFontManager.shared.convert(bodyFont, toHaveTrait: .italicFontMask),
                    range: range)
                self.concealSyntax(around: range, in: match.range, storage: storage)
            }
            apply(Self.inlineCode, to: textView.string) { match in
                guard match.numberOfRanges > 1 else { return }
                let range = match.range(at: 1)
                storage.addAttribute(
                    .font,
                    value: NSFont.monospacedSystemFont(ofSize: bodyFont.pointSize, weight: .regular),
                    range: range)
                self.concealSyntax(around: range, in: match.range, storage: storage)
            }
            apply(Self.link, to: textView.string) { match in
                guard match.numberOfRanges > 1 else { return }
                let range = match.range(at: 1)
                storage.addAttribute(
                    .underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                self.concealSyntax(around: range, in: match.range, storage: storage)
            }
            let slot = applyOrderedMarkers(in: textView.string, storage: storage)
            applyBullets(in: textView.string, storage: storage, layout: layout, slot: slot)
            applyCheckboxes(in: textView.string, storage: storage, layout: layout, slot: slot)
            apply(Self.completedTask, to: textView.string) { match in
                guard match.numberOfRanges > 1 else { return }
                storage.addAttribute(
                    .strikethroughStyle, value: NSUnderlineStyle.single.rawValue,
                    range: match.range(at: 1))
            }
            apply(Self.heading, to: textView.string) { match in
                guard match.numberOfRanges > 2 else { return }
                let marker = source.substring(with: match.range(at: 1))
                // A real hierarchy: H1 dominates the page, H2 is clearly a section, H3 only just
                // outgrows the body text, and deeper levels carry weight instead of more size.
                let style: NSFont.TextStyle =
                    switch marker.count {
                    case 1: .largeTitle
                    case 2: .title1
                    case 3: .title3
                    default: .headline
                    }
                let font = NSFont.preferredFont(forTextStyle: style)
                storage.addAttribute(.font, value: font, range: match.range)
                let selection = textView.selectedRange()
                if selection.length == 0, selection.location >= match.range.location,
                    selection.location <= NSMaxRange(match.range)
                {
                    typingAttributes[.font] = font
                }
                self.concealSyntax(around: match.range(at: 2), in: match.range, storage: storage)
            }
            apply(Self.listLine, to: textView.string) { match in
                guard match.numberOfRanges > 1 else { return }
                let style = NSMutableParagraphStyle()
                style.firstLineHeadIndent = 0
                // Every marker was kerned out to the same cell, so a wrapped line hangs at the one
                // content edge whichever kind of list it belongs to.
                style.headIndent =
                    NoteListMarker.indentationWidth(source.substring(with: match.range(at: 1)))
                    + slot
                // A raw tab in list indentation renders one indent unit wide, not the default
                // 28-point stop — nesting should read as a step, not a gulf.
                style.tabStops = []
                style.defaultTabInterval = NoteListMarker.indentUnit
                storage.addAttribute(.paragraphStyle, value: style, range: match.range)
            }
        }

        /// Kerns a marker's last character so the whole marker advances exactly one cell. Kerning is
        /// an attribute, not a character: `textView.string` keeps what the user typed.
        private func fit(_ marker: NSRange, to slot: CGFloat, in storage: NSTextStorage) {
            guard marker.length > 0 else { return }
            let last = NSRange(location: NSMaxRange(marker) - 1, length: 1)
            let existing = storage.attribute(.kern, at: last.location, effectiveRange: nil)
            let kern = (existing as? NSNumber).map { CGFloat($0.doubleValue) } ?? 0
            storage.addAttribute(
                .kern, value: kern + slot - width(of: marker, in: storage), range: last)
        }

        /// Gives one character an exact advance, so the square drawn over it is the same square on
        /// every kind of list line.
        private func stretch(_ character: NSRange, to advance: CGFloat, in storage: NSTextStorage) {
            let font =
                storage.attribute(.font, at: character.location, effectiveRange: nil) as? NSFont
                ?? NoteListMarker.bodyFont
            let glyph = (storage.string as NSString).substring(with: character)
            storage.addAttribute(
                .kern, value: advance - NoteListMarker.width(of: glyph, in: font), range: character)
        }

        /// A range's rendered advance: every run measured in its own font, plus the kerning already
        /// on it — the collapsed syntax either side of a todo's state character included.
        private func width(of range: NSRange, in storage: NSTextStorage) -> CGFloat {
            let source = storage.string as NSString
            var total: CGFloat = 0
            storage.enumerateAttributes(in: range, options: []) { attributes, run, _ in
                let font = attributes[.font] as? NSFont ?? NoteListMarker.bodyFont
                let kern = (attributes[.kern] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 0
                total +=
                    NoteListMarker.width(of: source.substring(with: run), in: font)
                    + kern * CGFloat(run.length)
            }
            return total
        }

        /// `1.` `9.` `10.` only line up under one another in a font whose digits are all one width,
        /// and the marker is the only part of the line that has to line up — the prose after it
        /// stays in the body font. Runs first of the list passes and returns the cell every marker
        /// is fitted to, since an ordered marker is the only one whose natural width can outgrow it.
        private func applyOrderedMarkers(in text: String, storage: NSTextStorage) -> CGFloat {
            let source = text as NSString
            let monospaced = NoteListMarker.monospacedFont
            var slot = NoteListMarker.baseSlot
            var markers: [NSRange] = []
            apply(Self.orderedMarker, to: text) { match in
                guard match.numberOfRanges > 2 else { return }
                let marker = match.range(at: 2)
                storage.addAttribute(.font, value: monospaced, range: marker)
                markers.append(marker)
                slot = max(
                    slot, NoteListMarker.width(of: source.substring(with: marker), in: monospaced))
            }
            for marker in markers { fit(marker, to: slot, in: storage) }
            return slot
        }

        /// The list dash is drawn as a real bullet rather than swapped for the font's `bullet`
        /// glyph, which comes out the size of a period. The dash is cleared rather than removed and
        /// its cell widened to the shared decoration square, so the disc lands exactly where a todo
        /// box would; the space after it carries the rest of the marker cell.
        private func applyBullets(
            in text: String, storage: NSTextStorage, layout: NoteLayoutManager, slot: CGFloat
        ) {
            apply(Self.bulletMarker, to: text) { match in
                guard match.numberOfRanges > 2 else { return }
                let dash = match.range(at: 2)
                storage.addAttribute(.foregroundColor, value: NSColor.clear, range: dash)
                self.stretch(dash, to: NoteListMarker.decorationSide, in: storage)
                self.fit(
                    NSRange(
                        location: dash.location, length: NSMaxRange(match.range) - dash.location),
                    to: slot, in: storage)
                layout.bullets.append(dash)
            }
        }

        /// The Markdown task marker collapses into a checkbox that stays visible because it is a control.
        private func applyCheckboxes(
            in text: String, storage: NSTextStorage, layout: NoteLayoutManager, slot: CGFloat
        ) {
            apply(Self.taskMarker, to: text) { match in
                guard match.numberOfRanges > 3 else { return }
                let opening = match.range(at: 1)
                let state = match.range(at: 2)
                let closing = NSRange(location: match.range(at: 3).location, length: 1)
                let isDone = (text as NSString).substring(with: state).lowercased() == "x"

                self.hide(opening, in: storage)
                self.hide(closing, in: storage)
                storage.addAttribute(.foregroundColor, value: NSColor.clear, range: state)
                self.stretch(state, to: NoteListMarker.decorationSide, in: storage)
                self.fit(
                    NSRange(
                        location: opening.location,
                        length: NSMaxRange(match.range) - opening.location),
                    to: slot, in: storage)
                layout.checkboxes.append(NoteLayoutManager.Checkbox(range: state, isDone: isDone))
                self.taskMarkers.append((range: match.range, state: state, isDone: isDone))
            }
        }

        /// Toggles the checkbox under a click, reporting whether one was there.
        func toggleCheckbox(atCharacterIndex index: Int) -> Bool {
            // Mid-composition the markers are from the last pass and the click belongs to the input
            // method: let the normal mouse path end the composition instead of editing under it.
            guard let textView, !textView.hasMarkedText(),
                let marker = taskMarkers.first(where: { NSLocationInRange(index, $0.range) })
            else { return false }
            // This writes over a range the last pass collected, so it has to still be the state
            // character it was found as — otherwise a stale marker would overwrite the user's text.
            let source = textView.string as NSString
            guard NSMaxRange(marker.state) <= source.length,
                [" ", "x", "X"].contains(source.substring(with: marker.state))
            else { return false }
            guard textView.shouldChangeText(in: marker.state, replacementString: marker.isDone ? " " : "x")
            else { return false }
            textView.textStorage?.replaceCharacters(
                in: marker.state, with: marker.isDone ? " " : "x")
            textView.didChangeText()
            highlight()
            return true
        }

        /// Block constructs: the fenced-code panel, the blockquote bar, the horizontal rule and the
        /// monospaced pipe table. Their fills are drawn by `NoteLayoutManager`; the text styling here
        /// is what makes the source read as the block it describes.
        private func applyBlocks(
            _ spans: [NoteBlockSpan], storage: NSTextStorage, layout: NoteLayoutManager
        ) {
            let bodyFont = NSFont.preferredFont(forTextStyle: .body)
            let monospaced = NSFont.monospacedSystemFont(
                ofSize: bodyFont.pointSize, weight: .regular)

            for span in spans {
                switch span.kind {
                case .codeBlock:
                    storage.addAttribute(.font, value: monospaced, range: span.range)
                    storage.addAttribute(
                        .paragraphStyle, value: Self.indented(by: Theme.Spacing.lg),
                        range: span.range)
                    layout.decorations.append(.codeBlock(span.range))
                case .codeFence:
                    storage.addAttribute(
                        .foregroundColor, value: NSColor.tertiaryLabelColor, range: span.range)
                case .quote:
                    storage.addAttribute(
                        .foregroundColor, value: NSColor.secondaryLabelColor, range: span.range)
                    storage.addAttribute(
                        .paragraphStyle, value: Self.indented(by: Theme.Spacing.xl),
                        range: span.range)
                    layout.decorations.append(.quoteBar(span.range))
                    let body = NSRange(
                        location: NSMaxRange(span.markerRange),
                        length: NSMaxRange(span.range) - NSMaxRange(span.markerRange))
                    concealSyntax(around: body, in: span.range, storage: storage)
                case .rule:
                    layout.decorations.append(.rule(span.range))
                    storage.addAttribute(
                        .foregroundColor, value: NSColor.clear, range: span.range)
                case .tableRow:
                    storage.addAttribute(.font, value: monospaced, range: span.range)
                }
            }
        }

        private static func indented(by amount: CGFloat) -> NSParagraphStyle {
            let style = NSMutableParagraphStyle()
            style.firstLineHeadIndent = amount
            style.headIndent = amount
            return style
        }

        func reportContentHeight() {
            guard let textView, let layout = textView.layoutManager,
                let container = textView.textContainer
            else { return }
            layout.ensureLayout(for: container)
            let textHeight = max(
                layout.usedRect(for: container).height, NoteEditorMetrics.minimumTextHeight)
            let unboundedHeight = NoteEditorMetrics.editorHeight(forTextHeight: textHeight)
            let height = min(
                max(unboundedHeight, NoteEditorMetrics.minimumEditorHeight),
                NoteEditorMetrics.maximumEditorHeight)
            if let scrollView = textView.enclosingScrollView {
                // A hand-sized window is bounded by its own frame, not by the height the window
                // would have grown to, so the ceiling the scroller answers to differs per mode.
                let ceiling = parent.autoSizes
                    ? NoteEditorMetrics.maximumEditorHeight
                    : scrollView.contentView.bounds.height
                let needsScroller = unboundedHeight > ceiling + 0.5
                if scrollView.hasVerticalScroller != needsScroller {
                    scrollView.hasVerticalScroller = needsScroller
                }
                if !needsScroller {
                    scrollView.contentView.scroll(to: .zero)
                    scrollView.reflectScrolledClipView(scrollView.contentView)
                }
            }
            guard abs(lastReportedHeight - height) > 0.5 else { return }
            lastReportedHeight = height
            DispatchQueue.main.async { [weak self] in
                self?.parent.onContentHeightChange(height)
            }
        }

        private func scheduleHighlight() {
            highlightWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.highlight() }
            highlightWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: work)
        }

        private func apply(
            _ expression: NSRegularExpression, to text: String,
            action: (NSTextCheckingResult) -> Void
        ) {
            let range = NSRange(location: 0, length: (text as NSString).length)
            expression.enumerateMatches(in: text, range: range) { match, _, _ in
                // Inside a fence the markers are the content — a `# ` there is a comment, not a heading.
                guard let match, !isInsideCode(match.range) else { return }
                action(match)
            }
        }

        private func isInsideCode(_ range: NSRange) -> Bool {
            codeRanges.contains { NSIntersectionRange($0, range).length > 0 }
        }

        private func concealSyntax(
            around content: NSRange, in fullRange: NSRange, storage: NSTextStorage
        ) {
            let prefix = NSRange(
                location: fullRange.location, length: content.location - fullRange.location)
            let suffix = NSRange(
                location: NSMaxRange(content), length: NSMaxRange(fullRange) - NSMaxRange(content))
            if suffix.length > 0 { concealedSuffixes.append(suffix) }
            for range in [prefix, suffix] { hide(range, in: storage) }
        }

        /// Collapses a range to nothing: no width, no ink. Now that styling lives in the storage this
        /// genuinely removes the syntax from the line rather than merely drawing it small.
        private func hide(_ range: NSRange, in storage: NSTextStorage) {
            guard range.length > 0 else { return }
            storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 0.1), range: range)
            storage.addAttribute(.foregroundColor, value: NSColor.clear, range: range)
        }

        private func firstCapture(in match: NSTextCheckingResult) -> NSRange? {
            for index in 1..<match.numberOfRanges {
                let range = match.range(at: index)
                if range.location != NSNotFound { return range }
            }
            return nil
        }

        private static let bold = try! NSRegularExpression(
            pattern: #"\*\*([^\n*]+)\*\*|__([^\n_]+)__"#)
        private static let italic = try! NSRegularExpression(
            pattern: #"(?<!\*)\*([^\n*]+)\*(?!\*)|(?<!_)_([^\n_]+)_(?!_)"#)
        private static let strikethrough = try! NSRegularExpression(pattern: #"~~([^\n~]+)~~"#)
        // Captures the syntax to collapse either side of the state character the box is drawn over.
        private static let taskMarker = try! NSRegularExpression(
            pattern: #"(?m)^[ \t]*([-*+] \[)([ xX])(\] )"#)
        private static let inlineCode = try! NSRegularExpression(pattern: #"`([^\n`]+)`"#)
        private static let link = try! NSRegularExpression(pattern: #"\[([^\]]+)\]\([^\)]+\)"#)
        private static let completedTask = try! NSRegularExpression(
            pattern: #"(?m)^\s*- \[[xX]\]\s+(.+)$"#)
        // The body may be empty so a heading takes effect the moment its marker and space are typed.
        private static let heading = try! NSRegularExpression(
            pattern: #"(?m)^(#{1,6})[ \t]+(.*)$"#)
        // A dash that opens a todo belongs to the checkbox, not to a bullet.
        private static let bulletMarker = try! NSRegularExpression(
            pattern: #"(?m)^([ \t]*)([-*+]) (?!\[[ xX]\] )"#)
        private static let orderedMarker = try! NSRegularExpression(
            pattern: #"(?m)^([ \t]*)(\d+\. )"#)
        private static let listLine = try! NSRegularExpression(
            pattern: #"(?m)^([ \t]*)([-*+] \[[ xX]\] |[-*+] |\d+\. ).+$"#)
    }
}

/// Draws the block fills a note's Markdown implies — the fenced-code panel, the blockquote bar and
/// the horizontal rule. They are painted behind the text instead of inserted into it, so the note's
/// source stays exactly the Markdown the user typed.
private final class NoteLayoutManager: NSLayoutManager {
    enum Decoration {
        case codeBlock(NSRange)
        case quoteBar(NSRange)
        case rule(NSRange)

        var range: NSRange {
            switch self {
            case .codeBlock(let range), .quoteBar(let range), .rule(let range): range
            }
        }

        func moved(to range: NSRange) -> Decoration {
            switch self {
            case .codeBlock: .codeBlock(range)
            case .quoteBar: .quoteBar(range)
            case .rule: .rule(range)
            }
        }
    }

    /// One todo box, drawn over the kerned-out state character of a `- [ ] ` marker.
    struct Checkbox {
        let range: NSRange
        let isDone: Bool
    }

    var decorations: [Decoration] = []
    var checkboxes: [Checkbox] = []
    /// Cleared list dashes, each drawn as a filled disc in the slot the dash left behind.
    var bullets: [NSRange] = []
    /// Breathing room between the todo box and the character slot kerned out for it.
    private static let checkboxMargin: CGFloat = 1.5
    private static let checkboxStroke: CGFloat = 1.5
    private static let minimumBulletDiameter: CGFloat = 5
    /// A disc filling the whole decoration square reads as a blob beside body text, so the bullet
    /// is inscribed in the square the todo box occupies rather than drawn to its edges.
    private static let bulletFraction: CGFloat = 0.38

    /// These ranges come from a whole-document pass that deliberately stands down while an input
    /// method holds a composition, so between passes the text moves under ranges already collected —
    /// and a Chinese list line is where that shows: every disc and box below the caret would be
    /// drawn one composition's worth of characters too early, on the user's own glyphs, while the
    /// markers they belong to sit cleared and undrawn. The text storage fixes its attributes on
    /// every edit; the decorations are fixed the same way, so a marker is only ever drawn where the
    /// pass that found it still describes the text.
    override func processEditing(
        for textStorage: NSTextStorage, edited editMask: NSTextStorageEditActions,
        range newCharRange: NSRange, changeInLength delta: Int, invalidatedRange: NSRange
    ) {
        super.processEditing(
            for: textStorage, edited: editMask, range: newCharRange, changeInLength: delta,
            invalidatedRange: invalidatedRange)
        guard editMask.contains(.editedCharacters), delta != 0 || newCharRange.length > 0 else {
            return
        }
        // `newCharRange` is the edit after the fact; the collected ranges predate it.
        let edited = NSRange(
            location: newCharRange.location, length: max(newCharRange.length - delta, 0))
        let length = textStorage.length
        func adjust(_ range: NSRange) -> NSRange? {
            NoteEngine.adjusting(
                range, forEdit: edited, changeInLength: delta, documentLength: length)
        }
        decorations = decorations.compactMap { decoration in
            adjust(decoration.range).map(decoration.moved(to:))
        }
        checkboxes = checkboxes.compactMap { checkbox in
            adjust(checkbox.range).map { Checkbox(range: $0, isDone: checkbox.isDone) }
        }
        bullets = bullets.compactMap(adjust)
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let container = textContainers.first else { return }
        drawCheckboxes(forGlyphRange: glyphsToShow, at: origin, in: container)
        drawBullets(forGlyphRange: glyphsToShow, at: origin, in: container)
        guard !decorations.isEmpty else { return }
        let padding = container.lineFragmentPadding
        let width = max(container.size.width - padding * 2, 0)
        let visible = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)

        for decoration in decorations
        where NSIntersectionRange(decoration.range, visible).length > 0 {
            guard let rect = lineRect(for: decoration.range) else { continue }
            let left = origin.x + padding
            let top = origin.y + rect.minY

            switch decoration {
            case .codeBlock:
                NSColor(Theme.Colors.controlSurface).setFill()
                NSBezierPath(
                    roundedRect: NSRect(x: left, y: top, width: width, height: rect.height),
                    xRadius: Theme.Radius.card, yRadius: Theme.Radius.card
                ).fill()
            case .quoteBar:
                NSColor(Theme.Colors.border).setFill()
                NSBezierPath(
                    roundedRect: NSRect(x: left, y: top, width: 2, height: rect.height),
                    xRadius: 1, yRadius: 1
                ).fill()
            case .rule:
                NSColor(Theme.Colors.separator).setFill()
                NSRect(
                    x: left, y: (origin.y + rect.midY).rounded(), width: width, height: 1
                ).fill()
            }
        }
    }

    /// A disc centred in the same square the todo box fills, on the cell the cleared dash was
    /// kerned out to. Drawn rather than substituted so it can be sized for reading — the font's own
    /// bullet glyph is barely larger than a period.
    private func drawBullets(
        forGlyphRange glyphsToShow: NSRange, at origin: NSPoint, in container: NSTextContainer
    ) {
        guard !bullets.isEmpty else { return }
        let visible = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        NSColor.labelColor.setFill()
        for bullet in bullets where NSIntersectionRange(bullet, visible).length > 0 {
            guard let box = decorationBox(for: bullet, at: origin, in: container) else { continue }
            let diameter = max(
                Self.minimumBulletDiameter, (box.width * Self.bulletFraction).rounded())
            let disc = NSRect(
                x: (box.midX - diameter / 2).rounded(),
                y: (box.midY - diameter / 2).rounded(),
                width: diameter, height: diameter)
            NSBezierPath(ovalIn: disc).fill()
        }
    }

    /// The square a marker's decoration is drawn in: its own character cell, inset so the edges are
    /// not flush against the text container. Both marks come from here, so a bullet and a todo box
    /// on neighbouring lines are the same size in the same place.
    private func decorationBox(
        for marker: NSRange, at origin: NSPoint, in container: NSTextContainer
    ) -> NSRect? {
        let glyphs = glyphRange(forCharacterRange: marker, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return nil }
        let slot = boundingRect(forGlyphRange: glyphs, in: container)
        let side = (min(slot.height, slot.width) - Self.checkboxMargin * 2).rounded()
        guard side > 4 else { return nil }
        return NSRect(
            x: (origin.x + slot.minX + Self.checkboxMargin).rounded(),
            y: (origin.y + slot.midY - side / 2).rounded(),
            width: side, height: side)
    }

    /// A rounded square in the space the marker's state character was kerned out to, filled with a
    /// checkmark once done. Drawn rather than substituted so the note's source keeps its Markdown.
    private func drawCheckboxes(
        forGlyphRange glyphsToShow: NSRange, at origin: NSPoint, in container: NSTextContainer
    ) {
        guard !checkboxes.isEmpty else { return }
        let visible = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        for checkbox in checkboxes
        where NSIntersectionRange(checkbox.range, visible).length > 0 {
            guard let box = decorationBox(for: checkbox.range, at: origin, in: container)
            else { continue }
            let side = box.width
            let stroke = Self.checkboxStroke
            let outline = NSBezierPath(
                roundedRect: checkbox.isDone ? box : box.insetBy(dx: stroke / 2, dy: stroke / 2),
                xRadius: Theme.Radius.noteCheckbox, yRadius: Theme.Radius.noteCheckbox)

            if checkbox.isDone {
                NSColor.controlAccentColor.setFill()
                outline.fill()
                // A text view is flipped, so `minY` is the top edge: the tick dips to `maxY` in the
                // middle and rises to `minY` on the right.
                let tick = NSBezierPath()
                tick.move(to: NSPoint(x: box.minX + side * 0.26, y: box.midY + side * 0.02))
                tick.line(to: NSPoint(x: box.minX + side * 0.44, y: box.maxY - side * 0.26))
                tick.line(to: NSPoint(x: box.maxX - side * 0.22, y: box.minY + side * 0.26))
                tick.lineWidth = max(stroke, side * 0.14)
                tick.lineCapStyle = .round
                tick.lineJoinStyle = .round
                NSColor.white.setStroke()
                tick.stroke()
            } else {
                NSColor(Theme.Colors.border).setStroke()
                outline.lineWidth = stroke
                outline.stroke()
            }
        }
    }

    /// The union of the line fragments a character range occupies, in text-container coordinates.
    private func lineRect(for range: NSRange) -> NSRect? {
        let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return nil }
        var union: NSRect?
        enumerateLineFragments(forGlyphRange: glyphs) { fragment, _, _, _, _ in
            union = union.map { $0.union(fragment) } ?? fragment
        }
        return union
    }
}

@MainActor
private final class NoteTextView: NSTextView {
    var markdownCommandHandler: ((NoteMarkdownCommand) -> Void)?
    var blockFormatHandler: ((NoteBlockFormat) -> Void)?
    var navigationHandler: ((NoteNavigationDirection) -> Void)?
    /// Reports the character index clicked and whether a todo box was toggled there.
    var checkboxClickHandler: ((Int) -> Bool)?
    /// Returns whether the line took the indent, so a plain tab can still be typed elsewhere.
    var indentHandler: ((NoteIndentDirection) -> Bool)?
    /// Returns whether a whole list marker was removed, so Delete falls through everywhere else.
    var deleteHandler: (() -> Bool)?

    override func deleteBackward(_ sender: Any?) {
        if deleteHandler?() == true { return }
        super.deleteBackward(sender)
    }

    override func insertTab(_ sender: Any?) {
        if indentHandler?(.indent) == true { return }
        super.insertTab(sender)
    }

    override func insertBacktab(_ sender: Any?) {
        if indentHandler?(.outdent) == true { return }
        super.insertBacktab(sender)
    }

    override func mouseDown(with event: NSEvent) {
        if let index = characterIndex(for: event), checkboxClickHandler?(index) == true { return }
        super.mouseDown(with: event)
    }

    private func characterIndex(for event: NSEvent) -> Int? {
        guard let layoutManager, let textContainer else { return nil }
        var point = convert(event.locationInWindow, from: nil)
        point.x -= textContainerOrigin.x
        point.y -= textContainerOrigin.y
        let glyph = layoutManager.glyphIndex(for: point, in: textContainer)
        return layoutManager.characterIndexForGlyph(at: glyph)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard selectedRange().length > 0 else { return super.menu(for: event) }

        let menu = NSMenu()
        menu.addItem(contextMenuItem("Copy", action: #selector(copy(_:)), keyEquivalent: "c"))
        menu.addItem(contextMenuItem("Paste", action: #selector(paste(_:)), keyEquivalent: "v"))
        menu.addItem(.separator())

        menu.addItem(.sectionHeader(title: "Format"))
        menu.addItem(contextMenuItem("Text", action: #selector(formatText(_:))))
        menu.addItem(contextMenuItem("Heading 1", action: #selector(formatHeading1(_:))))
        menu.addItem(contextMenuItem("Heading 2", action: #selector(formatHeading2(_:))))
        menu.addItem(contextMenuItem("Heading 3", action: #selector(formatHeading3(_:))))
        menu.addItem(contextMenuItem("Numbered List", action: #selector(formatNumberedList(_:))))
        menu.addItem(contextMenuItem("Bulleted List", action: #selector(formatBulletedList(_:))))

        menu.addItem(.separator())
        menu.addItem(contextMenuItem("Bold", action: #selector(formatBold(_:)), keyEquivalent: "b"))
        menu.addItem(
            contextMenuItem("Italic", action: #selector(formatItalic(_:)), keyEquivalent: "i"))
        return menu
    }

    private func contextMenuItem(
        _ title: String, action: Selector, keyEquivalent: String = ""
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        if !keyEquivalent.isEmpty { item.keyEquivalentModifierMask = [.command] }
        return item
    }

    @objc private func formatText(_ sender: Any?) {
        blockFormatHandler?(.text)
    }

    @objc private func formatHeading1(_ sender: Any?) {
        blockFormatHandler?(.heading1)
    }

    @objc private func formatHeading2(_ sender: Any?) {
        blockFormatHandler?(.heading2)
    }

    @objc private func formatHeading3(_ sender: Any?) {
        blockFormatHandler?(.heading3)
    }

    @objc private func formatNumberedList(_ sender: Any?) {
        blockFormatHandler?(.numberedList)
    }

    @objc private func formatBulletedList(_ sender: Any?) {
        blockFormatHandler?(.bulletedList)
    }

    @objc private func formatBold(_ sender: Any?) {
        markdownCommandHandler?(.bold)
    }

    @objc private func formatItalic(_ sender: Any?) {
        markdownCommandHandler?(.italic)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers == .command,
            let key = event.charactersIgnoringModifiers?.lowercased()
        else { return super.performKeyEquivalent(with: event) }

        switch key {
        case "b":
            markdownCommandHandler?(.bold)
        case "i":
            markdownCommandHandler?(.italic)
        case "k":
            markdownCommandHandler?(.link)
        case "[":
            navigationHandler?(.previous)
        case "]":
            navigationHandler?(.next)
        default:
            return super.performKeyEquivalent(with: event)
        }
        return true
    }
}
