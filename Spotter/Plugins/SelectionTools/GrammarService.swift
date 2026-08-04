import AppKit
import Foundation

struct SelectionGrammarRawIssue: Equatable, Sendable {
    let location: Int
    let length: Int
    let message: String
    let suggestions: [String]
}

@MainActor
protocol SelectionGrammarChecking {
    func check(_ text: String) async throws -> SelectionGrammarResult
}

@MainActor
struct SystemSelectionGrammarService: SelectionGrammarChecking {
    func check(_ text: String) async throws -> SelectionGrammarResult {
        try Task.checkCancellation()
        let rawIssues = await withCheckedContinuation { continuation in
            let textLength = (text as NSString).length
            NSSpellChecker.shared.requestChecking(
                of: text,
                range: NSRange(location: 0, length: textLength),
                types: NSTextCheckingResult.CheckingType.grammar.rawValue,
                options: nil,
                inSpellDocumentWithTag: 0,
                completionHandler: Self.makeCompletion(
                    textLength: textLength, continuation: continuation))
        }
        try Task.checkCancellation()
        return await Task.detached(priority: .userInitiated) {
            SelectionGrammarResponseMapper.map(originalText: text, rawIssues: rawIssues)
        }.value
    }

    nonisolated private static func decode(
        results: [NSTextCheckingResult], textLength: Int
    ) -> [SelectionGrammarRawIssue] {
        results.flatMap { result -> [SelectionGrammarRawIssue] in
            guard result.resultType == .grammar else { return [] }
            return (result.grammarDetails ?? []).compactMap { detail in
                let relativeRange = (detail[NSGrammarRange] as? NSValue)?.rangeValue
                    ?? NSRange(location: 0, length: result.range.length)
                let absoluteRange = NSRange(
                    location: result.range.location + relativeRange.location,
                    length: relativeRange.length)
                guard absoluteRange.location >= 0, absoluteRange.length >= 0,
                    NSMaxRange(absoluteRange) <= textLength
                else { return nil }

                let message = detail[NSGrammarUserDescription] as? String
                    ?? "Grammar issue"
                let suggestions = detail[NSGrammarCorrections] as? [String] ?? []
                return SelectionGrammarRawIssue(
                    location: absoluteRange.location,
                    length: absoluteRange.length,
                    message: message,
                    suggestions: suggestions)
            }
        }
    }

    /// AppKit invokes this completion on its text-checking queue, so create it outside MainActor isolation before handing the Sendable values back to the awaiting task.
    nonisolated private static func makeCompletion(
        textLength: Int,
        continuation: CheckedContinuation<[SelectionGrammarRawIssue], Never>
    ) -> (Int, [NSTextCheckingResult], NSOrthography, Int) -> Void {
        { _, results, _, _ in
            continuation.resume(returning: decode(results: results, textLength: textLength))
        }
    }
}

enum SelectionGrammarResponseMapper {
    static func map(
        originalText: String, rawIssues: [SelectionGrammarRawIssue]
    ) -> SelectionGrammarResult {
        let source = originalText as NSString
        let validIssues = rawIssues.filter {
            $0.location >= 0 && $0.length >= 0 && $0.location + $0.length <= source.length
        }
        let issues = validIssues.map { issue in
            SelectionGrammarIssue(
                location: issue.location,
                length: issue.length,
                originalText: source.substring(
                    with: NSRange(location: issue.location, length: issue.length)),
                message: issue.message,
                suggestions: issue.suggestions)
        }

        let corrected = NSMutableString(string: originalText)
        var appliedRanges: [NSRange] = []
        for issue in validIssues.sorted(by: { $0.location > $1.location }) {
            guard let suggestion = issue.suggestions.first, !suggestion.isEmpty else { continue }
            let range = NSRange(location: issue.location, length: issue.length)
            guard !appliedRanges.contains(where: { NSIntersectionRange($0, range).length > 0 }) else {
                continue
            }
            corrected.replaceCharacters(in: range, with: suggestion)
            appliedRanges.append(range)
        }

        return SelectionGrammarResult(
            originalText: originalText,
            correctedText: corrected as String,
            issues: issues)
    }
}
