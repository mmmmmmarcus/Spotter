import Foundation

enum ClipboardSemanticEngine {
    static let dimension = 768
    static let modelID = "embeddinggemma-2-bfcd298-llama-v1-clipboard-v1"
    static let maximumItems = 10_000
    static let batchSize = 8

    static func query(_ text: String) -> String {
        "task: search result | query: \(text.prefix(512))"
    }

    static func documents(_ text: String) -> [String] {
        let characters = Array(text.prefix(32_000))
        return stride(from: 0, to: characters.count, by: 1_000).map { start in
            "title: none | text: " + String(characters[start..<min(characters.count, start + 1_200)])
        }
    }

    static func normalized(_ vector: [Float]) -> [Float]? {
        guard vector.count == dimension, vector.allSatisfy(\.isFinite) else { return nil }
        let norm = sqrt(vector.reduce(0.0) { $0 + Double($1) * Double($1) })
        guard norm.isFinite, norm > 0.000001 else { return nil }
        return vector.map { Float(Double($0) / norm) }
    }

    static func ranked(query: [Float], entries: [ClipboardSemanticEntry], limit: Int = 40) -> [UUID] {
        guard let query = normalized(query), limit > 0 else { return [] }
        let scores = entries.compactMap { entry -> (UUID, Float)? in
            let scores = entry.vectors.compactMap { vector -> Float? in
                guard let vector = normalized(vector) else { return nil }
                return zip(query, vector).reduce(Float(0)) { $0 + $1.0 * $1.1 }
            }
            guard let score = scores.max() else { return nil }
            return (entry.id, score)
        }
        // A floor and a best-match window avoid filling a clipboard search with unrelated history.
        let floor = max(Float(0.30), (scores.map(\.1).max() ?? 0) - 0.12)
        return scores.filter { $0.1 >= floor }.sorted {
            $0.1 == $1.1 ? $0.0.uuidString < $1.0.uuidString : $0.1 > $1.1
        }.prefix(limit).map(\.0)
    }
}

struct ClipboardSemanticEntry: Codable, Sendable {
    let id: UUID
    let fingerprint: String
    let vectors: [[Float]]
}

struct ClipboardSemanticSnapshot: Codable, Sendable {
    let model: String
    let entries: [ClipboardSemanticEntry]

    var compatibleEntries: [ClipboardSemanticEntry] {
        guard model == ClipboardSemanticEngine.modelID else { return [] }
        var seen = Set<UUID>()
        return entries.prefix(ClipboardSemanticEngine.maximumItems).filter {
            seen.insert($0.id).inserted && !$0.vectors.isEmpty && $0.vectors.count <= 32
                && $0.vectors.allSatisfy { ClipboardSemanticEngine.normalized($0) != nil }
        }
    }
}
