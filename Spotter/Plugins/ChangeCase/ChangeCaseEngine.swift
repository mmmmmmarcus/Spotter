import Foundation

enum ChangeCaseKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case camel, capital, constant, dot, header, lower, lowerFirst, noCase, kebab
    case upperKebab, pascal, pascalSnake, path, random, sentence, snake, alternating
    case swap, title, upper, upperFirst

    var id: String { rawValue }

    var title: String {
        switch self {
        case .camel: "camelCase"
        case .capital: "Capital Case"
        case .constant: "CONSTANT_CASE"
        case .dot: "dot.case"
        case .header: "Header-Case"
        case .lower: "lower case"
        case .lowerFirst: "lower first"
        case .noCase: "no case"
        case .kebab: "kebab-case"
        case .upperKebab: "KEBAB-UPPER"
        case .pascal: "PascalCase"
        case .pascalSnake: "Pascal_Snake_Case"
        case .path: "path/case"
        case .random: "rAnDoM cAsE"
        case .sentence: "Sentence case"
        case .snake: "snake_case"
        case .alternating: "aLtErNaTiNg CaSe"
        case .swap: "sWAP cASE"
        case .title: "Title Case"
        case .upper: "UPPER CASE"
        case .upperFirst: "Upper first"
        }
    }

    var systemImage: String {
        switch self {
        case .lower, .lowerFirst: "textformat.size.smaller"
        case .upper, .upperFirst, .constant, .upperKebab: "textformat.size.larger"
        case .random, .alternating, .swap: "shuffle"
        default: "textformat"
        }
    }
}

struct ChangeCaseOptions: Sendable {
    var preserveCase = true
    var preservePunctuation = false
    var exceptions: [String] = []
    var prefixCharacters = ""
    var suffixCharacters = ""
}

enum ChangeCaseEngine {
    static func transform(
        _ input: String, as kind: ChangeCaseKind, options: ChangeCaseOptions = .init()
    ) -> String {
        input.split(separator: "\n", omittingEmptySubsequences: false)
            .map { transformLine(String($0), as: kind, options: options) }
            .joined(separator: "\n")
    }

    private static func transformLine(
        _ input: String, as kind: ChangeCaseKind, options: ChangeCaseOptions
    ) -> String {
        if kind == .swap {
            return input.map { character in
                let value = String(character)
                if value == value.uppercased() { return value.lowercased() }
                return value.uppercased()
            }.joined()
        }
        if kind == .lower { return options.preservePunctuation ? input.lowercased() : words(input).joined(separator: " ").lowercased() }
        if kind == .upper { return options.preservePunctuation ? input.uppercased() : words(input).joined(separator: " ").uppercased() }
        if kind == .lowerFirst { return changeFirst(input, upper: false) }
        if kind == .upperFirst { return changeFirst(input, upper: true) }

        let preservesOriginal = kind == .swap || kind == .alternating || kind == .random
            || kind == .lowerFirst || kind == .upperFirst
        let source = options.preserveCase || preservesOriginal ? input : input.lowercased()
        let edges = retainedEdges(source, options: options)
        let tokens = words(edges.body)
        guard !tokens.isEmpty else { return input }
        let transformed: String
        switch kind {
        case .camel:
            transformed = tokens[0].lowercased() + tokens.dropFirst().map(capitalized).joined()
        case .capital:
            transformed = tokens.map(capitalized).joined(separator: " ")
        case .constant:
            transformed = tokens.map { $0.uppercased() }.joined(separator: "_")
        case .dot:
            transformed = tokens.map { $0.lowercased() }.joined(separator: ".")
        case .header:
            transformed = tokens.map(capitalized).joined(separator: "-")
        case .noCase:
            transformed = tokens.map { $0.lowercased() }.joined(separator: " ")
        case .kebab:
            transformed = tokens.map { $0.lowercased() }.joined(separator: "-")
        case .upperKebab:
            transformed = tokens.map { $0.uppercased() }.joined(separator: "-")
        case .pascal:
            transformed = tokens.map(capitalized).joined()
        case .pascalSnake:
            transformed = tokens.map(capitalized).joined(separator: "_")
        case .path:
            transformed = tokens.map { $0.lowercased() }.joined(separator: "/")
        case .random:
            transformed = tokens.joined(separator: " ").enumerated().map { index, character in
                Bool.random() ? String(character).uppercased() : String(character).lowercased()
            }.joined()
        case .sentence:
            transformed = sentence(tokens, exceptions: options.exceptions)
        case .snake:
            transformed = tokens.map { $0.lowercased() }.joined(separator: "_")
        case .alternating:
            transformed = tokens.joined(separator: " ").enumerated().map { index, character in
                index.isMultiple(of: 2) ? String(character).lowercased() : String(character).uppercased()
            }.joined()
        case .title:
            transformed = title(tokens, exceptions: options.exceptions)
        case .lower, .lowerFirst, .swap, .upper, .upperFirst:
            transformed = input
        }
        return edges.prefix + transformed + edges.suffix
    }

    static func words(_ input: String) -> [String] {
        var normalized = input
            .replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "([A-Z]+)([A-Z][a-z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "[^\\p{L}\\p{N}]+", with: " ", options: .regularExpression)
        normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.split(whereSeparator: \Character.isWhitespace).map(String.init)
    }

    private static func capitalized(_ word: String) -> String {
        guard let first = word.first else { return word }
        return String(first).uppercased() + word.dropFirst().lowercased()
    }

    private static func sentence(_ words: [String], exceptions: [String]) -> String {
        let merged = mergeExceptions(words, exceptions: exceptions)
        let mapped = merged.enumerated().map { index, word in
            exception(word, in: exceptions) ?? (index == 0 ? capitalized(word) : word.lowercased())
        }
        return mapped.joined(separator: " ")
    }

    private static func title(_ words: [String], exceptions: [String]) -> String {
        let small = Set(["a", "an", "and", "as", "at", "but", "by", "for", "in", "nor", "of", "on", "or", "the", "to"])
        let merged = mergeExceptions(words, exceptions: exceptions)
        return merged.enumerated().map { index, word in
            if let value = exception(word, in: exceptions) { return value }
            let lower = word.lowercased()
            if index > 0, index < merged.count - 1, small.contains(lower) { return lower }
            return capitalized(word)
        }.joined(separator: " ")
    }

    private static func mergeExceptions(_ words: [String], exceptions: [String]) -> [String] {
        let candidates = exceptions.map { ($0, self.words($0)) }
            .filter { !$0.1.isEmpty }
            .sorted { $0.1.count > $1.1.count }
        var result: [String] = []
        var index = 0
        while index < words.count {
            if let match = candidates.first(where: { _, parts in
                guard index + parts.count <= words.count else { return false }
                return zip(words[index..<(index + parts.count)], parts).allSatisfy {
                    $0.0.caseInsensitiveCompare($0.1) == .orderedSame
                }
            }) {
                result.append(match.0)
                index += match.1.count
            } else {
                result.append(words[index])
                index += 1
            }
        }
        return result
    }

    private static func exception(_ word: String, in exceptions: [String]) -> String? {
        exceptions.first { $0.caseInsensitiveCompare(word) == .orderedSame }
    }

    private static func changeFirst(_ input: String, upper: Bool) -> String {
        guard let index = input.firstIndex(where: { $0.isLetter }) else { return input }
        let next = input.index(after: index)
        let changed = upper ? String(input[index]).uppercased() : String(input[index]).lowercased()
        return String(input[..<index]) + changed + String(input[next...])
    }

    private static func retainedEdges(
        _ input: String, options: ChangeCaseOptions
    ) -> (prefix: String, body: String, suffix: String) {
        let prefixSet = CharacterSet(charactersIn: options.prefixCharacters)
        let suffixSet = CharacterSet(charactersIn: options.suffixCharacters)
        var start = input.startIndex
        while start < input.endIndex,
            input[start].unicodeScalars.allSatisfy(prefixSet.contains)
        { start = input.index(after: start) }
        var end = input.endIndex
        while end > start {
            let previous = input.index(before: end)
            guard input[previous].unicodeScalars.allSatisfy(suffixSet.contains) else { break }
            end = previous
        }
        return (String(input[..<start]), String(input[start..<end]), String(input[end...]))
    }
}
