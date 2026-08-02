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
    var preview: String { NoteEngine.preview(in: content) }
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

struct NoteEditResult: Equatable, Sendable {
    let text: String
    let selection: NSRange
}

enum NoteEngine {
    static func title(in markdown: String) -> String {
        for line in markdown.components(separatedBy: .newlines) {
            let cleaned = stripMarkup(line)
            if !cleaned.isEmpty { return String(cleaned.prefix(80)) }
        }
        return "Untitled Note"
    }

    static func preview(in markdown: String) -> String {
        let meaningful = markdown.components(separatedBy: .newlines)
            .map(stripMarkup)
            .filter { !$0.isEmpty }
        guard !meaningful.isEmpty else { return "No additional text" }
        let body = meaningful.dropFirst().prefix(2).joined(separator: " ")
        return body.isEmpty ? "No additional text" : String(body.prefix(120))
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
