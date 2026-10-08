import Foundation

enum RaycastImportError: LocalizedError {
    case notRaycastFile
    case incorrectPassphrase
    case corrupt
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .notRaycastFile: "This doesn't look like a Raycast export (.rayconfig)."
        case .incorrectPassphrase: "The passphrase is incorrect, or the export is damaged."
        case .corrupt: "The Raycast export could not be read."
        case .tooLarge: "This Raycast export is too large to import."
        }
    }
}

struct RaycastLibraryImport: Sendable {
    let snippets: [Snippet]
    let quicklinks: [Quicklink]

    static func read(file: URL, passphrase: String) throws -> Self {
        try parse(RaycastDecoder.decrypt(try Data(contentsOf: file), passphrase: passphrase))
    }

    static func parse(_ data: Data) throws -> Self {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RaycastImportError.corrupt
        }
        let snippetValue = (root["snippets"] as? [String: Any])?["snippets"]
        return Self(snippets: parseSnippets(snippetValue), quicklinks: parseQuicklinks(root["quicklinks"]))
    }

    private static func parseSnippets(_ value: Any?) -> [Snippet] {
        guard let rows = value as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let name = trimmed(row["title"]), let content = row["text"] as? String, !content.isEmpty else { return nil }
            return Snippet(name: name, content: content, keyword: trimmed(row["keyword"]))
        }
    }

    private static func parseQuicklinks(_ value: Any?) -> [Quicklink] {
        let root = value as? [String: Any]
        let rows = root?["quicklinks"] as? [[String: Any]] ?? value as? [[String: Any]] ?? []
        var platformPaths: [String: String] = [:]
        for row in root?["openWithPlatforms"] as? [[String: Any]] ?? [] {
            if let id = trimmed(row["id"]), let path = trimmed(row["macos"]) { platformPaths[id] = path }
        }
        return rows.compactMap { row in
            guard let name = trimmed(row["name"]), let link = trimmed(row["link"]) else { return nil }
            let openWith = trimmed(row["openWith"]) ?? trimmed(row["applicationId"])
            let path = openWith.flatMap { $0.hasPrefix("/") ? $0 : platformPaths[$0] }
            return Quicklink(name: name, link: rewriteQueryTokens(link),
                openWithBundleID: path.flatMap { Bundle(url: URL(fileURLWithPath: $0))?.bundleIdentifier })
        }
    }

    static func rewriteQueryTokens(_ link: String) -> String {
        var result = ""
        var position = link.startIndex
        while position < link.endIndex,
            let opening = link[position...].firstIndex(of: "{"),
            let closing = link[link.index(after: opening)...].firstIndex(of: "}") {
            result += link[position..<opening]
            let body = String(link[link.index(after: opening)..<closing])
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            let commandEnd = trimmed.firstIndex(where: { $0.isWhitespace || $0 == "=" || $0 == "|" }) ?? trimmed.endIndex
            result += trimmed[..<commandEnd].lowercased() == "query"
                ? "{argument\(trimmed[commandEnd...])}" : "{\(body)}"
            position = link.index(after: closing)
        }
        result += link[position...]
        return result
    }

    private static func trimmed(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let value = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
