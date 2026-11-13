import UIKit

/// The one cell every list marker occupies, so a Note mixing todos, bullets and numbers keeps a single content edge. Kerning and paragraph style are attributes, never characters.
@MainActor
private enum NoteListMarker {
    /// Breathing room between the widest decoration and the text after it.
    private static let minimumGap: CGFloat = 4

    /// The square both the todo box and the bullet disc are laid out in.
    static var decorationSide: CGFloat { NotesTheme.Fonts.body.pointSize.rounded() }

    /// Wide enough for a one-digit ordered marker in its monospaced font, never narrower than a decoration and its gap.
    static var baseSlot: CGFloat {
        max(decorationSide + minimumGap, width(of: "1.", in: NotesTheme.Fonts.monospaced) + minimumGap)
    }

    static let indentUnit = NotesTheme.Spacing.xxl

    /// A nesting level is the same step whether it was written as spaces or as a legacy tab.
    static func indentationWidth(_ indentation: String) -> CGFloat {
        let spaces = indentation.filter { $0 == " " }.count
        let tabs = indentation.count - spaces
        return CGFloat(spaces) / CGFloat(NoteEngine.listIndentUnit.count) * indentUnit
            + CGFloat(tabs) * indentUnit
    }

    static func width(of text: String, in font: UIFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }
}

/// Styles a Note's Markdown in place. Everything lives in the text storage's attributes, so the string — and therefore everything persisted — stays exactly what was typed.
@MainActor
final class NoteEditorStyler {
    /// Closing markers the last pass collapsed, so Return can step the caret out of one.
    private(set) var concealedSuffixes: [NSRange] = []
    private var codeRanges: [NSRange] = []
    private var headings: [(range: NSRange, font: UIFont)] = []

    static var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: NotesTheme.Fonts.body, .foregroundColor: UIColor.label]
    }

    /// What typing at this selection inherits: a heading's font inside a heading, the plain slate elsewhere — never the hidden syntax beside the caret.
    func typingAttributes(for selection: NSRange) -> [NSAttributedString.Key: Any] {
        var attributes = Self.baseAttributes
        if selection.length == 0,
            let heading = headings.first(where: {
                selection.location >= $0.range.location && selection.location <= NSMaxRange($0.range)
            })
        {
            attributes[.font] = heading.font
        }
        return attributes
    }

    func style(_ storage: NSTextStorage, layout: NoteLayoutManager) {
        let text = storage.string
        let source = text as NSString
        let wholeDocument = NSRange(location: 0, length: source.length)
        layout.decorations = []
        layout.checkboxes = []
        layout.bullets = []
        concealedSuffixes = []
        headings = []
        codeRanges = []

        storage.beginEditing()
        defer { storage.endEditing() }
        storage.setAttributes(Self.baseAttributes, range: wholeDocument)
        guard source.length > 0, source.length <= 200_000 else { return }

        let spans = NoteEngine.blockSpans(in: text)
        codeRanges = spans.filter { $0.kind == .codeBlock }.map(\.range)
        applyBlocks(spans, storage: storage, layout: layout)

        apply(Self.bold, to: text) { match in
            guard let range = self.firstCapture(in: match) else { return }
            storage.addAttribute(.font, value: NotesTheme.Fonts.body(.traitBold), range: range)
            self.concealSyntax(around: range, in: match.range, storage: storage)
        }
        apply(Self.strikethrough, to: text) { match in
            guard let range = self.firstCapture(in: match) else { return }
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            self.concealSyntax(around: range, in: match.range, storage: storage)
        }
        apply(Self.italic, to: text) { match in
            guard let range = self.firstCapture(in: match) else { return }
            storage.addAttribute(.font, value: NotesTheme.Fonts.body(.traitItalic), range: range)
            self.concealSyntax(around: range, in: match.range, storage: storage)
        }
        apply(Self.inlineCode, to: text) { match in
            guard match.numberOfRanges > 1 else { return }
            storage.addAttribute(.font, value: NotesTheme.Fonts.monospaced, range: match.range(at: 1))
            self.concealSyntax(around: match.range(at: 1), in: match.range, storage: storage)
        }
        apply(Self.link, to: text) { match in
            guard match.numberOfRanges > 1 else { return }
            storage.addAttribute(
                .underlineStyle, value: NSUnderlineStyle.single.rawValue, range: match.range(at: 1))
            self.concealSyntax(around: match.range(at: 1), in: match.range, storage: storage)
        }

        let slot = applyOrderedMarkers(in: text, storage: storage)
        applyBullets(in: text, storage: storage, layout: layout, slot: slot)
        applyCheckboxes(in: text, storage: storage, layout: layout, slot: slot)
        apply(Self.completedTask, to: text) { match in
            guard match.numberOfRanges > 1 else { return }
            storage.addAttribute(
                .strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: match.range(at: 1))
            storage.addAttribute(.foregroundColor, value: UIColor.tertiaryLabel, range: match.range(at: 1))
        }
        apply(Self.heading, to: text) { match in
            guard match.numberOfRanges > 2 else { return }
            let font = NotesTheme.Fonts.heading(level: match.range(at: 1).length)
            storage.addAttribute(.font, value: font, range: match.range)
            self.headings.append((match.range, font))
            let prefix = NSRange(
                location: match.range.location, length: match.range(at: 2).location - match.range.location)
            // Cleared and squeezed rather than shrunk, so an empty heading keeps its line height and caret.
            storage.addAttribute(.foregroundColor, value: UIColor.clear, range: prefix)
            for index in prefix.location..<NSMaxRange(prefix) {
                self.stretch(NSRange(location: index, length: 1), to: 0, in: storage)
            }
        }
        apply(Self.listLine, to: text) { match in
            guard match.numberOfRanges > 1 else { return }
            let indentation = match.range(at: 1)
            for index in indentation.location..<NSMaxRange(indentation)
            where source.character(at: index) == 32 {
                self.stretch(
                    NSRange(location: index, length: 1),
                    to: NoteListMarker.indentUnit / CGFloat(NoteEngine.listIndentUnit.count), in: storage)
            }
            let style = NSMutableParagraphStyle()
            // Every marker was kerned to the same cell, so a wrapped line hangs at the one content edge.
            style.headIndent =
                NoteListMarker.indentationWidth(source.substring(with: indentation)) + slot
            style.tabStops = []
            style.defaultTabInterval = NoteListMarker.indentUnit
            storage.addAttribute(.paragraphStyle, value: style, range: match.range)
        }
    }

    /// Kerns a marker's last character so the whole marker advances exactly one cell.
    private func fit(_ marker: NSRange, to slot: CGFloat, in storage: NSTextStorage) {
        guard marker.length > 0 else { return }
        let last = NSRange(location: NSMaxRange(marker) - 1, length: 1)
        let existing = storage.attribute(.kern, at: last.location, effectiveRange: nil) as? NSNumber
        let kern = existing.map { CGFloat($0.doubleValue) } ?? 0
        storage.addAttribute(.kern, value: kern + slot - width(of: marker, in: storage), range: last)
    }

    /// Gives one character an exact advance, so the square drawn over it is the same on every kind of list line.
    private func stretch(_ character: NSRange, to advance: CGFloat, in storage: NSTextStorage) {
        let font =
            storage.attribute(.font, at: character.location, effectiveRange: nil) as? UIFont
            ?? NotesTheme.Fonts.body
        let glyph = (storage.string as NSString).substring(with: character)
        storage.addAttribute(
            .kern, value: advance - NoteListMarker.width(of: glyph, in: font), range: character)
    }

    /// A range's rendered advance: every run in its own font, plus the kerning already on it.
    private func width(of range: NSRange, in storage: NSTextStorage) -> CGFloat {
        let source = storage.string as NSString
        var total: CGFloat = 0
        storage.enumerateAttributes(in: range, options: []) { attributes, run, _ in
            let font = attributes[.font] as? UIFont ?? NotesTheme.Fonts.body
            let kern = (attributes[.kern] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 0
            total += NoteListMarker.width(of: source.substring(with: run), in: font) + kern * CGFloat(run.length)
        }
        return total
    }

    /// Ordered markers are monospaced so `9.` and `10.` align; returns the cell every marker is fitted to, since only they can outgrow it.
    private func applyOrderedMarkers(in text: String, storage: NSTextStorage) -> CGFloat {
        let source = text as NSString
        let monospaced = NotesTheme.Fonts.monospaced
        var slot = NoteListMarker.baseSlot
        var markers: [NSRange] = []
        apply(Self.orderedMarker, to: text) { match in
            guard match.numberOfRanges > 2 else { return }
            let marker = match.range(at: 2)
            storage.addAttribute(.font, value: monospaced, range: marker)
            markers.append(marker)
            slot = max(
                slot,
                NoteListMarker.width(of: String(source.substring(with: marker).dropLast()), in: monospaced)
                    + NotesTheme.Spacing.xs)
        }
        for marker in markers { fit(marker, to: slot, in: storage) }
        return slot
    }

    /// The dash is cleared and widened to the decoration square; the layout manager draws a disc in it.
    private func applyBullets(
        in text: String, storage: NSTextStorage, layout: NoteLayoutManager, slot: CGFloat
    ) {
        apply(Self.bulletMarker, to: text) { match in
            guard match.numberOfRanges > 2 else { return }
            let dash = match.range(at: 2)
            storage.addAttribute(.foregroundColor, value: UIColor.clear, range: dash)
            self.stretch(dash, to: NoteListMarker.decorationSide, in: storage)
            self.fit(
                NSRange(location: dash.location, length: NSMaxRange(match.range) - dash.location),
                to: slot, in: storage)
            layout.bullets.append(dash)
        }
    }

    /// The task marker collapses into a box that stays visible because it is a control, not decoration.
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
            storage.addAttribute(.foregroundColor, value: UIColor.clear, range: state)
            self.stretch(state, to: NoteListMarker.decorationSide, in: storage)
            self.fit(
                NSRange(location: opening.location, length: NSMaxRange(match.range) - opening.location),
                to: slot, in: storage)
            layout.checkboxes.append(NoteLayoutManager.Checkbox(range: state, isDone: isDone))
        }
    }

    private func applyBlocks(
        _ spans: [NoteBlockSpan], storage: NSTextStorage, layout: NoteLayoutManager
    ) {
        for span in spans {
            switch span.kind {
            case .codeBlock:
                storage.addAttribute(.font, value: NotesTheme.Fonts.monospaced, range: span.range)
                storage.addAttribute(
                    .paragraphStyle, value: Self.indented(by: NotesTheme.Spacing.lg), range: span.range)
                layout.decorations.append(.codeBlock(span.range))
            case .codeFence:
                storage.addAttribute(.foregroundColor, value: UIColor.tertiaryLabel, range: span.range)
            case .quote:
                storage.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: span.range)
                storage.addAttribute(
                    .paragraphStyle, value: Self.indented(by: NotesTheme.Spacing.xl), range: span.range)
                layout.decorations.append(.quoteBar(span.range))
                let body = NSRange(
                    location: NSMaxRange(span.markerRange),
                    length: NSMaxRange(span.range) - NSMaxRange(span.markerRange))
                concealSyntax(around: body, in: span.range, storage: storage)
            case .rule:
                layout.decorations.append(.rule(span.range))
                storage.addAttribute(.foregroundColor, value: UIColor.clear, range: span.range)
            case .tableRow:
                storage.addAttribute(.font, value: NotesTheme.Fonts.monospaced, range: span.range)
            }
        }
    }

    private static func indented(by amount: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = amount
        style.headIndent = amount
        return style
    }

    private func apply(
        _ expression: NSRegularExpression, to text: String, action: (NSTextCheckingResult) -> Void
    ) {
        let range = NSRange(location: 0, length: (text as NSString).length)
        expression.enumerateMatches(in: text, range: range) { match, _, _ in
            // Inside a fence the markers are the content: a `# ` there is a comment, not a heading.
            guard let match, !codeRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 })
            else { return }
            action(match)
        }
    }

    private func concealSyntax(around content: NSRange, in fullRange: NSRange, storage: NSTextStorage) {
        let prefix = NSRange(
            location: fullRange.location, length: content.location - fullRange.location)
        let suffix = NSRange(
            location: NSMaxRange(content), length: NSMaxRange(fullRange) - NSMaxRange(content))
        if suffix.length > 0 { concealedSuffixes.append(suffix) }
        for range in [prefix, suffix] { hide(range, in: storage) }
    }

    /// Collapses a range to nothing: no width, no ink.
    private func hide(_ range: NSRange, in storage: NSTextStorage) {
        guard range.length > 0 else { return }
        storage.addAttribute(.font, value: NotesTheme.Fonts.concealed, range: range)
        storage.addAttribute(.foregroundColor, value: UIColor.clear, range: range)
    }

    private func firstCapture(in match: NSTextCheckingResult) -> NSRange? {
        for index in 1..<match.numberOfRanges {
            let range = match.range(at: index)
            if range.location != NSNotFound { return range }
        }
        return nil
    }

    private static let bold = try! NSRegularExpression(pattern: #"\*\*([^\n*]+)\*\*|__([^\n_]+)__"#)
    private static let italic = try! NSRegularExpression(
        pattern: #"(?<!\*)\*([^\n*]+)\*(?!\*)|(?<!_)_([^\n_]+)_(?!_)"#)
    private static let strikethrough = try! NSRegularExpression(pattern: #"~~([^\n~]+)~~"#)
    // Captures the syntax to collapse either side of the state character the box is drawn over.
    private static let taskMarker = try! NSRegularExpression(
        pattern: #"(?m)^[ \t]*([-*+] \[)([ xX])(\] )"#)
    private static let inlineCode = try! NSRegularExpression(pattern: #"`([^\n`]+)`"#)
    private static let link = try! NSRegularExpression(pattern: #"\[([^\]]+)\]\([^\)]+\)"#)
    private static let completedTask = try! NSRegularExpression(
        pattern: #"(?m)^[ \t]*[-*+] \[[xX]\][ \t]+(.+)$"#)
    // The body may be empty so a heading takes effect the moment its marker and space are typed.
    private static let heading = try! NSRegularExpression(pattern: #"(?m)^(#{1,6})[ \t]+(.*)$"#)
    // A dash that opens a todo belongs to the checkbox, not to a bullet.
    private static let bulletMarker = try! NSRegularExpression(
        pattern: #"(?m)^([ \t]*)([-*+]) (?!\[[ xX]\] )"#)
    private static let orderedMarker = try! NSRegularExpression(pattern: #"(?m)^([ \t]*)(\d+\. )"#)
    private static let listLine = try! NSRegularExpression(
        pattern: #"(?m)^([ \t]*)([-*+] \[[ xX]\] |[-*+] |\d+\. ).*$"#)
}
