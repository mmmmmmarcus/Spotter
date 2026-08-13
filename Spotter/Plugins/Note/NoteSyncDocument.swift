import Foundation

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
