import Foundation

struct PaletteMenuTypeaheadBuffer {
    static let resetInterval: TimeInterval = 0.8

    private(set) var query = ""
    private var lastInput: Date?

    mutating func append(_ characters: String, at now: Date) {
        guard !characters.isEmpty else { return }
        if let lastInput, now.timeIntervalSince(lastInput) >= Self.resetInterval {
            query = ""
        }
        query.append(contentsOf: characters)
        lastInput = now
    }

    mutating func deleteLast() {
        guard !query.isEmpty else { return }
        query.removeLast()
        if query.isEmpty { lastInput = nil }
    }

    mutating func reset() {
        query = ""
        lastInput = nil
    }
}

enum PaletteMenuTypeahead {
    static func bestMatch(query: String, titles: [String]) -> Int? {
        guard !query.isEmpty else { return nil }
        var best: (index: Int, score: Int)?

        for (index, title) in titles.enumerated() {
            guard let score = FuzzyMatch.score(query: query, candidate: title) else { continue }
            if let bestScore = best?.score, score <= bestScore {
                continue
            } else {
                best = (index, score)
            }
        }
        return best?.index
    }
}
