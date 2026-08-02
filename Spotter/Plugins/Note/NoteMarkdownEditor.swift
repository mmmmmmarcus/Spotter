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
    let onContentHeightChange: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        let textView = NoteTextView()
        textView.markdownCommandHandler = { [weak coordinator = context.coordinator] command in
            coordinator?.apply(command)
        }
        textView.delegate = context.coordinator
        textView.layoutManager?.delegate = context.coordinator
        textView.string = text
        textView.drawsBackground = false
        textView.textColor = .white
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
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0, height: CGFloat.greatestFiniteMagnitude)
        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.highlight()

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
            context.coordinator.reportContentHeight()
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }
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
    final class Coordinator: NSObject, NSTextViewDelegate, @preconcurrency NSLayoutManagerDelegate {
        var parent: NoteMarkdownEditor
        weak var textView: NSTextView?
        private var highlightWork: DispatchWorkItem?
        private var isApplyingListEdit = false
        private var lastReportedHeight: CGFloat = 0

        init(parent: NoteMarkdownEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
            scheduleHighlight()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            scheduleHighlight()
        }

        func textView(
            _ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard !isApplyingListEdit, replacementString == "\n", affectedCharRange.length == 0
            else { return true }
            let source = textView.string as NSString
            let lineRange = source.lineRange(
                for: NSRange(location: affectedCharRange.location, length: 0))
            var contentRange = lineRange
            if contentRange.length > 0,
                source.substring(with: contentRange).hasSuffix("\n")
            {
                contentRange.length -= 1
            }
            guard affectedCharRange.location == NSMaxRange(contentRange),
                let continuation = NoteEngine.listContinuation(
                    after: source.substring(with: contentRange))
            else { return true }

            let replacementRange: NSRange
            let replacement: String
            switch continuation {
            case .continueWith(let prefix):
                replacementRange = affectedCharRange
                replacement = "\n" + prefix
            case .endList:
                replacementRange = contentRange
                replacement = ""
            }

            isApplyingListEdit = true
            textView.insertText(replacement, replacementRange: replacementRange)
            isApplyingListEdit = false
            return false
        }

        func apply(_ command: NoteMarkdownCommand) {
            guard let textView else { return }
            let result = NoteEngine.applying(
                command, to: textView.string, selection: textView.selectedRange())
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

        func highlight() {
            guard let textView, let layout = textView.layoutManager else { return }
            let source = textView.string as NSString
            let wholeDocument = NSRange(location: 0, length: source.length)
            for key in [
                NSAttributedString.Key.font, .foregroundColor, .paragraphStyle, .underlineStyle,
                .strikethroughStyle,
            ] {
                layout.removeTemporaryAttribute(key, forCharacterRange: wholeDocument)
            }
            guard source.length > 0, source.length <= 200_000 else {
                reportContentHeight()
                return
            }

            let bodyFont = NSFont.preferredFont(forTextStyle: .body)
            let firstLine = source.lineRange(for: NSRange(location: 0, length: 0))
            let firstLineText = source.substring(with: firstLine)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !firstLineText.isEmpty {
                layout.addTemporaryAttribute(
                    .font, value: NSFont.preferredFont(forTextStyle: .title2),
                    forCharacterRange: firstLine)
            }

            apply(Self.bold, to: textView.string, layout: layout) { match in
                guard let range = self.firstCapture(in: match) else { return }
                layout.addTemporaryAttribute(
                    .font,
                    value: NSFontManager.shared.convert(bodyFont, toHaveTrait: .boldFontMask),
                    forCharacterRange: range)
                self.concealSyntax(around: range, in: match.range, layout: layout)
            }
            apply(Self.italic, to: textView.string, layout: layout) { match in
                guard let range = self.firstCapture(in: match) else { return }
                layout.addTemporaryAttribute(
                    .font,
                    value: NSFontManager.shared.convert(bodyFont, toHaveTrait: .italicFontMask),
                    forCharacterRange: range)
                self.concealSyntax(around: range, in: match.range, layout: layout)
            }
            apply(Self.inlineCode, to: textView.string, layout: layout) { match in
                guard match.numberOfRanges > 1 else { return }
                let range = match.range(at: 1)
                layout.addTemporaryAttribute(
                    .font,
                    value: NSFont.monospacedSystemFont(
                        ofSize: bodyFont.pointSize, weight: .regular),
                    forCharacterRange: range)
                self.concealSyntax(around: range, in: match.range, layout: layout)
            }
            apply(Self.link, to: textView.string, layout: layout) { match in
                guard match.numberOfRanges > 1 else { return }
                let range = match.range(at: 1)
                layout.addTemporaryAttribute(
                    .underlineStyle, value: NSUnderlineStyle.single.rawValue,
                    forCharacterRange: range)
                self.concealSyntax(around: range, in: match.range, layout: layout)
            }
            apply(Self.completedTask, to: textView.string, layout: layout) { match in
                guard match.numberOfRanges > 1 else { return }
                layout.addTemporaryAttribute(
                    .strikethroughStyle, value: NSUnderlineStyle.single.rawValue,
                    forCharacterRange: match.range(at: 1))
            }
            apply(Self.heading, to: textView.string, layout: layout) { match in
                guard match.numberOfRanges > 2 else { return }
                let marker = source.substring(with: match.range(at: 1))
                let style: NSFont.TextStyle =
                    marker.count == 1 ? .title1 : marker.count == 2 ? .title2 : .title3
                layout.addTemporaryAttribute(
                    .font, value: NSFont.preferredFont(forTextStyle: style),
                    forCharacterRange: match.range)
                self.concealSyntax(
                    around: match.range(at: 2), in: match.range, layout: layout)
            }
            apply(Self.listLine, to: textView.string, layout: layout) { match in
                let style = NSMutableParagraphStyle()
                style.headIndent = Theme.Spacing.xxl
                style.firstLineHeadIndent = 0
                layout.addTemporaryAttribute(
                    .paragraphStyle, value: style, forCharacterRange: match.range)
            }
            reportContentHeight()
        }

        func reportContentHeight() {
            guard let textView, let layout = textView.layoutManager,
                let container = textView.textContainer
            else { return }
            layout.ensureLayout(for: container)
            let usedHeight = max(
                layout.usedRect(for: container).height,
                NoteEditorMetrics.minimumEditorHeight - Theme.Spacing.xxl * 2)
            let height = min(
                max(usedHeight + Theme.Spacing.xxl * 2, NoteEditorMetrics.minimumEditorHeight),
                NoteEditorMetrics.maximumEditorHeight)
            guard abs(lastReportedHeight - height) > 0.5 else { return }
            lastReportedHeight = height
            DispatchQueue.main.async { [weak self] in
                self?.parent.onContentHeightChange(height)
            }
        }

        func layoutManager(
            _ layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
            properties: UnsafePointer<NSLayoutManager.GlyphProperty>,
            characterIndexes: UnsafePointer<Int>, font: NSFont, forGlyphRange glyphRange: NSRange
        ) -> Int {
            guard let source = layoutManager.textStorage?.string as NSString? else { return 0 }
            var generated = Array(UnsafeBufferPointer(start: glyphs, count: glyphRange.length))
            let generatedProperties = Array(
                UnsafeBufferPointer(start: properties, count: glyphRange.length))
            let generatedIndexes = Array(
                UnsafeBufferPointer(start: characterIndexes, count: glyphRange.length))
            let bullet = CGGlyph(font.glyph(withName: "bullet"))
            if bullet != 0 {
                for offset in generated.indices
                where Self.isBulletMarker(at: generatedIndexes[offset], in: source) {
                    generated[offset] = bullet
                }
            }
            generated.withUnsafeBufferPointer { glyphBuffer in
                generatedProperties.withUnsafeBufferPointer { propertyBuffer in
                    generatedIndexes.withUnsafeBufferPointer { indexBuffer in
                        layoutManager.setGlyphs(
                            glyphBuffer.baseAddress!, properties: propertyBuffer.baseAddress!,
                            characterIndexes: indexBuffer.baseAddress!, font: font,
                            forGlyphRange: glyphRange)
                    }
                }
            }
            return glyphRange.length
        }

        private func scheduleHighlight() {
            highlightWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.highlight() }
            highlightWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: work)
        }

        private func apply(
            _ expression: NSRegularExpression, to text: String, layout: NSLayoutManager,
            action: (NSTextCheckingResult) -> Void
        ) {
            let range = NSRange(location: 0, length: (text as NSString).length)
            expression.enumerateMatches(in: text, range: range) { match, _, _ in
                if let match { action(match) }
            }
        }

        private func concealSyntax(
            around content: NSRange, in fullRange: NSRange, layout: NSLayoutManager
        ) {
            guard let textView, !selectionTouches(fullRange, in: textView) else { return }
            let hiddenFont = NSFont.systemFont(ofSize: 0.1)
            let prefix = NSRange(
                location: fullRange.location, length: content.location - fullRange.location)
            let suffix = NSRange(
                location: NSMaxRange(content), length: NSMaxRange(fullRange) - NSMaxRange(content))
            for range in [prefix, suffix] where range.length > 0 {
                layout.addTemporaryAttribute(.font, value: hiddenFont, forCharacterRange: range)
                layout.addTemporaryAttribute(
                    .foregroundColor, value: NSColor.clear, forCharacterRange: range)
            }
        }

        private func selectionTouches(_ range: NSRange, in textView: NSTextView) -> Bool {
            let selection = textView.selectedRange()
            if selection.length == 0 {
                return selection.location >= range.location && selection.location <= NSMaxRange(range)
            }
            return NSIntersectionRange(selection, range).length > 0
        }

        private func firstCapture(in match: NSTextCheckingResult) -> NSRange? {
            for index in 1..<match.numberOfRanges {
                let range = match.range(at: index)
                if range.location != NSNotFound { return range }
            }
            return nil
        }

        private static func isBulletMarker(at characterIndex: Int, in source: NSString) -> Bool {
            guard characterIndex >= 0, characterIndex + 1 < source.length else { return false }
            let marker = source.character(at: characterIndex)
            guard marker == 0x2D || marker == 0x2A || marker == 0x2B,
                source.character(at: characterIndex + 1) == 0x20
            else { return false }
            if characterIndex + 2 < source.length, source.character(at: characterIndex + 2) == 0x5B {
                return false
            }
            let line = source.lineRange(for: NSRange(location: characterIndex, length: 0))
            let prefix = source.substring(
                with: NSRange(location: line.location, length: characterIndex - line.location))
            return prefix.trimmingCharacters(in: .whitespaces).isEmpty
        }

        private static let bold = try! NSRegularExpression(
            pattern: #"\*\*([^\n*]+)\*\*|__([^\n_]+)__"#)
        private static let italic = try! NSRegularExpression(
            pattern: #"(?<!\*)\*([^\n*]+)\*(?!\*)|(?<!_)_([^\n_]+)_(?!_)"#)
        private static let inlineCode = try! NSRegularExpression(pattern: #"`([^\n`]+)`"#)
        private static let link = try! NSRegularExpression(pattern: #"\[([^\]]+)\]\([^\)]+\)"#)
        private static let completedTask = try! NSRegularExpression(
            pattern: #"(?m)^\s*- \[[xX]\]\s+(.+)$"#)
        private static let heading = try! NSRegularExpression(
            pattern: #"(?m)^(#{1,6})\s+(.+)$"#)
        private static let listLine = try! NSRegularExpression(
            pattern: #"(?m)^\s*(?:[-*+] |\d+\. |- \[[ xX]\] ).+$"#)
    }
}

@MainActor
private final class NoteTextView: NSTextView {
    var markdownCommandHandler: ((NoteMarkdownCommand) -> Void)?

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
        default:
            return super.performKeyEquivalent(with: event)
        }
        return true
    }
}
