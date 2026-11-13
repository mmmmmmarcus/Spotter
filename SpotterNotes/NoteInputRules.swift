import Foundation

/// What the editor does with one edit the keyboard proposed.
enum NoteInputDecision: Equatable {
    case allow
    case reject
    /// Perform this replacement instead; the caret lands at its end.
    case replace(NSRange, String)
}

/// Everything the keyboard accessory bar and a hardware keyboard can ask of a Note.
enum NoteTouchCommand: Equatable {
    case inline(NoteMarkdownCommand)
    case block(NoteBlockFormat)
    case checklist
    case indent(NoteIndentDirection)
}

/// The touch editor's input rules, composed from `NoteEngine` exactly as the Mac editor composes them. Foundation-only and pure so `Tools/note-ios-test.swift` runs them without UIKit.
enum NoteInputRules {
    /// `evaluate` answers an arithmetic expression, or nil when it does not resolve.
    static func decision(
        replacing range: NSRange, with replacement: String, in text: String, selection: NSRange,
        concealedSuffixes: [NSRange] = [], evaluate: (String) -> String?
    ) -> NoteInputDecision {
        let source = text as NSString
        guard range.location >= 0, NSMaxRange(range) <= source.length else { return .allow }

        let titlePrefix = (NoteEngine.requiredTitlePrefix as NSString).length
        if range.location < titlePrefix, text.hasPrefix(NoteEngine.requiredTitlePrefix),
            !replacement.hasPrefix(NoteEngine.requiredTitlePrefix)
        {
            // The edit is moved past the protected `# ` rather than refused, so select-all-and-type still works.
            let editable = NSRange(
                location: titlePrefix, length: max(NSMaxRange(range), titlePrefix) - titlePrefix)
            let moved = decision(
                replacing: editable, with: replacement, in: text, selection: editable,
                concealedSuffixes: concealedSuffixes, evaluate: evaluate)
            guard moved == .allow else { return moved }
            return editable.length == 0 && replacement.isEmpty ? .reject : .replace(editable, replacement)
        }

        if replacement.isEmpty {
            // A backspace arrives as the one character before a bare caret.
            guard selection.length == 0, range.length == 1, NSMaxRange(range) == selection.location,
                let marker = NoteEngine.listMarkerDeletion(in: text, selection: selection)
            else { return .allow }
            return .replace(marker, "")
        }

        if (replacement as NSString).length > 1,
            let pasteRange = NoteEngine.listPasteReplacementRange(
                in: text, selection: range, inserting: replacement),
            pasteRange != range
        {
            return .replace(pasteRange, replacement)
        }

        guard range.length == 0 else { return .allow }
        let prefixRange = linePrefixRange(before: range.location, in: source)
        let prefix = source.substring(with: prefixRange)

        if let todo = NoteEngine.checklistInputRule(forLinePrefix: prefix, inserting: replacement) {
            return .replace(prefixRange, todo)
        }
        if range.location == NSMaxRange(lineContentRange(at: range.location, in: source)),
            let rule = NoteEngine.horizontalRuleCompletion(forLinePrefix: prefix, inserting: replacement)
        {
            return .replace(range, rule)
        }
        if replacement == "\n" {
            let firstLine = text.components(separatedBy: .newlines).first ?? ""
            // Return is refused until the title has text, so a Note cannot start with an empty heading.
            if range.location <= (firstLine as NSString).length, NoteEngine.leadingH1Title(in: text) == nil {
                return .reject
            }
            return newline(at: range.location, in: source, concealedSuffixes: concealedSuffixes)
        }
        if NoteEngine.isArithmeticEquals(replacement),
            NoteEngine.arithmeticCandidate(inLinePrefix: prefix) != nil
        {
            return .replace(range, replacement + answer(for: prefix, evaluate: evaluate))
        }
        return .allow
    }

    /// The rewrite that keeps an answered line answered after its formula was edited, or nil when nothing changes.
    static func arithmeticRefresh(
        in text: String, caret: NSRange, evaluate: (String) -> String?
    ) -> (range: NSRange, answer: String)? {
        let source = text as NSString
        guard caret.length == 0, caret.location <= source.length else { return nil }
        let line = lineContentRange(at: caret.location, in: source)
        guard let answered = NoteEngine.arithmeticAnswer(inLine: source.substring(with: line)) else {
            return nil
        }
        let resultRange = NSRange(
            location: line.location + answered.resultRange.location, length: answered.resultRange.length)
        // Left of the answer only: the answer itself is the user's to edit.
        guard caret.location < resultRange.location else { return nil }
        let display = answer(for: answered.expression, evaluate: evaluate)
        return display == answered.result ? nil : (resultRange, display)
    }

    /// Nil when the command leaves the Note exactly as it was.
    static func applying(
        _ command: NoteTouchCommand, to text: String, selection: NSRange
    ) -> NoteEditResult? {
        let source = text as NSString
        let location = min(max(0, selection.location), source.length)
        let length = min(max(0, selection.length), source.length - location)
        guard let selection = editableSelection(
            NSRange(location: location, length: length), for: command, in: source)
        else { return nil }

        let result: NoteEditResult
        switch command {
        case .inline(let inline):
            result = NoteEngine.applying(inline, to: text, selection: selection)
        case .indent(let direction):
            guard let indented = NoteEngine.applyingListIndent(direction, to: text, selection: selection)
            else { return nil }
            result = indented
        case .checklist:
            let written = touchedLines(in: source, selection: selection)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            // Stripped first, so a todo replaces a bullet or number instead of nesting inside it.
            let plain = NoteEngine.applyingBlockFormat(.text, to: text, selection: selection)
            let isToggleOff = !written.isEmpty && written.allSatisfy(isChecklistLine)
            result = keepingCaret(
                isToggleOff ? plain : NoteEngine.applying(.checklist, to: plain.text, selection: plain.selection),
                from: selection)
        case .block(let format):
            result = keepingCaret(applyingBlock(format, to: text, selection: selection), from: selection)
        }
        return result.text == text ? nil : result
    }

    /// The title line keeps its `# `: an inline command starts after the marker and a block command skips the line.
    private static func editableSelection(
        _ selection: NSRange, for command: NoteTouchCommand, in source: NSString
    ) -> NSRange? {
        let end = NSMaxRange(selection)
        if case .inline = command {
            let prefix = (NoteEngine.requiredTitlePrefix as NSString).length
            let start = min(max(selection.location, prefix), source.length)
            return NSRange(location: start, length: max(end, start) - start)
        }
        let titleEnd = NSMaxRange(lineContentRange(at: 0, in: source))
        guard selection.location <= titleEnd else { return selection }
        let body = NSMaxRange(source.lineRange(for: NSRange(location: 0, length: 0)))
        guard body > titleEnd, end > body else { return nil }
        return NSRange(location: body, length: end - body)
    }

    /// The smallest replacement that turns `old` into `new`, so applying a command does not relay out the whole Note.
    static func difference(from old: String, to new: String) -> (range: NSRange, replacement: String) {
        let before = old as NSString
        let after = new as NSString
        let limit = min(before.length, after.length)
        var prefix = 0
        while prefix < limit, before.character(at: prefix) == after.character(at: prefix) { prefix += 1 }
        var suffix = 0
        while suffix < limit - prefix,
            before.character(at: before.length - 1 - suffix) == after.character(at: after.length - 1 - suffix)
        {
            suffix += 1
        }
        // Never split a surrogate pair: an edit has to begin and end on whole characters.
        while prefix > 0, UTF16.isLeadSurrogate(before.character(at: prefix - 1)) { prefix -= 1 }
        while suffix > 0, UTF16.isTrailSurrogate(before.character(at: before.length - suffix)) { suffix -= 1 }
        return (
            NSRange(location: prefix, length: before.length - prefix - suffix),
            after.substring(with: NSRange(location: prefix, length: after.length - prefix - suffix))
        )
    }

    private static func applyingBlock(
        _ format: NoteBlockFormat, to text: String, selection: NSRange
    ) -> NoteEditResult {
        let source = text as NSString
        let lines = touchedLines(in: source, selection: selection)
        let written = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !written.isEmpty else {
            // The engine's block formats skip blank lines, but on touch a blank line is where a list or heading starts.
            let line = lineContentRange(at: selection.location, in: source)
            let marker = marker(for: format)
            guard selection.length == 0, !marker.isEmpty else {
                return NoteEditResult(text: text, selection: selection)
            }
            return NoteEditResult(
                text: source.replacingCharacters(
                    in: NSRange(location: NSMaxRange(line), length: 0), with: marker),
                selection: NSRange(location: NSMaxRange(line) + (marker as NSString).length, length: 0))
        }
        // Tapping the list a line already belongs to takes the marker off again.
        let isToggleOff =
            switch format {
            case .bulletedList: written.allSatisfy { isBulletLine($0) && !isChecklistLine($0) }
            case .numberedList: written.allSatisfy(isNumberedLine)
            default: false
            }
        return NoteEngine.applyingBlockFormat(isToggleOff ? .text : format, to: text, selection: selection)
    }

    private static func marker(for format: NoteBlockFormat) -> String {
        switch format {
        case .text: ""
        case .heading1: "# "
        case .heading2: "## "
        case .heading3: "### "
        case .bulletedList: "- "
        case .numberedList: "1. "
        }
    }

    /// A block command reshapes whole lines and the engine selects them all; a bare caret stays a caret, at the end of its line.
    private static func keepingCaret(_ result: NoteEditResult, from selection: NSRange) -> NoteEditResult {
        guard selection.length == 0, result.selection.length > 0 else { return result }
        let line = lineContentRange(at: result.selection.location, in: result.text as NSString)
        return NoteEditResult(
            text: result.text, selection: NSRange(location: NSMaxRange(line), length: 0))
    }

    private static func newline(
        at caret: Int, in source: NSString, concealedSuffixes: [NSRange]
    ) -> NoteInputDecision {
        // A Return at the visual end of a bold run sits before its hidden closing marker; step over it so the run stays whole.
        var escaped = caret
        while let suffix = concealedSuffixes.first(where: { $0.location == escaped }),
            NSMaxRange(suffix) <= source.length
        {
            escaped = NSMaxRange(suffix)
        }
        let content = lineContentRange(at: escaped, in: source)
        let prefix = source.substring(with: linePrefixRange(before: escaped, in: source))
        if let continuation = NoteEngine.listContinuation(after: source.substring(with: content)),
            NoteEngine.listContinuation(after: prefix) != nil
        {
            switch continuation {
            case .continueWith(let marker):
                return .replace(NSRange(location: escaped, length: 0), "\n" + marker)
            case .endList:
                return .replace(content, "")
            }
        }
        return escaped == caret ? .allow : .replace(NSRange(location: escaped, length: 0), "\n")
    }

    private static func answer(for prefix: String, evaluate: (String) -> String?) -> String {
        NoteEngine.arithmeticExpression(inLinePrefix: prefix).flatMap(evaluate)
            ?? NoteEngine.unresolvedArithmeticResult
    }

    private static func touchedLines(in source: NSString, selection: NSRange) -> [String] {
        var lines = source.substring(with: source.lineRange(for: selection)).components(separatedBy: "\n")
        if lines.count > 1, lines.last == "" { lines.removeLast() }
        return lines
    }

    private static func isChecklistLine(_ line: String) -> Bool {
        line.range(of: #"^[ \t]*[-*+] \[[ xX]\] "#, options: .regularExpression) != nil
    }

    private static func isBulletLine(_ line: String) -> Bool {
        line.range(of: #"^[ \t]*[-*+] "#, options: .regularExpression) != nil
    }

    private static func isNumberedLine(_ line: String) -> Bool {
        line.range(of: #"^[ \t]*\d+\. "#, options: .regularExpression) != nil
    }

    /// The line's text from its start up to `location`.
    private static func linePrefixRange(before location: Int, in source: NSString) -> NSRange {
        let line = source.lineRange(for: NSRange(location: location, length: 0))
        return NSRange(location: line.location, length: location - line.location)
    }

    /// The line `location` sits on, without its trailing break.
    private static func lineContentRange(at location: Int, in source: NSString) -> NSRange {
        var range = source.lineRange(for: NSRange(location: location, length: 0))
        if range.length > 0, source.substring(with: range).hasSuffix("\n") { range.length -= 1 }
        return range
    }
}
