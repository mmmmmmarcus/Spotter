import Foundation

struct SpotterNote: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var content: String
    let createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), content: String = "", createdAt: Date = Date(), updatedAt: Date? = nil) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    var title: String { NoteEngine.title(in: content) }
    var excerpt: String { NoteEngine.excerpt(in: content) }
}

enum NoteMarkdownCommand: Sendable {
    case bold
    case italic
    case strikethrough
    case inlineCode
    case link
    case heading
    case bulletedList
    case numberedList
    case checklist
}

enum NoteBlockFormat: Equatable, Sendable {
    case text
    case heading1
    case heading2
    case heading3
    case bulletedList
    case numberedList
}

enum NoteListContinuation: Equatable, Sendable {
    case continueWith(String)
    case endList
}

enum NoteNavigationDirection: Equatable, Sendable {
    case previous
    case next
}

struct NoteEditResult: Equatable, Sendable {
    let text: String
    let selection: NSRange
}

/// A block-level Markdown construct the editor styles in place. Inline spans stay with the editor's
/// own expressions; only these need a line-by-line scan to be found.
enum NoteBlockKind: Equatable, Sendable {
    /// A whole fenced block, both fence lines included — the range the code panel is drawn behind.
    case codeBlock
    /// One ``` or ~~~ line, dimmed inside its own block.
    case codeFence
    case quote
    case rule
    case tableRow
}

struct NoteBlockSpan: Equatable, Sendable {
    let kind: NoteBlockKind
    /// UTF-16, and never includes the line break — a background drawn over one runs to the next line.
    let range: NSRange
    /// Leading syntax the editor hides behind the rendered block; empty when there is none.
    let markerRange: NSRange

    init(kind: NoteBlockKind, range: NSRange, markerRange: NSRange = NSRange(location: 0, length: 0)) {
        self.kind = kind
        self.range = range
        self.markerRange = markerRange
    }
}

enum NoteEngine {
    static func title(in markdown: String) -> String {
        let firstLine = markdown.components(separatedBy: .newlines).first ?? ""
        let cleaned = stripMarkup(firstLine)
        return cleaned.isEmpty ? "Untitled Note" : String(cleaned.prefix(80))
    }

    static func editorLineCount(in markdown: String, minimum: Int = 3, maximum: Int = 20) -> Int {
        let logicalLines = markdown.reduce(into: 1) { count, character in
            if character == "\n" { count += 1 }
        }
        return min(max(logicalLines, minimum), maximum)
    }

    static func listContinuation(after line: String) -> NoteListContinuation? {
        let indentation = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
        let body = String(line.dropFirst(indentation.count))

        for marker in ["- [ ] ", "- [x] ", "- [X] "] where body.hasPrefix(marker) {
            let content = body.dropFirst(marker.count)
            return content.trimmingCharacters(in: .whitespaces).isEmpty
                ? .endList : .continueWith(indentation + "- [ ] ")
        }

        for marker in ["- ", "* ", "+ "] where body.hasPrefix(marker) {
            let content = body.dropFirst(marker.count)
            return content.trimmingCharacters(in: .whitespaces).isEmpty
                ? .endList : .continueWith(indentation + marker)
        }

        let digits = body.prefix(while: { $0.isNumber })
        guard !digits.isEmpty, body.dropFirst(digits.count).hasPrefix(". "),
            let number = Int(digits)
        else { return nil }
        let content = body.dropFirst(digits.count + 2)
        return content.trimmingCharacters(in: .whitespaces).isEmpty
            ? .endList : .continueWith(indentation + "\(number + 1). ")
    }

    static func excerpt(in markdown: String) -> String {
        let meaningful = markdown.components(separatedBy: .newlines)
            .map(stripMarkup)
            .filter { !$0.isEmpty }
        guard !meaningful.isEmpty else { return "No additional text" }
        let body = meaningful.dropFirst().prefix(2).joined(separator: " ")
        return body.isEmpty ? "No additional text" : String(body.prefix(120))
    }

    /// Turns completed ASCII or Chinese brackets into the Markdown source for a visual checkbox.
    static func checklistInputRule(
        forLinePrefix prefix: String, inserting typedText: String = " "
    ) -> String? {
        let indentation = String(prefix.prefix(while: { $0 == " " || $0 == "\t" }))
        var body = Substring(prefix.dropFirst(indentation.count))
        if let marker = ["- ", "* ", "+ "].first(where: { body.hasPrefix($0) }) {
            body = body.dropFirst(marker.count)
        }
        let completed = String(body) + typedText
        guard completed == "[] " || completed == "【】 " || completed == "【 】"
            || completed == "【　】"
        else { return nil }
        return indentation + "- [ ] "
    }

    /// The arithmetic sitting immediately before a typed `=`, or nil when the line does not end in
    /// one. Only the substring is found here — evaluating it is the editor's job, so this stays pure
    /// and `Core/Calculator` keeps its single owner.
    static func arithmeticExpression(inLinePrefix prefix: String) -> String? {
        var line = Substring(prefix)
        while line.last == " " || line.last == "\t" { line = line.dropLast() }
        guard let last = line.last, last.isNumber || last == ")" || last == "%" else { return nil }

        var start = line.endIndex
        while start > line.startIndex, Self.arithmeticCharacters.contains(line[line.index(before: start)]) {
            start = line.index(before: start)
        }
        // Whitespace is inside the set so `1 + 2` scans as one expression; step back over whatever it
        // swallowed at the front before judging what precedes the sum.
        while start < line.endIndex, line[start] == " " || line[start] == "\t" {
            start = line.index(after: start)
        }
        // Anything glued to a word ("rev2+3") is an identifier, not a sum the user wants evaluated.
        if start > line.startIndex {
            let preceding = line[line.index(before: start)]
            guard preceding == " " || preceding == "\t" else { return nil }
        }

        var body = line[start...]
        // The operator set contains the list markers, so a bulleted or numbered line would otherwise
        // swallow its own marker and evaluate `- 12+3` as a negation.
        while true {
            if body.first == " " || body.first == "\t" {
                body = body.dropFirst()
            } else if ["- ", "* ", "+ "].contains(where: { body.hasPrefix($0) }) {
                body = body.dropFirst(2)
            } else if let marker = numberedListMarker(in: body) {
                body = body.dropFirst(marker)
            } else {
                break
            }
        }

        let expression = String(body)
        guard expression.count >= 3, expression.contains(where: { "+-*/×÷^%".contains($0) }),
            expression.contains(where: \.isNumber)
        else { return nil }
        return expression
    }

    private static let arithmeticCharacters = Set("0123456789.,+-*/×÷()%^ \t")

    /// The length of a leading `12. ` marker — the trailing space is what separates it from `1.5`.
    private static func numberedListMarker(in body: Substring) -> Int? {
        let digits = body.prefix(while: \.isNumber)
        guard !digits.isEmpty, body.dropFirst(digits.count).hasPrefix(". ") else { return nil }
        return digits.count + 2
    }

    /// Locates every block-level construct in a note, in source order. A fenced block shadows
    /// everything inside it, so a rule or table drawn in an example stays literal text.
    static func blockSpans(in markdown: String) -> [NoteBlockSpan] {
        let source = markdown as NSString
        let lines = lineContentRanges(in: source)
        var spans: [NoteBlockSpan] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = source.substring(with: line).trimmingCharacters(in: .whitespaces)

            if let marker = fenceMarker(in: trimmed) {
                let opening = index
                index += 1
                while index < lines.count, !isFence(trimmedLine(index, lines, source), marker: marker) {
                    index += 1
                }
                // An unterminated fence still reads as code: the block runs to the end of the note.
                let closing = min(index, lines.count - 1)
                spans.append(
                    NoteBlockSpan(
                        kind: .codeBlock,
                        range: NSRange(
                            location: line.location, length: NSMaxRange(lines[closing]) - line.location)))
                spans.append(NoteBlockSpan(kind: .codeFence, range: lines[opening]))
                if index < lines.count {
                    spans.append(NoteBlockSpan(kind: .codeFence, range: lines[index]))
                    index += 1
                }
                continue
            }

            if isRule(trimmed) {
                spans.append(NoteBlockSpan(kind: .rule, range: line))
                index += 1
                continue
            }

            if let marker = quoteMarker(in: line, source: source) {
                spans.append(NoteBlockSpan(kind: .quote, range: line, markerRange: marker))
                index += 1
                continue
            }

            if let end = tableEnd(from: index, lines: lines, source: source) {
                for row in index..<end {
                    spans.append(NoteBlockSpan(kind: .tableRow, range: lines[row]))
                }
                index = end
                continue
            }

            index += 1
        }
        return spans
    }

    static func applying(
        _ command: NoteMarkdownCommand, to text: String, selection: NSRange
    ) -> NoteEditResult {
        let source = text as NSString
        let location = min(max(0, selection.location), source.length)
        let length = min(max(0, selection.length), source.length - location)
        let safeSelection = NSRange(location: location, length: length)

        switch command {
        case .bold:
            return wrapping("**", around: safeSelection, in: text, placeholder: "bold text")
        case .italic:
            return wrapping("*", around: safeSelection, in: text, placeholder: "italic text")
        case .strikethrough:
            return wrapping("~~", around: safeSelection, in: text, placeholder: "struck text")
        case .inlineCode:
            return wrapping("`", around: safeSelection, in: text, placeholder: "code")
        case .link:
            return insertingLink(around: safeSelection, in: text)
        case .heading, .bulletedList, .numberedList, .checklist:
            return formattingLines(command, selection: safeSelection, in: text)
        }
    }

    static func applyingBlockFormat(
        _ format: NoteBlockFormat, to text: String, selection: NSRange
    ) -> NoteEditResult {
        let source = text as NSString
        let location = min(max(0, selection.location), source.length)
        let length = min(max(0, selection.length), source.length - location)
        let lineRange = source.lineRange(for: NSRange(location: location, length: length))
        let block = source.substring(with: lineRange)
        let keepsTrailingNewline = block.hasSuffix("\n")
        var lines = block.components(separatedBy: "\n")
        if keepsTrailingNewline { lines.removeLast() }

        var listNumber = 1
        let transformed = lines.map { line in
            let indentation = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
            let body = String(line.dropFirst(indentation.count))
            guard !body.trimmingCharacters(in: .whitespaces).isEmpty else { return line }
            let plainBody = removingBlockPrefix(from: body)

            let prefix: String
            switch format {
            case .text: prefix = ""
            case .heading1: prefix = "# "
            case .heading2: prefix = "## "
            case .heading3: prefix = "### "
            case .bulletedList: prefix = "- "
            case .numberedList:
                prefix = "\(listNumber). "
                listNumber += 1
            }
            return indentation + prefix + plainBody
        }

        var replacement = transformed.joined(separator: "\n")
        if keepsTrailingNewline { replacement += "\n" }
        let result = source.replacingCharacters(in: lineRange, with: replacement)
        return NoteEditResult(
            text: result,
            selection: NSRange(location: lineRange.location, length: (replacement as NSString).length))
    }

    private static func removingBlockPrefix(from line: String) -> String {
        let patterns = [
            #"^#{1,6}[ \t]+"#,
            #"^[-*+][ \t]+\[[ xX]\][ \t]+"#,
            #"^\d+\.[ \t]+"#,
            #"^[-*+][ \t]+"#,
        ]
        for pattern in patterns {
            if line.range(of: pattern, options: .regularExpression) != nil {
                return line.replacingOccurrences(
                    of: pattern, with: "", options: .regularExpression,
                    range: line.startIndex..<line.endIndex)
            }
        }
        return line
    }

    private static func wrapping(
        _ marker: String, around selection: NSRange, in text: String, placeholder: String
    ) -> NoteEditResult {
        let source = text as NSString
        let markerLength = (marker as NSString).length
        let selected = source.substring(with: selection)
        let before = selection.location >= markerLength
            ? source.substring(with: NSRange(location: selection.location - markerLength, length: markerLength))
            : nil
        let afterLocation = selection.location + selection.length
        let after = afterLocation + markerLength <= source.length
            ? source.substring(with: NSRange(location: afterLocation, length: markerLength))
            : nil

        if before == marker, after == marker {
            let replacementRange = NSRange(
                location: selection.location - markerLength,
                length: selection.length + markerLength * 2)
            let result = source.replacingCharacters(in: replacementRange, with: selected)
            return NoteEditResult(
                text: result,
                selection: NSRange(location: selection.location - markerLength, length: selection.length))
        }

        let body = selected.isEmpty ? placeholder : selected
        let replacement = marker + body + marker
        let result = source.replacingCharacters(in: selection, with: replacement)
        return NoteEditResult(
            text: result,
            selection: NSRange(location: selection.location + markerLength, length: (body as NSString).length))
    }

    private static func insertingLink(around selection: NSRange, in text: String) -> NoteEditResult {
        let source = text as NSString
        let selected = source.substring(with: selection)
        let label = selected.isEmpty ? "link title" : selected
        let replacement = "[\(label)](https://)"
        let result = source.replacingCharacters(in: selection, with: replacement)
        return NoteEditResult(
            text: result,
            selection: NSRange(location: selection.location + 1, length: (label as NSString).length))
    }

    private static func formattingLines(
        _ command: NoteMarkdownCommand, selection: NSRange, in text: String
    ) -> NoteEditResult {
        let source = text as NSString
        let lineRange = source.lineRange(for: selection)
        let block = source.substring(with: lineRange)
        let keepsTrailingNewline = block.hasSuffix("\n")
        var lines = block.components(separatedBy: "\n")
        if keepsTrailingNewline { lines.removeLast() }

        let nonempty = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let shouldRemove = !nonempty.isEmpty && nonempty.allSatisfy { lineMatches($0, command: command) }
        let transformed = lines.enumerated().map { index, line in
            transform(line, command: command, remove: shouldRemove, number: index + 1)
        }
        var replacement = transformed.joined(separator: "\n")
        if keepsTrailingNewline { replacement += "\n" }
        let result = source.replacingCharacters(in: lineRange, with: replacement)
        return NoteEditResult(
            text: result,
            selection: NSRange(location: lineRange.location, length: (replacement as NSString).length))
    }

    private static func lineMatches(_ line: String, command: NoteMarkdownCommand) -> Bool {
        let body = line.drop(while: { $0 == " " || $0 == "\t" })
        switch command {
        case .heading: return body.hasPrefix("# ")
        case .bulletedList: return body.hasPrefix("- ") && !body.hasPrefix("- [ ] ") && !body.hasPrefix("- [x] ")
        case .numberedList:
            return body.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil
        case .checklist: return body.hasPrefix("- [ ] ") || body.hasPrefix("- [x] ")
        default: return false
        }
    }

    private static func transform(
        _ line: String, command: NoteMarkdownCommand, remove: Bool, number: Int
    ) -> String {
        let indentation = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
        let body = String(line.dropFirst(indentation.count))
        if remove {
            switch command {
            case .heading: return indentation + String(body.dropFirst(2))
            case .bulletedList: return indentation + String(body.dropFirst(2))
            case .numberedList:
                return indentation + body.replacingOccurrences(
                    of: #"^\d+\.\s"#, with: "", options: .regularExpression)
            case .checklist: return indentation + String(body.dropFirst(6))
            default: return line
            }
        }

        let prefix: String
        switch command {
        case .heading: prefix = "# "
        case .bulletedList: prefix = "- "
        case .numberedList: prefix = "\(number). "
        case .checklist: prefix = "- [ ] "
        default: return line
        }
        return indentation + prefix + body
    }

    private static func lineContentRanges(in source: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        var index = 0
        while index < source.length {
            let line = source.lineRange(for: NSRange(location: index, length: 0))
            index = NSMaxRange(line)
            var content = line
            while content.length > 0, isLineBreak(source.character(at: NSMaxRange(content) - 1)) {
                content.length -= 1
            }
            ranges.append(content)
        }
        return ranges
    }

    private static func trimmedLine(_ index: Int, _ lines: [NSRange], _ source: NSString) -> String {
        source.substring(with: lines[index]).trimmingCharacters(in: .whitespaces)
    }

    private static func fenceMarker(in trimmed: String) -> Character? {
        guard let marker = trimmed.first, marker == "`" || marker == "~" else { return nil }
        let run = trimmed.prefix { $0 == marker }
        guard run.count >= 3 else { return nil }
        // An info string may not contain the fence character itself, which is what rules out "``x``".
        return trimmed.dropFirst(run.count).contains(marker) ? nil : marker
    }

    private static func isFence(_ trimmed: String, marker: Character) -> Bool {
        trimmed.count >= 3 && trimmed.allSatisfy { $0 == marker }
    }

    private static func isRule(_ trimmed: String) -> Bool {
        guard let first = trimmed.first, first == "-" || first == "*" || first == "_" else {
            return false
        }
        let bare = trimmed.filter { !$0.isWhitespace }
        return bare.count >= 3 && bare.allSatisfy { $0 == first }
    }

    private static func quoteMarker(in line: NSRange, source: NSString) -> NSRange? {
        var offset = line.location
        let end = NSMaxRange(line)
        while offset < end, isSpace(source.character(at: offset)) { offset += 1 }
        guard offset < end, source.character(at: offset) == 0x3E else { return nil }
        offset += 1
        while offset < end, source.character(at: offset) == 0x20 { offset += 1 }
        return NSRange(location: line.location, length: offset - line.location)
    }

    /// A pipe table only when the row under the header is a delimiter row — otherwise a sentence that
    /// happens to contain a pipe would swallow the paragraph around it.
    private static func tableEnd(from start: Int, lines: [NSRange], source: NSString) -> Int? {
        guard start + 1 < lines.count else { return nil }
        let header = cells(in: source.substring(with: lines[start]))
        guard header.count >= 2 else { return nil }
        let delimiter = cells(in: source.substring(with: lines[start + 1]))
        guard delimiter.count == header.count, delimiter.allSatisfy(isDelimiterCell) else {
            return nil
        }
        var index = start + 2
        // Inside a table a ragged row is still a row; a blank or pipe-less line ends it.
        while index < lines.count, !cells(in: source.substring(with: lines[index])).isEmpty {
            index += 1
        }
        return index
    }

    private static func cells(in line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return [] }
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }
        return trimmed.components(separatedBy: "|").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }

    private static func isDelimiterCell(_ cell: String) -> Bool {
        let bare = cell.replacingOccurrences(of: ":", with: "")
        return !bare.isEmpty && bare.allSatisfy { $0 == "-" }
    }

    private static func isSpace(_ character: unichar) -> Bool {
        character == 0x20 || character == 0x09
    }

    private static func isLineBreak(_ character: unichar) -> Bool {
        character == 0x0A || character == 0x0D || character == 0x85 || character == 0x2028
            || character == 0x2029
    }

    private static func stripMarkup(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        result = result.replacingOccurrences(
            of: #"^(#{1,6}\s+|-\s+\[[ xX]\]\s+|[-*+]\s+|\d+\.\s+)"#,
            with: "", options: .regularExpression)
        result = result.replacingOccurrences(
            of: #"\[([^\]]+)\]\([^\)]+\)"#, with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(
            of: #"(\*\*|__|~~|`|\*|_)"#, with: "", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
