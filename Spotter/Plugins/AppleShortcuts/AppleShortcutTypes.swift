import Foundation

struct AppleShortcut: Hashable, Identifiable, Sendable {
    static let entryIDPrefix = "command:apple-shortcut:"

    let id: UUID
    let name: String

    var entryID: String { Self.entryIDPrefix + id.uuidString.lowercased() }

    static func parseList(_ output: String) -> [AppleShortcut] {
        var seen: Set<UUID> = []
        return output.split(whereSeparator: \.isNewline)
            .compactMap(parseLine)
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func parseLine(_ line: Substring) -> AppleShortcut? {
        guard line.hasSuffix(")"), let open = line.lastIndex(of: "(") else { return nil }
        let identifier = line[line.index(after: open)..<line.index(before: line.endIndex)]
        let name = line[..<open].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let id = UUID(uuidString: String(identifier)) else { return nil }
        return AppleShortcut(id: id, name: name)
    }
}
