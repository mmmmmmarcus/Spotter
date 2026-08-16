import Foundation

/// One block of an assistant reply. Inline spans (bold, italics, code, links) stay as Markdown
/// inside a block's text — SwiftUI's own parser renders those; only block structure needs splitting.
enum AIChatMarkdownBlock: Equatable, Sendable {
    case paragraph(String)
    case heading(level: Int, text: String)
    case listItem(marker: String, text: String, depth: Int)
    case quote(String)
    case code(language: String?, text: String)
    case table(header: [String], rows: [[String]])
    case rule
}

/// The pure block splitter behind AI Chat's reply rendering. Foundation-only so
/// `Tools/ai-chat-test.swift` compiles it standalone; every style decision lives in the view.
enum AIChatMarkdown {
    /// Two spaces of indent per nesting level, capped — a palette column has no room for deeper.
    private static let maxDepth = 3
    private static let maxHeadingLevel = 6

    static func blocks(in text: String) -> [AIChatMarkdownBlock] {
        let lines = text.components(separatedBy: .newlines)
        var blocks: [AIChatMarkdownBlock] = []
        var paragraph: [String] = []
        var index = 0

        func flushParagraph() {
            let joined = paragraph.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            paragraph.removeAll()
            guard !joined.isEmpty else { return }
            blocks.append(.paragraph(joined))
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let fence = fenceOpener(trimmed) {
                flushParagraph()
                index += 1
                var body: [String] = []
                while index < lines.count,
                    !isFenceClose(lines[index].trimmingCharacters(in: .whitespaces), fence: fence.marker)
                {
                    body.append(lines[index])
                    index += 1
                }
                // An unterminated fence still renders as code: a truncated reply ends mid-block.
                if index < lines.count { index += 1 }
                blocks.append(.code(language: fence.language, text: body.joined(separator: "\n")))
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            if isRule(trimmed) {
                flushParagraph()
                blocks.append(.rule)
                index += 1
                continue
            }

            if let heading = heading(in: trimmed) {
                flushParagraph()
                blocks.append(heading)
                index += 1
                continue
            }

            if let table = table(at: index, in: lines) {
                flushParagraph()
                blocks.append(table.block)
                index = table.next
                continue
            }

            if let item = listItem(in: line) {
                flushParagraph()
                blocks.append(item)
                index += 1
                continue
            }

            if let quoted = quote(in: trimmed) {
                flushParagraph()
                // Consecutive quoted lines are one block, not one per line.
                if case .quote(let previous) = blocks.last {
                    blocks[blocks.count - 1] = .quote(previous + "\n" + quoted)
                } else {
                    blocks.append(.quote(quoted))
                }
                index += 1
                continue
            }

            paragraph.append(trimmed)
            index += 1
        }

        flushParagraph()
        return blocks
    }

    private static func fenceOpener(_ trimmed: String) -> (marker: Character, language: String?)? {
        guard let marker = trimmed.first, marker == "`" || marker == "~" else { return nil }
        let run = trimmed.prefix { $0 == marker }
        guard run.count >= 3 else { return nil }
        let language = trimmed.dropFirst(run.count).trimmingCharacters(in: .whitespaces)
        // An info string may not contain the fence character itself, which is what rules out "``x``".
        guard !language.contains(marker) else { return nil }
        return (marker, language.isEmpty ? nil : language)
    }

    private static func isFenceClose(_ trimmed: String, fence: Character) -> Bool {
        trimmed.count >= 3 && trimmed.allSatisfy { $0 == fence }
    }

    private static func isRule(_ trimmed: String) -> Bool {
        guard let first = trimmed.first, first == "-" || first == "*" || first == "_" else {
            return false
        }
        let bare = trimmed.filter { !$0.isWhitespace }
        return bare.count >= 3 && bare.allSatisfy { $0 == first }
    }

    private static func heading(in trimmed: String) -> AIChatMarkdownBlock? {
        let hashes = trimmed.prefix { $0 == "#" }
        guard (1...maxHeadingLevel).contains(hashes.count) else { return nil }
        let rest = trimmed.dropFirst(hashes.count)
        guard rest.first?.isWhitespace == true else { return nil }
        var text = rest.trimmingCharacters(in: .whitespaces)
        while text.hasSuffix("#") { text.removeLast() }
        text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return .heading(level: hashes.count, text: text)
    }

    private static func quote(in trimmed: String) -> String? {
        guard trimmed.hasPrefix(">") else { return nil }
        return String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
    }

    private static func listItem(in line: String) -> AIChatMarkdownBlock? {
        let indent = line.prefix { $0 == " " || $0 == "\t" }
            .reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
        let depth = min(indent / 2, maxDepth)
        var rest = Substring(line.drop { $0 == " " || $0 == "\t" })

        var marker: String
        if let bullet = rest.first, bullet == "-" || bullet == "*" || bullet == "+" {
            guard rest.dropFirst().first == " " else { return nil }
            rest = rest.dropFirst(2)
            marker = "•"
        } else if rest.first?.isNumber == true {
            let digits = rest.prefix(while: \.isNumber)
            let after = rest.dropFirst(digits.count)
            guard let punctuation = after.first, punctuation == "." || punctuation == ")",
                after.dropFirst().first == " "
            else { return nil }
            rest = after.dropFirst(2)
            marker = String(digits) + "."
        } else {
            return nil
        }

        // A task list keeps its checkbox as the marker rather than rendering the raw brackets.
        let text = rest.trimmingCharacters(in: .whitespaces)
        if let box = taskBox(in: text) {
            marker = box.marker
            return .listItem(marker: marker, text: box.text, depth: depth)
        }
        return .listItem(marker: marker, text: text, depth: depth)
    }

    private static func taskBox(in text: String) -> (marker: String, text: String)? {
        guard text.hasPrefix("[") else { return nil }
        let box = text.prefix(3)
        guard box.count == 3, box.hasSuffix("]") else { return nil }
        let state = box.dropFirst().first
        let done: Bool
        switch state {
        case " ": done = false
        case "x", "X": done = true
        default: return nil
        }
        return (done ? "☑" : "☐", String(text.dropFirst(3)).trimmingCharacters(in: .whitespaces))
    }

    /// A pipe table only when the row after the header is a delimiter row — otherwise a sentence
    /// that happens to contain a pipe would swallow the paragraph around it.
    private static func table(
        at start: Int, in lines: [String]
    ) -> (block: AIChatMarkdownBlock, next: Int)? {
        guard start + 1 < lines.count else { return nil }
        let header = cells(in: lines[start])
        guard header.count >= 2 else { return nil }
        let delimiter = cells(in: lines[start + 1])
        guard delimiter.count == header.count, delimiter.allSatisfy(isDelimiterCell) else {
            return nil
        }

        var rows: [[String]] = []
        var index = start + 2
        while index < lines.count {
            // Inside a table a ragged row is still a row; a blank or pipe-less line ends it.
            let row = cells(in: lines[index])
            guard !row.isEmpty else { break }
            rows.append(row)
            index += 1
        }
        return (.table(header: header, rows: rows), index)
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
}
