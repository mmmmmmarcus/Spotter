import Foundation

struct DynamicTemplateContext: Sendable {
    var selection = ""
    var clipboardHistory: [String] = []
    var now = Date()
    var calendar = Calendar.current
    var locale = Locale.current
    var arguments: [String: String] = [:]
    var snippets: [String: String] = [:]
    var makeUUID: @Sendable () -> UUID = { UUID() }
}

struct DynamicTemplateResult: Equatable, Sendable {
    var text: String
    var cursorOffset: Int?
    var missingArguments: [String]
}

enum DynamicTemplate {
    enum Encoding: Sendable { case none, percent }

    static func expand(_ source: String, context: DynamicTemplateContext, encoding: Encoding = .none) -> DynamicTemplateResult {
        expand(source, context: context, encoding: encoding, depth: 0, visited: [])
    }

    private static func expand(_ source: String, context: DynamicTemplateContext, encoding: Encoding,
        depth: Int, visited: Set<String>) -> DynamicTemplateResult {
        var result = DynamicTemplateResult(text: "", cursorOffset: nil, missingArguments: [])
        var index = source.startIndex
        while index < source.endIndex {
            guard let open = source[index...].firstIndex(of: "{") else {
                result.text += String(source[index...])
                break
            }
            result.text += String(source[index..<open])
            guard let close = source[source.index(after: open)...].firstIndex(of: "}") else {
                result.text += String(source[open...])
                break
            }
            let raw = String(source[source.index(after: open)..<close])
            let token = parse(raw)
            let literal = String(source[open...close])
            switch token.name.lowercased() {
            case "clipboard":
                let offset = Int(token.attributes["offset"] ?? "0") ?? 0
                let value = context.clipboardHistory.indices.contains(offset) ? context.clipboardHistory[offset] : ""
                result.text += transformed(value, modifiers: token.modifiers, encoding: encoding)
            case "selection", "selectedtext":
                result.text += transformed(context.selection, modifiers: token.modifiers, encoding: encoding)
            case "date", "time", "datetime", "day":
                result.text += transformed(dateValue(token, context: context), modifiers: token.modifiers, encoding: encoding)
            case "uuid":
                result.text += transformed(context.makeUUID().uuidString.lowercased(), modifiers: token.modifiers, encoding: encoding)
            case "argument", "query":
                let name = token.attributes["name"] ?? "Argument"
                if let value = context.arguments[name] ?? token.attributes["default"] {
                    result.text += transformed(value, modifiers: token.modifiers, encoding: encoding)
                } else {
                    result.text += literal
                    if !result.missingArguments.contains(name) { result.missingArguments.append(name) }
                }
            case "cursor":
                if result.cursorOffset == nil { result.cursorOffset = result.text.count }
            default:
                if token.name.lowercased().hasPrefix("snippet:"), depth < 5 {
                    let key = String(token.name.dropFirst("snippet:".count)).lowercased()
                    if !visited.contains(key), let body = context.snippets[key] {
                        var next = visited
                        next.insert(key)
                        let nested = expand(body, context: context, encoding: encoding, depth: depth + 1, visited: next)
                        let base = result.text.count
                        result.text += nested.text
                        if result.cursorOffset == nil, let cursor = nested.cursorOffset { result.cursorOffset = base + cursor }
                        for name in nested.missingArguments where !result.missingArguments.contains(name) {
                            result.missingArguments.append(name)
                        }
                    } else { result.text += literal }
                } else { result.text += literal }
            }
            index = source.index(after: close)
        }
        return result
    }

    private struct Token {
        let name: String
        let attributes: [String: String]
        let modifiers: [String]
    }

    private static func parse(_ raw: String) -> Token {
        let pieces = raw.split(separator: "|", omittingEmptySubsequences: false)
        let head = String(pieces.first ?? "").trimmingCharacters(in: .whitespaces)
        let modifiers = pieces.dropFirst().map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        let name = head.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? head
        var attributes: [String: String] = [:]
        var cursor = head.index(head.startIndex, offsetBy: min(name.count, head.count))
        while cursor < head.endIndex {
            while cursor < head.endIndex, head[cursor].isWhitespace { cursor = head.index(after: cursor) }
            let keyStart = cursor
            while cursor < head.endIndex, head[cursor] != "=", !head[cursor].isWhitespace { cursor = head.index(after: cursor) }
            guard cursor < head.endIndex, head[cursor] == "=" else { break }
            let key = String(head[keyStart..<cursor]).lowercased()
            cursor = head.index(after: cursor)
            let value: String
            if cursor < head.endIndex, head[cursor] == "\"" {
                cursor = head.index(after: cursor)
                let start = cursor
                while cursor < head.endIndex, head[cursor] != "\"" { cursor = head.index(after: cursor) }
                value = String(head[start..<cursor])
                if cursor < head.endIndex { cursor = head.index(after: cursor) }
            } else {
                let start = cursor
                while cursor < head.endIndex, !head[cursor].isWhitespace { cursor = head.index(after: cursor) }
                value = String(head[start..<cursor])
            }
            if !key.isEmpty { attributes[key] = value }
        }
        return Token(name: name, attributes: attributes, modifiers: modifiers)
    }

    private static func dateValue(_ token: Token, context: DynamicTemplateContext) -> String {
        let formatter = DateFormatter()
        formatter.locale = token.attributes["locale"].map(Locale.init(identifier:)) ?? context.locale
        formatter.calendar = context.calendar
        let date = shifted(context.now, by: token.attributes["offset"], calendar: context.calendar)
        if let format = token.attributes["format"], !format.isEmpty { formatter.dateFormat = format }
        else {
            switch token.name.lowercased() {
            case "time": formatter.timeStyle = .short
            case "datetime": formatter.dateStyle = .medium; formatter.timeStyle = .short
            case "day": formatter.dateFormat = "EEEE"
            default: formatter.dateStyle = .medium
            }
        }
        return formatter.string(from: date)
    }

    private static func shifted(_ date: Date, by expression: String?, calendar: Calendar) -> Date {
        guard let expression else { return date }
        var result = date
        for part in expression.split(whereSeparator: \.isWhitespace) {
            let raw = String(part)
            guard raw.count >= 2, let amount = Int(raw.dropLast()) else { continue }
            let component: Calendar.Component? = switch raw.last {
            case "m": .minute
            case "h": .hour
            case "d": .day
            case "M": .month
            case "y": .year
            default: nil
            }
            if let component { result = calendar.date(byAdding: component, value: amount, to: result) ?? result }
        }
        return result
    }

    private static func transformed(_ value: String, modifiers: [String], encoding: Encoding) -> String {
        var result = value
        var raw = false
        for modifier in modifiers {
            switch modifier {
            case "uppercase": result = result.uppercased()
            case "lowercase": result = result.lowercased()
            case "trim": result = result.trimmingCharacters(in: .whitespacesAndNewlines)
            case "percent-encode": result = percentEncoded(result); raw = true
            case "json-stringify":
                let data = try? JSONEncoder().encode(result)
                result = data.map { String(decoding: $0, as: UTF8.self).dropFirst().dropLast() }.map(String.init) ?? result
            case "raw": raw = true
            default: break
            }
        }
        return encoding == .percent && !raw ? percentEncoded(result) : result
    }

    private static func percentEncoded(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")) ?? value
    }
}
