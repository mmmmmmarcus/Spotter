import CoreServices
import Foundation
import UniformTypeIdentifiers

/// The one Spotlight read. Spotter builds, persists and watches no file index of its own, so the
/// launch and idle cost of this feature is zero — nothing here is allocated until a search runs.
enum FileSearchService {
    enum Failure: Error {
        case couldNotCreateQuery
        case couldNotExecuteQuery
    }

    /// Synchronous by design: `MDQueryExecute` cannot be stopped mid-flight, so the caller serializes
    /// these on one worker off the main actor and discards any result its query has outlived.
    nonisolated static func search(
        query rawQuery: String, expression: String, homeDirectory: URL
    ) throws -> [FileSearchResult] {
        let selection = resolveScopes(homeDirectory: homeDirectory)
        // The scope roots themselves are matched here — Spotlight never returns the directory it was handed.
        var results = selection.rootItems.compactMap { candidate -> FileSearchResult? in
            guard
                FileSearchQuery.matches(
                    filename: candidate.url.lastPathComponent, query: rawQuery)
            else { return nil }
            return FileSearchResult(
                url: candidate.url, isDirectory: candidate.isDirectory,
                homeDirectory: homeDirectory)
        }
        guard !selection.directories.isEmpty else {
            return FileSearchQuery.rank(results, for: rawQuery)
        }

        guard let query = MDQueryCreate(nil, expression as CFString, nil, nil) else {
            throw Failure.couldNotCreateQuery
        }
        MDQuerySetSearchScope(query, selection.directories as CFArray, 0)
        MDQuerySetMaxCount(query, FileSearchQuery.candidateLimit)
        guard MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) else {
            throw Failure.couldNotExecuteQuery
        }

        var seen = Set(results.map(\.id))
        for index in 0..<MDQueryGetResultCount(query) {
            guard let rawItem = MDQueryGetResultAtIndex(query, index) else { continue }
            // Decoded to plain values before anything crosses back into actor code.
            let item = Unmanaged<MDItem>.fromOpaque(rawItem).takeUnretainedValue()
            guard let path = MDItemCopyAttribute(item, kMDItemPath) as? String else { continue }
            guard MDItemCopyAttribute(item, kMDItemFSInvisible) as? Bool != true else { continue }

            let contentType = (MDItemCopyAttribute(item, kMDItemContentType) as? String)
                .flatMap(UTType.init)
            // Apps belong to the launcher, which already indexes them properly.
            guard contentType?.conforms(to: .application) != true else { continue }

            let result = FileSearchResult(
                url: URL(fileURLWithPath: path),
                isDirectory: contentType?.conforms(to: .folder) == true,
                homeDirectory: homeDirectory)
            guard seen.insert(result.id).inserted else { continue }
            results.append(result)
        }
        return FileSearchQuery.rank(results, for: rawQuery)
    }

    /// Visible top-level home folders, plus iCloud Drive and whatever cloud providers are installed.
    private nonisolated static func resolveScopes(homeDirectory: URL) -> FileSearchScope.Selection {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .isHiddenKey, .isPackageKey, .contentTypeKey,
        ]
        let urls =
            (try? FileManager.default.contentsOfDirectory(
                at: homeDirectory, includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles])) ?? []
        let candidates = urls.compactMap { url -> FileSearchScope.Candidate? in
            guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
            return FileSearchScope.Candidate(
                url: url,
                isDirectory: values.isDirectory == true,
                isHidden: values.isHidden == true,
                isPackage: values.isPackage == true,
                isApplication: values.contentType?.conforms(to: .application) == true)
        }
        let selection = FileSearchScope.select(candidates)
        var directories = selection.directories + cloudScopes(homeDirectory: homeDirectory)
        var seen = Set<String>()
        directories = directories.filter { seen.insert($0.standardizedFileURL.path).inserted }
        return FileSearchScope.Selection(
            directories: directories, rootItems: selection.rootItems)
    }

    /// The two named exceptions to "`~/Library` is not a scope": both are user documents that only happen to live there.
    private nonisolated static func cloudScopes(homeDirectory: URL) -> [URL] {
        [
            homeDirectory.appending(path: "Library/CloudStorage", directoryHint: .isDirectory),
            homeDirectory.appending(
                path: "Library/Mobile Documents/com~apple~CloudDocs", directoryHint: .isDirectory),
        ]
        .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }
}
