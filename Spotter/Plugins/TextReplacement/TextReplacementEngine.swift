import Foundation

struct TextReplacementRule: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var keyword: String
    var replacement: String

    init(id: UUID = UUID(), keyword: String, replacement: String) {
        self.id = id
        self.keyword = keyword
        self.replacement = replacement
    }
}

enum TextReplacementValidationError: LocalizedError, Equatable {
    case invalidPrefix
    case invalidKeyword
    case emptyReplacement
    case replacementTooLong
    case duplicateKeyword
    case conflictingKeyword(String)

    var errorDescription: String? {
        switch self {
        case .invalidPrefix:
            return "The prefix must be 1–8 visible characters with no spaces."
        case .invalidKeyword:
            return "The keyword must be 1–64 characters with no spaces."
        case .emptyReplacement:
            return "The replacement text can't be empty."
        case .replacementTooLong:
            return "The replacement text must be 10,000 characters or fewer."
        case .duplicateKeyword:
            return "That keyword already exists."
        case .conflictingKeyword(let keyword):
            return "This conflicts with “\(keyword)”; one keyword can't begin with another."
        }
    }
}

enum TextReplacementValidator {
    static let defaultPrefix = "@@"

    static func normalizedPrefix(_ value: String) throws -> String {
        let prefix = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prefix.isEmpty, prefix.count <= 8,
            prefix.unicodeScalars.allSatisfy({ !CharacterSet.whitespacesAndNewlines.contains($0) })
        else { throw TextReplacementValidationError.invalidPrefix }
        return prefix
    }

    static func normalizedRule(
        _ rule: TextReplacementRule, among existing: [TextReplacementRule],
        excluding excludedID: UUID? = nil
    ) throws -> TextReplacementRule {
        let keyword = rule.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty, keyword.count <= 64,
            keyword.unicodeScalars.allSatisfy({ !CharacterSet.whitespacesAndNewlines.contains($0) })
        else { throw TextReplacementValidationError.invalidKeyword }

        guard !rule.replacement.isEmpty else {
            throw TextReplacementValidationError.emptyReplacement
        }
        guard rule.replacement.count <= 10_000 else {
            throw TextReplacementValidationError.replacementTooLong
        }

        let folded = keyword.lowercased()
        for other in existing where other.id != excludedID {
            let otherFolded = other.keyword.lowercased()
            if folded == otherFolded {
                throw TextReplacementValidationError.duplicateKeyword
            }
            if folded.hasPrefix(otherFolded) || otherFolded.hasPrefix(folded) {
                throw TextReplacementValidationError.conflictingKeyword(other.keyword)
            }
        }
        return TextReplacementRule(id: rule.id, keyword: keyword, replacement: rule.replacement)
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

    init(prefix: String, rules: [TextReplacementRule]) {
        triggers = rules.map { rule in
            let source = prefix + rule.keyword
            return Trigger(
                folded: source.lowercased(), source: source, replacement: rule.replacement,
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
