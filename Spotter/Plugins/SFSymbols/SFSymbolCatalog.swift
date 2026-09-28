import Foundation

struct SFSymbolEntry: Decodable, Equatable, Sendable, Identifiable {
    let name: String
    var codepoint: String?
    var availability: [String: [String: String]]?
    var id: String { name }
    var swiftUI: String { "Image(systemName: \"\(name)\")" }
    var minimumMacOS: String? { availability?["monochrome"]?["macOS"] }
}

enum SFSymbolCatalog {
    static let resultLimit = 150

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func decode(_ data: Data) throws -> [SFSymbolEntry] {
        guard data.count <= 4 * 1024 * 1024 else { throw Failure(message: "SF Symbols returned too much data.") }
        let records = try JSONDecoder().decode([SFSymbolEntry].self, from: data)
        guard records.count <= resultLimit else { throw Failure(message: "SF Symbols exceeded the result limit.") }
        var seen = Set<String>()
        return records.filter { validName($0.name) && seen.insert($0.name).inserted }
    }

    static func validName(_ name: String) -> Bool {
        !name.isEmpty && name.utf8.count <= 256 && name.unicodeScalars.allSatisfy {
            $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "." || $0 == "_")
        }
    }

    static func searchArguments(_ query: String) throws -> [String] {
        guard query.count <= 256, !query.utf8.contains(0) else { throw Failure(message: "Use a search of at most 256 characters.") }
        return ["search", "--json", "--limit", String(resultLimit), "--", query.trimmingCharacters(in: .whitespacesAndNewlines)]
    }

    static func argument(_ query: String) -> String? {
        guard query.count <= 256 else { return nil }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["sf symbols ", "sfsymbols ", "sf "] where trimmed.lowercased().hasPrefix(prefix) {
            let argument = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !argument.isEmpty { return argument }
        }
        return nil
    }
}
