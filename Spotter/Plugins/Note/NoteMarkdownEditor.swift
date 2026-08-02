import AppKit
import SwiftUI

struct NoteEditRequest: Identifiable {
    let id = UUID()
    let command: NoteMarkdownCommand
}

struct NoteMarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    let request: NoteEditRequest?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        let textView = NSTextView()
        textView.delegate = context.coordinator
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
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }
        if textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
            context.coordinator.highlight()
        }
        if let request, request.id != context.coordinator.lastRequestID {
            context.coordinator.lastRequestID = request.id
            context.coordinator.apply(request.command)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteMarkdownEditor
        weak var textView: NSTextView?
        var lastRequestID: UUID?
        private var highlightWork: DispatchWorkItem?

        init(parent: NoteMarkdownEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
            scheduleHighlight()
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
            let length = (textView.string as NSString).length
            let wholeDocument = NSRange(location: 0, length: length)
            for key in [NSAttributedString.Key.font, .underlineStyle, .strikethroughStyle] {
                layout.removeTemporaryAttribute(key, forCharacterRange: wholeDocument)
            }
            guard length > 0, length <= 200_000 else { return }

            let bodyFont = NSFont.preferredFont(forTextStyle: .body)
            apply(Self.bold, to: textView.string, layout: layout) { match in
                guard let range = self.firstCapture(in: match) else { return nil }
                return (.font, NSFontManager.shared.convert(bodyFont, toHaveTrait: .boldFontMask), range)
            }
            apply(Self.italic, to: textView.string, layout: layout) { match in
                guard let range = self.firstCapture(in: match) else { return nil }
                return (.font, NSFontManager.shared.convert(bodyFont, toHaveTrait: .italicFontMask), range)
            }
            apply(Self.inlineCode, to: textView.string, layout: layout) { match in
                guard match.numberOfRanges > 1 else { return nil }
                return (.font, NSFont.monospacedSystemFont(ofSize: bodyFont.pointSize, weight: .regular), match.range(at: 1))
            }
            apply(Self.link, to: textView.string, layout: layout) { match in
                guard match.numberOfRanges > 1 else { return nil }
                return (.underlineStyle, NSUnderlineStyle.single.rawValue, match.range(at: 1))
            }
            apply(Self.completedTask, to: textView.string, layout: layout) { match in
                guard match.numberOfRanges > 1 else { return nil }
                return (.strikethroughStyle, NSUnderlineStyle.single.rawValue, match.range(at: 1))
            }
            Self.heading.enumerateMatches(
                in: textView.string, range: wholeDocument
            ) { match, _, _ in
                guard let match else { return }
                let marker = (textView.string as NSString).substring(with: match.range(at: 1))
                let style: NSFont.TextStyle = marker.count == 1 ? .title1 : marker.count == 2 ? .title2 : .title3
                layout.addTemporaryAttribute(
                    .font, value: NSFont.preferredFont(forTextStyle: style),
                    forCharacterRange: match.range)
            }
        }

        private func scheduleHighlight() {
            highlightWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.highlight() }
            highlightWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: work)
        }

        private func apply(
            _ expression: NSRegularExpression, to text: String, layout: NSLayoutManager,
            attribute: (NSTextCheckingResult) -> (NSAttributedString.Key, Any, NSRange)?
        ) {
            let range = NSRange(location: 0, length: (text as NSString).length)
            expression.enumerateMatches(in: text, range: range) { match, _, _ in
                guard let match, let (key, value, target) = attribute(match) else { return }
                layout.addTemporaryAttribute(key, value: value, forCharacterRange: target)
            }
        }

        private func firstCapture(in match: NSTextCheckingResult) -> NSRange? {
            for index in 1..<match.numberOfRanges {
                let range = match.range(at: index)
                if range.location != NSNotFound { return range }
            }
            return nil
        }

        private static let bold = try! NSRegularExpression(pattern: #"\*\*([^\n*]+)\*\*|__([^\n_]+)__"#)
        private static let italic = try! NSRegularExpression(pattern: #"(?<!\*)\*([^\n*]+)\*(?!\*)|(?<!_)_([^\n_]+)_(?!_)"#)
        private static let inlineCode = try! NSRegularExpression(pattern: #"`([^\n`]+)`"#)
        private static let link = try! NSRegularExpression(pattern: #"\[([^\]]+)\]\([^\)]+\)"#)
        private static let completedTask = try! NSRegularExpression(pattern: #"(?m)^\s*- \[[xX]\]\s+(.+)$"#)
        private static let heading = try! NSRegularExpression(pattern: #"(?m)^(#{1,6})\s+.+$"#)
    }
}
