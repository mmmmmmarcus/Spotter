import Foundation

struct ScheduleNoteRun: Equatable, Sendable {
    let text: String
    var url: URL? = nil
}

struct ScheduleNoteField: Equatable, Sendable {
    let name: String
    let value: String
}

struct ScheduleNotes: Equatable, Sendable {
    let runs: [ScheduleNoteRun]
    let fields: [ScheduleNoteField]

    static func parse(_ raw: String) -> ScheduleNotes {
        let breaks = replacing(#"(?i)<br\s*/?>|</(?:p|div|li|h[1-6])\s*>"#, in: raw, with: "\n")
        let clean = replacing(#"(?is)<(script|style)\b[^>]*>.*?</\1\s*>"#, in: breaks, with: "")
        var fields: [ScheduleNoteField] = []
        var lines: [String] = []
        let fieldPattern = try! NSRegularExpression(pattern: #"(?i)^\s*(组织者|Organizer|参与者|参与人|Participants|Attendees|会议\s*ID|Meeting\s*ID)\s*(?:[（(][^）)]*[）)])?\s*[:：]\s*(.+)$"#)
        for line in clean.components(separatedBy: .newlines) {
            let plain = plainText(line)
            if let match = fieldPattern.firstMatch(in: plain, range: NSRange(plain.startIndex..., in: plain)) {
                let key = (plain as NSString).substring(with: match.range(at: 1)).lowercased()
                let name = ["组织者", "organizer"].contains(key) ? "Organizer"
                    : key.contains("id") ? "Meeting ID" : "Participants"
                fields.append(.init(name: name, value: (plain as NSString).substring(with: match.range(at: 2))))
            } else { lines.append(line) }
        }
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = try! NSRegularExpression(pattern: #"(?is)<a\b[^>]*?\bhref\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))[^>]*>(.*?)</a\s*>|\[([^\]\n]+)\]\(([^\s)]+)\)"#)
        let source = text as NSString
        var runs: [ScheduleNoteRun] = []
        var cursor = 0
        for match in pattern.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            appendPlain(source.substring(with: NSRange(location: cursor, length: match.range.location - cursor)), to: &runs)
            func capture(_ index: Int) -> String? {
                let range = match.range(at: index)
                return range.location == NSNotFound ? nil : source.substring(with: range)
            }
            let address = entities(capture(1) ?? capture(2) ?? capture(3) ?? capture(6) ?? "")
            let title = plainText(capture(4) ?? capture(5) ?? "")
            runs.append(.init(text: title.isEmpty ? address : title, url: safeURL(address)))
            cursor = NSMaxRange(match.range)
        }
        appendPlain(source.substring(from: cursor), to: &runs)
        return ScheduleNotes(runs: runs, fields: fields)
    }

    static func safeURL(_ text: String) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), ["https", "http", "mailto"].contains(scheme),
              scheme == "mailto" || url.host?.isEmpty == false else { return nil }
        return url
    }

    private static func appendPlain(_ raw: String, to runs: inout [ScheduleNoteRun]) {
        let text = plainText(raw)
        let source = text as NSString
        let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        var cursor = 0
        for match in detector.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            let before = source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            if !before.isEmpty { runs.append(.init(text: before)) }
            let literal = source.substring(with: match.range)
            let url = match.url.flatMap { safeURL($0.absoluteString) }
            runs.append(.init(text: url?.host ?? literal, url: url))
            cursor = NSMaxRange(match.range)
        }
        let remaining = source.substring(from: cursor)
        if !remaining.isEmpty { runs.append(.init(text: remaining)) }
    }

    private static func plainText(_ text: String) -> String {
        entities(replacing(#"(?is)</?[a-z][^>]*>"#, in: text, with: ""))
    }

    private static func replacing(_ pattern: String, in text: String, with replacement: String) -> String {
        let regex = try! NSRegularExpression(pattern: pattern)
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: replacement)
    }

    private static func entities(_ text: String) -> String {
        let regex = try! NSRegularExpression(pattern: #"&(#x[0-9a-fA-F]+|#[0-9]+|amp|lt|gt|quot|apos|nbsp);"#)
        let source = text as NSString
        var result = text
        let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " "]
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)).reversed() {
            let key = source.substring(with: match.range(at: 1))
            var value = named[key]
            if key.hasPrefix("#") {
                let hex = key.hasPrefix("#x")
                if let number = UInt32(key.dropFirst(hex ? 2 : 1), radix: hex ? 16 : 10),
                   let scalar = Unicode.Scalar(number) { value = String(scalar) }
            }
            if let value, let range = Range(match.range, in: result) { result.replaceSubrange(range, with: value) }
        }
        return result
    }
}
