import Foundation

/// One saved snippet: a named piece of reusable text, searchable and pasteable from the palette.
/// A snippet may additionally carry an expansion keyword — typing prefix+keyword anywhere replaces
/// it with the content, the original Text Replacement behavior, now one option on a snippet.
struct Snippet: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var content: String
    /// Nil for palette-only snippets; set, the typing matcher expands prefix+keyword into `content`.
    var keyword: String?

    init(id: UUID = UUID(), name: String, content: String, keyword: String? = nil) {
        self.id = id
        self.name = name
        self.content = content
        self.keyword = keyword
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, content, keyword, replacement
    }

    /// Decodes both shapes: the retired rule records `{id, keyword, replacement}` (every one an
    /// expanding snippet named after its keyword) and the current `{id, name, content, keyword?}`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        keyword = try container.decodeIfPresent(String.self, forKey: .keyword)
        if let content = try container.decodeIfPresent(String.self, forKey: .content) {
            self.content = content
            name = try container.decodeIfPresent(String.self, forKey: .name) ?? keyword ?? "Snippet"
        } else {
            content = try container.decode(String.self, forKey: .replacement)
            name = keyword ?? "Snippet"
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(keyword, forKey: .keyword)
    }
}

enum SnippetValidationError: LocalizedError, Equatable {
    case invalidPrefix
    case emptyName
    case invalidKeyword
    case emptyContent
    case contentTooLong
    case duplicateKeyword
    case conflictingKeyword(String)

    var errorDescription: String? {
        switch self {
        case .invalidPrefix:
            return "The prefix must be 1–8 visible characters with no spaces."
        case .emptyName:
            return "The snippet needs a name."
        case .invalidKeyword:
            return "The keyword must be 1–64 characters with no spaces."
        case .emptyContent:
            return "The snippet text can't be empty."
        case .contentTooLong:
            return "The snippet text must be 10,000 characters or fewer."
        case .duplicateKeyword:
            return "That keyword already exists."
        case .conflictingKeyword(let keyword):
            return "This conflicts with “\(keyword)”; one keyword can't begin with another."
        }
    }
}

enum SnippetValidator {
    static let defaultPrefix = "@@"

    static func normalizedPrefix(_ value: String) throws -> String {
        let prefix = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prefix.isEmpty, prefix.count <= 8,
            prefix.unicodeScalars.allSatisfy({ !CharacterSet.whitespacesAndNewlines.contains($0) })
        else { throw SnippetValidationError.invalidPrefix }
        return prefix
    }

    static func normalizedSnippet(
        _ snippet: Snippet, among existing: [Snippet],
        excluding excludedID: UUID? = nil
    ) throws -> Snippet {
        let name = snippet.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 100 else {
            throw SnippetValidationError.emptyName
        }
        guard !snippet.content.isEmpty else {
            throw SnippetValidationError.emptyContent
        }
        guard snippet.content.count <= 10_000 else {
            throw SnippetValidationError.contentTooLong
        }

        // An empty keyword field is a palette-only snippet, not an invalid one.
        let trimmedKeyword = snippet.keyword?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let keyword = trimmedKeyword, !keyword.isEmpty else {
            return Snippet(id: snippet.id, name: name, content: snippet.content, keyword: nil)
        }
        guard keyword.count <= 64,
            keyword.unicodeScalars.allSatisfy({ !CharacterSet.whitespacesAndNewlines.contains($0) })
        else { throw SnippetValidationError.invalidKeyword }

        let folded = keyword.lowercased()
        for other in existing where other.id != excludedID {
            guard let otherKeyword = other.keyword else { continue }
            let otherFolded = otherKeyword.lowercased()
            if folded == otherFolded {
                throw SnippetValidationError.duplicateKeyword
            }
            if folded.hasPrefix(otherFolded) || otherFolded.hasPrefix(folded) {
                throw SnippetValidationError.conflictingKeyword(otherKeyword)
            }
        }
        return Snippet(id: snippet.id, name: name, content: snippet.content, keyword: keyword)
    }
}

struct TextReplacementMatch: Equatable, Sendable {
    let trigger: String
    let replacement: String
    let deletionCount: Int
}

/// Keeps only a suffix that can still become a configured trigger, never an arbitrary typing history.
struct TextReplacementEngine: Sendable {
    private struct Trigger: Sendable {
        let folded: String
        let source: String
        let replacement: String
        let deletionCount: Int
    }

    private let triggers: [Trigger]
    private(set) var pendingCharacterCount = 0
    private var pending = ""

    /// Only keyworded snippets become triggers; palette-only snippets never touch typing.
    init(prefix: String, snippets: [Snippet]) {
        triggers = snippets.compactMap { snippet in
            guard let keyword = snippet.keyword else { return nil }
            let source = prefix + keyword
            return Trigger(
                folded: source.lowercased(), source: source, replacement: snippet.content,
                deletionCount: source.count)
        }
    }

    var isEmpty: Bool { triggers.isEmpty }

    mutating func consume(_ input: String) -> TextReplacementMatch? {
        guard !triggers.isEmpty else {
            reset()
            return nil
        }

        for character in input.lowercased() {
            let candidate = pending + String(character)
            if let trigger = triggers.first(where: { $0.folded == candidate }) {
                reset()
                return TextReplacementMatch(
                    trigger: trigger.source, replacement: trigger.replacement,
                    deletionCount: trigger.deletionCount)
            }
            pending = longestViableSuffix(of: candidate)
            pendingCharacterCount = pending.count
        }
        return nil
    }

    mutating func deleteBackward() {
        if !pending.isEmpty { pending.removeLast() }
        pendingCharacterCount = pending.count
    }

    mutating func reset() {
        pending = ""
        pendingCharacterCount = 0
    }

    private func longestViableSuffix(of candidate: String) -> String {
        let characters = Array(candidate)
        for start in characters.indices {
            let suffix = String(characters[start...])
            if triggers.contains(where: { $0.folded.hasPrefix(suffix) }) { return suffix }
        }
        return ""
    }
}
