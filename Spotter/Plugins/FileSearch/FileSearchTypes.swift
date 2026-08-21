import Foundation

/// One matched file or folder. Foundation-only and pure, like the rest of this file, so `Tools/file-search-test.swift` compiles the real query, scope and exclusion policy standalone.
struct FileSearchResult: Identifiable, Equatable, Sendable {
    let id: String
    let url: URL
    let name: String
    /// Tilde-abbreviated parent directory, which is what the row draws as its subtitle.
    let parentPath: String
    let isDirectory: Bool

    init(url: URL, isDirectory: Bool, homeDirectory: URL) {
        let url = url.standardizedFileURL
        id = url.path
        self.url = url
        name = url.lastPathComponent
        parentPath = FileSearchScope.abbreviate(
            url.deletingLastPathComponent().path, homeDirectory: homeDirectory)
        self.isDirectory = isDirectory
    }
}

/// Where the search is allowed to look. `~/Library` is never admitted as a general scope — the two cloud providers under it are named individually — which is most of what keeps File Search free of any permission prompt.
enum FileSearchScope {
    /// The visible top-level home items, minus `Library`, minus anything that is itself an app.
    struct Candidate: Sendable {
        let url: URL
        let isDirectory: Bool
        let isHidden: Bool
        let isPackage: Bool
        let isApplication: Bool
    }

    /// Directories Spotlight is pointed at, plus the top-level items matched by name directly — a home folder is itself a result, and Spotlight would never return the scope root it was handed.
    struct Selection: Sendable {
        let directories: [URL]
        let rootItems: [Candidate]
    }

    static func select(_ candidates: [Candidate]) -> Selection {
        var directories: [URL] = []
        var rootItems: [Candidate] = []
        for candidate in candidates
        where !candidate.isHidden && !candidate.isApplication
            && candidate.url.lastPathComponent.caseInsensitiveCompare("Library") != .orderedSame
        {
            rootItems.append(candidate)
            // A package (a .rtfd, an Xcode project) is a result, never a directory to search inside.
            if candidate.isDirectory && !candidate.isPackage {
                directories.append(candidate.url)
            }
        }
        return Selection(directories: directories, rootItems: rootItems)
    }

    static func abbreviate(_ path: String, homeDirectory: URL) -> String {
        let home = homeDirectory.standardizedFileURL.path
        if path == home { return "~" }
        guard path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }
}

enum FileSearchQuery {
    /// Spotlight's own cap, applied before execution. Not a nicety: an uncapped `mdfind` for a one-letter query takes tens of seconds, and `MDQuery` is used instead of `NSMetadataQuery` precisely because it exposes this.
    static let candidateLimit = 1_000
    /// What is published to the palette after ranking.
    static let resultLimit = 200

    /// Directory names whose contents are build output or vendored code — never what a person is looking for, and numerous enough to fill the candidate cap on their own.
    static let ignoredDirectoryNames: Set<String> = [
        "node_modules", "deriveddata", "build", "dist", "target", "pods",
    ]

    static func terms(in query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Every term must appear in the filename; Spotlight ANDs them, so "report 2024" needs both.
    static func expression(for query: String) -> String? {
        let terms = terms(in: query)
        guard !terms.isEmpty else { return nil }
        return terms.map { "kMDItemFSName == \"*\(escape($0))*\"cd" }.joined(separator: " && ")
    }

    /// Ranks Spotlight's bounded candidate set with the launcher's own scorer, so a filename ranks the way an app name would. The whole-query score leads; the per-term sum breaks ties for multi-term queries, then the name and the path.
    static func rank(_ results: [FileSearchResult], for query: String) -> [FileSearchResult] {
        let terms = terms(in: query)
        guard !terms.isEmpty else { return [] }
        return
            results
            .filter { !isExcludedPath($0.id) }
            .map { result in
                let whole = FuzzyMatch.score(query: query, candidate: result.name)
                let perTerm = terms
                    .compactMap { FuzzyMatch.score(query: $0, candidate: result.name) }
                    .reduce(0, +)
                return (result, whole, perTerm)
            }
            .sorted { left, right in
                switch (left.1, right.1) {
                case let (leftScore?, rightScore?) where leftScore != rightScore:
                    return leftScore > rightScore
                case (_?, nil): return true
                case (nil, _?): return false
                default:
                    if left.2 != right.2 { return left.2 > right.2 }
                    let byName = left.0.name.localizedCaseInsensitiveCompare(right.0.name)
                    if byName != .orderedSame { return byName == .orderedAscending }
                    return left.0.id.localizedCaseInsensitiveCompare(right.0.id) == .orderedAscending
                }
            }
            .prefix(resultLimit)
            .map(\.0)
    }

    /// The in-memory filter for the top-level home items, which never go through Spotlight.
    static func matches(filename: String, query: String) -> Bool {
        terms(in: query).allSatisfy { term in
            filename.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    /// Hidden paths and bundle interiors are structural exclusions: staying out of them is what keeps File Search a plain read of the existing index rather than a crawl of everything the user owns.
    static func isExcludedPath(_ path: String) -> Bool {
        path.split(separator: "/").contains { component in
            if component.hasPrefix(".") && component != "." && component != ".." { return true }
            let name = component.lowercased()
            return name.hasSuffix(".app") || ignoredDirectoryNames.contains(name)
        }
    }

    /// A typed term is literal, so its wildcards are neutralized along with the string delimiters — otherwise a copied `*` silently widens the query Spotlight runs.
    private static func escape(_ term: String) -> String {
        var escaped = ""
        for character in term {
            if "\\\"*?".contains(character) { escaped.append("\\") }
            escaped.append(character)
        }
        return escaped
    }
}
