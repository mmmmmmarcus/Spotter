import Foundation

struct NoteTombstone: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let deletedAt: Date
}

struct NoteSyncSnapshot: Equatable, Sendable {
    var notes: [SpotterNote]
    var tombstones: [NoteTombstone]

    var notesByID: [UUID: SpotterNote] { Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) }) }
    var tombstonesByID: [UUID: NoteTombstone] {
        Dictionary(uniqueKeysWithValues: tombstones.map { ($0.id, $0) })
    }
}

enum NoteSyncItem: Equatable, Sendable {
    case note(SpotterNote)
    case tombstone(NoteTombstone)

    var id: UUID {
        switch self {
        case .note(let note): note.id
        case .tombstone(let tombstone): tombstone.id
        }
    }

    var modifiedAt: Date {
        switch self {
        case .note(let note): note.updatedAt
        case .tombstone(let tombstone): tombstone.deletedAt
        }
    }
}

enum NoteSyncMerge {
    static func items(in snapshot: NoteSyncSnapshot) -> [UUID: NoteSyncItem] {
        var items = Dictionary(
            uniqueKeysWithValues: snapshot.notes.map { ($0.id, NoteSyncItem.note($0)) })
        for tombstone in snapshot.tombstones {
            let candidate = NoteSyncItem.tombstone(tombstone)
            if let current = items[tombstone.id] {
                items[tombstone.id] = preferred(current, candidate)
            } else {
                items[tombstone.id] = candidate
            }
        }
        return items
    }

    static func snapshot(from items: [UUID: NoteSyncItem]) -> NoteSyncSnapshot {
        var notes: [SpotterNote] = []
        var tombstones: [NoteTombstone] = []
        for item in items.values {
            switch item {
            case .note(let note): notes.append(note)
            case .tombstone(let tombstone): tombstones.append(tombstone)
            }
        }
        notes.sort { $0.contentUpdatedAt > $1.contentUpdatedAt }
        tombstones.sort { $0.deletedAt > $1.deletedAt }
        return NoteSyncSnapshot(notes: notes, tombstones: tombstones)
    }

    static func merging(_ local: NoteSyncSnapshot, with remote: NoteSyncSnapshot) -> NoteSyncSnapshot {
        var merged = items(in: local)
        for (id, candidate) in items(in: remote) {
            if let current = merged[id] {
                merged[id] = preferred(current, candidate)
            } else {
                merged[id] = candidate
            }
        }
        return snapshot(from: merged)
    }

    static func preferred(_ lhs: NoteSyncItem, _ rhs: NoteSyncItem) -> NoteSyncItem {
        if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt > rhs.modifiedAt ? lhs : rhs }
        switch (lhs, rhs) {
        case (.tombstone, .note): return lhs
        case (.note, .tombstone): return rhs
        case (.tombstone(let left), .tombstone(let right)):
            return left.id.uuidString <= right.id.uuidString ? lhs : rhs
        case (.note(let left), .note(let right)):
            if left.content != right.content { return left.content > right.content ? lhs : rhs }
            // Two devices can hold the same text at the same instant under different tints; without
            // a tint step here that pair never converges.
            if left.tint != right.tint {
                return (left.tint?.rawValue ?? "") > (right.tint?.rawValue ?? "") ? lhs : rhs
            }
            if left.createdAt != right.createdAt { return left.createdAt < right.createdAt ? lhs : rhs }
            return left.id.uuidString <= right.id.uuidString ? lhs : rhs
        }
    }
}

// Decode-only bridge for the former user-selected Notes JSON sync file.
struct NoteSyncDocument: Codable, Equatable, Sendable {
    static let supportedVersion = 1

    var version = supportedVersion
    var notes: [SpotterNote]
    var selectedID: UUID?

    enum DecodeError: LocalizedError {
        case unsupportedVersion(Int)

        var errorDescription: String? {
            switch self {
            case .unsupportedVersion(let version):
                "This Notes file was written by a newer Spotter (format \(version))."
            }
        }
    }

    init(notes: [SpotterNote], selectedID: UUID?) {
        self.notes = notes
        self.selectedID = selectedID
    }

    init(json data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(NoteSyncDocument.self, from: data)
        guard decoded.version <= Self.supportedVersion else {
            throw DecodeError.unsupportedVersion(decoded.version)
        }
        self = decoded
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    func encodedOffMain() async throws -> Data {
        let snapshot = self
        return try await Task.detached(priority: .utility) { try snapshot.encoded() }.value
    }

    static func decodedOffMain(_ data: Data) async throws -> NoteSyncDocument {
        try await Task.detached(priority: .utility) { try NoteSyncDocument(json: data) }.value
    }
}
