// Standalone test for File Search's query, scope and exclusion policy. Compiles the real
// FileSearchTypes.swift and the real scorer it ranks with — no copies to keep in sync:
//
//   swiftc -swift-version 6 Spotter/Core/SearchRelevance.swift \
//       Spotter/Plugins/FileSearch/FileSearchTypes.swift Tools/file-search-test.swift \
//       -o /tmp/file-search-test && /tmp/file-search-test
//
// Nothing here touches Spotlight or the filesystem: the policy is pure, which is the whole point of
// keeping it in its own file.

import Foundation

@main
@MainActor
struct FileSearchTests {
    static var failures = 0
    static var passes = 0

    static let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)

    static func main() {
        expressionBuilding()
        structuralExclusions()
        rootItemMatching()
        ranking()
        scopeSelection()
        resultShape()

        print("\(passes)/\(passes + failures) passed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Cases

    static func expressionBuilding() {
        expect(FileSearchQuery.expression(for: "") == nil, "an empty query builds no expression")
        expect(
            FileSearchQuery.expression(for: "   ") == nil, "whitespace alone builds no expression")
        expect(
            FileSearchQuery.expression(for: "report")
                == "kMDItemFSName == \"*report*\"cd",
            "one term becomes one case- and diacritic-insensitive contains")
        expect(
            FileSearchQuery.expression(for: "report 2024")
                == "kMDItemFSName == \"*report*\"cd && kMDItemFSName == \"*2024*\"cd",
            "every term must match, so terms are ANDed")

        // A typed term is literal: a copied `*` must not widen the query Spotlight actually runs.
        expect(
            FileSearchQuery.expression(for: "*")
                == "kMDItemFSName == \"*\\**\"cd", "a typed asterisk is escaped")
        expect(
            FileSearchQuery.expression(for: "a\"b")
                == "kMDItemFSName == \"*a\\\"b*\"cd", "a quote cannot close the string")
        expect(
            FileSearchQuery.expression(for: "a\\b")
                == "kMDItemFSName == \"*a\\\\b*\"cd", "a backslash escapes itself")
        expect(FileSearchQuery.terms(in: " a  b ") == ["a", "b"], "terms collapse whitespace")
    }

    static func structuralExclusions() {
        for path in [
            "/Users/tester/.ssh/config",
            "/Users/tester/Documents/.hidden/notes.txt",
            "/Users/tester/Applications/Thing.app/Contents/Info.plist",
            "/Users/tester/dev/site/node_modules/react/index.js",
            "/Users/tester/Library/Developer/Xcode/DerivedData/App/x.o",
            "/Users/tester/dev/app/build/output.txt",
            "/Users/tester/dev/app/dist/bundle.js",
            "/Users/tester/dev/rust/target/debug/app",
            "/Users/tester/dev/ios/Pods/Alamofire/Source.swift",
        ] {
            expect(FileSearchQuery.isExcludedPath(path), "excluded: \(path)")
        }
        for path in [
            "/Users/tester/Documents/report.pdf",
            "/Users/tester/dev/rebuild/main.swift",
            "/Users/tester/Pictures/2024/photo.heic",
        ] {
            expect(!FileSearchQuery.isExcludedPath(path), "kept: \(path)")
        }
        // "rebuild" contains "build"; only a whole path component counts.
        expect(
            !FileSearchQuery.isExcludedPath("/Users/tester/rebuild/x"),
            "a substring of an ignored name is not an ignored component")
    }

    static func rootItemMatching() {
        expect(
            FileSearchQuery.matches(filename: "Documents", query: "doc"),
            "the top-level match is case-insensitive")
        expect(
            FileSearchQuery.matches(filename: "Résumé.pdf", query: "resume"),
            "and diacritic-insensitive")
        expect(
            FileSearchQuery.matches(filename: "Q4 report final", query: "report final"),
            "every term must appear")
        expect(
            !FileSearchQuery.matches(filename: "Q4 report", query: "report final"),
            "a missing term rejects the file")
    }

    static func ranking() {
        let ranked = FileSearchQuery.rank(
            [
                result("/Users/tester/Documents/quarterly-report-draft.pdf"),
                result("/Users/tester/Documents/report.pdf"),
                result("/Users/tester/dev/app/node_modules/report.js"),
                result("/Users/tester/.trash/report.pdf"),
            ], for: "report")
        expect(
            ranked.map(\.name) == ["report.pdf", "quarterly-report-draft.pdf"],
            "the exact filename leads and excluded paths are dropped, got \(ranked.map(\.name))")

        let multi = FileSearchQuery.rank(
            [
                result("/Users/tester/a/report.pdf"),
                result("/Users/tester/a/report-2024.pdf"),
            ], for: "report 2024")
        expect(
            multi.map(\.name) == ["report-2024.pdf", "report.pdf"],
            "the per-term sum breaks the tie when no name matches the whole query")

        expect(FileSearchQuery.rank([result("/Users/tester/a/x")], for: "  ").isEmpty,
            "a blank query ranks nothing")

        // Published rows are capped even though Spotlight was already capped at candidateLimit.
        let many = (0..<(FileSearchQuery.resultLimit + 50)).map {
            result("/Users/tester/a/report-\($0).pdf")
        }
        expect(
            FileSearchQuery.rank(many, for: "report").count == FileSearchQuery.resultLimit,
            "the published set is capped at resultLimit")

        let once = FileSearchQuery.rank(many, for: "report").map(\.id)
        expect(FileSearchQuery.rank(many, for: "report").map(\.id) == once, "ranking is stable")
    }

    static func scopeSelection() {
        let selection = FileSearchScope.select([
            candidate("Documents", isDirectory: true),
            candidate("Library", isDirectory: true),
            candidate(".config", isDirectory: true, isHidden: true),
            candidate("Notes.rtfd", isDirectory: true, isPackage: true),
            candidate("Xcode.app", isDirectory: true, isPackage: true, isApplication: true),
            candidate("todo.txt", isDirectory: false),
        ])
        expect(
            selection.directories.map(\.lastPathComponent) == ["Documents"],
            "only real visible directories become Spotlight scopes, got "
                + "\(selection.directories.map(\.lastPathComponent))")
        expect(
            selection.rootItems.map { $0.url.lastPathComponent }
                == ["Documents", "Notes.rtfd", "todo.txt"],
            "a package and a loose file are results even though neither is searched inside")
        expect(
            !selection.rootItems.contains { $0.url.lastPathComponent == "Library" },
            "~/Library is never admitted, as a scope or as a result")
    }

    static func resultShape() {
        let inside = result("/Users/tester/Documents/report.pdf")
        expect(inside.name == "report.pdf", "name is the last component")
        expect(inside.parentPath == "~/Documents", "the parent is tilde-abbreviated")
        expect(inside.id == inside.url.path, "the path is the identity")

        expect(result("/Users/tester/todo.txt").parentPath == "~", "home itself abbreviates to ~")
        expect(
            result("/Volumes/Backup/report.pdf").parentPath == "/Volumes/Backup",
            "a path outside home stays absolute")
        // `/Users/tester2` starts with the home path as a *string* but is a different directory.
        expect(
            result("/Users/tester2/report.pdf").parentPath == "/Users/tester2",
            "a sibling home is not abbreviated")
    }

    // MARK: - Helpers

    static func result(_ path: String) -> FileSearchResult {
        FileSearchResult(
            url: URL(fileURLWithPath: path), isDirectory: false, homeDirectory: home)
    }

    static func candidate(
        _ name: String, isDirectory: Bool, isHidden: Bool = false, isPackage: Bool = false,
        isApplication: Bool = false
    ) -> FileSearchScope.Candidate {
        FileSearchScope.Candidate(
            url: home.appendingPathComponent(name), isDirectory: isDirectory, isHidden: isHidden,
            isPackage: isPackage, isApplication: isApplication)
    }

    static func expect(_ condition: Bool, _ label: String) {
        if condition {
            passes += 1
        } else {
            print("FAIL: \(label)")
            failures += 1
        }
    }
}
