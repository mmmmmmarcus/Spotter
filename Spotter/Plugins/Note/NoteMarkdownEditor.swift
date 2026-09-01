import AppKit
import SwiftUI

@MainActor
enum NoteEditorMetrics {
    static let minimumLines = 3
    static let maximumLines = 20

    private static var bodyLineHeight: CGFloat {
        let font = NSFont.preferredFont(forTextStyle: .body)
        return ceil(font.ascender - font.descender + font.leading)
    }

    static var minimumEditorHeight: CGFloat {
        bodyLineHeight * CGFloat(minimumLines) + Theme.Spacing.xxl * 2
    }

    static var maximumEditorHeight: CGFloat {
        bodyLineHeight * CGFloat(maximumLines) + Theme.Spacing.xxl * 2
    }

    static func estimatedEditorHeight(for markdown: String) -> CGFloat {
        let lines = NoteEngine.editorLineCount(
            in: markdown, minimum: minimumLines, maximum: maximumLines)
        return bodyLineHeight * CGFloat(lines) + Theme.Spacing.xxl * 2
    }

    static func windowHeight(forEditorHeight editorHeight: CGFloat) -> CGFloat {
        Theme.Size.noteToolbarHeight + editorHeight
    }
}

struct NoteMarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    let tint: NoteTint?
    let onContentHeightChange: (CGFloat) -> Void
    let onNavigate: (NoteNavigationDirection) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
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
        textView.markdownCommandHandler = { [weak coordinator = context.coordinator] command in
            coordinator?.apply(command)
        }
        textView.blockFormatHandler = { [weak coordinator = context.coordinator] format in
            coordinator?.apply(format)
        }
        textView.checkboxClickHandler = { [weak coordinator = context.coordinator] index in
            coordinator?.toggleCheckbox(atCharacterIndex: index) ?? false
        }
        textView.indentHandler = { [weak coordinator = context.coordinator] direction in
            coordinator?.applyIndent(direction) ?? false
        }
        textView.navigationHandler = { [weak coordinator = context.coordinator] direction in
            coordinator?.navigate(direction)
        }
        textView.delegate = context.coordinator
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
        textView.textContainerInset = NSSize(width: Theme.Spacing.xxl, height: Theme.Spacing.xxl)
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.applyTint()
        context.coordinator.highlight()

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
            context.coordinator.reportContentHeight()
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let tintChanged = context.coordinator.parent.tint != tint
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }
        if tintChanged { context.coordinator.applyTint() }
        if textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(
                NSRange(location: min(selection.location, (text as NSString).length), length: 0))
            context.coordinator.highlight()
        }
        context.coordinator.reportContentHeight()
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
            parent.text = textView.string
            reportContentHeight()
            // Synchronous, not debounced: a deferred pass leaves a frame where a new line's dash is
            // plain text and every disc below the edit draws from stale ranges — the list "blink"
            // on Return and delete. Caret-only moves keep the debounce in the selection handler.
            highlightWork?.cancel()
            highlight()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isHighlighting else { return }
            scheduleHighlight()
        }

        func textView(
            _ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard !isApplyingInputRule, affectedCharRange.length == 0,
                let typed = replacementString
            else { return true }
            if applyChecklistInputRule(in: textView, at: affectedCharRange, inserting: typed) {
                return false
            }
            if applyRuleInputRule(in: textView, at: affectedCharRange, inserting: typed) {
                return false
            }
            switch typed {
            case "\n": return insertNewline(in: textView, at: affectedCharRange)
            case "=": return evaluateArithmetic(in: textView, at: affectedCharRange)
            default: return true
            }
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
            var location = caret.location
            while let suffix = concealedSuffixes.first(where: { $0.location == location }) {
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
            guard let textView, !isRewritingAnswer else { return }
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
        private func evaluateArithmetic(in textView: NSTextView, at caret: NSRange) -> Bool {
            let source = textView.string as NSString
            let prefix = source.substring(with: linePrefixRange(before: caret, in: source))
            // A formula that cannot be answered is still a formula: it gets the unresolved marker,
            // where prose ending in an `=` just gets its equals sign.
            guard NoteEngine.arithmeticCandidate(inLinePrefix: prefix) != nil else { return true }
            return !applyInputRule("=" + answer(for: prefix), over: caret, in: textView)
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
            guard let textView,
                let result = NoteEngine.applyingListIndent(
                    direction, to: textView.string, selection: textView.selectedRange())
            else { return false }
            apply(result, to: textView)
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
            applyBullets(in: textView.string, storage: storage, layout: layout)
            applyCheckboxes(in: textView.string, storage: storage, layout: layout)
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
                guard match.numberOfRanges > 2 else { return }
                let indentation = source.substring(with: match.range(at: 1))
                let marker = source.substring(with: match.range(at: 2))
                let font = storage.attribute(
                    .font, at: match.range.location, effectiveRange: nil) as? NSFont ?? bodyFont
                let style = NSMutableParagraphStyle()
                style.firstLineHeadIndent = 0
                style.headIndent = Self.listContinuationIndent(
                    indentation: indentation, marker: marker, font: font)
                // A raw tab in list indentation renders one indent unit wide, not the default
                // 28-point stop — nesting should read as a step, not a gulf.
                style.tabStops = []
                style.defaultTabInterval = (NoteEngine.listIndentUnit as NSString).size(
                    withAttributes: [.font: bodyFont]).width
                storage.addAttribute(.paragraphStyle, value: style, range: match.range)
            }
        }

        private static func listContinuationIndent(
            indentation: String, marker: String, font: NSFont
        ) -> CGFloat {
            let indentationWidth = (indentation as NSString).size(
                withAttributes: [.font: font]).width
            if marker.range(
                of: #"^[-*+] \[[ xX]\] "#, options: .regularExpression) != nil
            {
                let bodyFont = NSFont.preferredFont(forTextStyle: .body)
                return indentationWidth + (bodyFont.ascender - bodyFont.descender).rounded()
            }
            return indentationWidth + (marker as NSString).size(
                withAttributes: [.font: font]).width
        }

        /// The list dash is drawn as a real bullet rather than swapped for the font's `bullet`
        /// glyph, which comes out the size of a period. Clearing the dash keeps its width, so the
        /// hanging indent and everything measured from the marker stay where they were.
        private func applyBullets(
            in text: String, storage: NSTextStorage, layout: NoteLayoutManager
        ) {
            apply(Self.bulletMarker, to: text) { match in
                guard match.numberOfRanges > 2 else { return }
                let marker = match.range(at: 2)
                storage.addAttribute(.foregroundColor, value: NSColor.clear, range: marker)
                layout.bullets.append(marker)
            }
        }

        /// The Markdown task marker collapses into a checkbox that stays visible because it is a control.
        private func applyCheckboxes(
            in text: String, storage: NSTextStorage, layout: NoteLayoutManager
        ) {
            let bodyFont = NSFont.preferredFont(forTextStyle: .body)
            let box = (bodyFont.ascender - bodyFont.descender).rounded()
            apply(Self.taskMarker, to: text) { match in
                guard match.numberOfRanges > 3 else { return }
                let opening = match.range(at: 1)
                let state = match.range(at: 2)
                let closing = NSRange(location: match.range(at: 3).location, length: 1)
                let isDone = (text as NSString).substring(with: state).lowercased() == "x"

                self.hide(opening, in: storage)
                self.hide(closing, in: storage)
                storage.addAttribute(.foregroundColor, value: NSColor.clear, range: state)
                storage.addAttribute(
                    .kern, value: box - (" " as NSString).size(withAttributes: [.font: bodyFont]).width,
                    range: state)
                layout.checkboxes.append(NoteLayoutManager.Checkbox(range: state, isDone: isDone))
                self.taskMarkers.append((range: match.range, state: state, isDone: isDone))
            }
        }

        /// Toggles the checkbox under a click, reporting whether one was there.
        func toggleCheckbox(atCharacterIndex index: Int) -> Bool {
            guard let textView,
                let marker = taskMarkers.first(where: { NSLocationInRange(index, $0.range) })
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
            let usedHeight = max(
                layout.usedRect(for: container).height,
                NoteEditorMetrics.minimumEditorHeight - Theme.Spacing.xxl * 2)
            let unboundedHeight = usedHeight + Theme.Spacing.xxl * 2
            let height = min(
                max(unboundedHeight, NoteEditorMetrics.minimumEditorHeight),
                NoteEditorMetrics.maximumEditorHeight)
            if let scrollView = textView.enclosingScrollView {
                let needsScroller = unboundedHeight > NoteEditorMetrics.maximumEditorHeight + 0.5
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

    /// A disc centred on the slot the cleared dash still occupies. Drawn rather than substituted so
    /// it can be sized for reading — the font's own bullet glyph is barely larger than a period.
    private func drawBullets(
        forGlyphRange glyphsToShow: NSRange, at origin: NSPoint, in container: NSTextContainer
    ) {
        guard !bullets.isEmpty else { return }
        let visible = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        NSColor.labelColor.setFill()
        for bullet in bullets where NSIntersectionRange(bullet, visible).length > 0 {
            let glyphs = glyphRange(forCharacterRange: bullet, actualCharacterRange: nil)
            guard glyphs.length > 0 else { continue }
            let slot = boundingRect(forGlyphRange: glyphs, in: container)
            let font =
                textStorage?.attribute(.font, at: bullet.location, effectiveRange: nil) as? NSFont
                ?? NSFont.preferredFont(forTextStyle: .body)
            let diameter = max(Self.minimumBulletDiameter, (font.pointSize * 0.42).rounded())
            let disc = NSRect(
                x: (origin.x + slot.midX - diameter / 2).rounded(),
                y: (origin.y + slot.midY - diameter / 2).rounded(),
                width: diameter, height: diameter)
            NSBezierPath(ovalIn: disc).fill()
        }
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
            let glyphs = glyphRange(forCharacterRange: checkbox.range, actualCharacterRange: nil)
            guard glyphs.length > 0 else { continue }
            let slot = boundingRect(forGlyphRange: glyphs, in: container)
            let side = (min(slot.height, slot.width) - Self.checkboxMargin * 2).rounded()
            guard side > 4 else { continue }
            // Inset from the slot's leading edge as well: a list item's first line has no indent, so
            // the slot starts flush against the text container and a flush box loses its left edge.
            let box = NSRect(
                x: (origin.x + slot.minX + Self.checkboxMargin).rounded(),
                y: (origin.y + slot.midY - side / 2).rounded(),
                width: side, height: side)
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
