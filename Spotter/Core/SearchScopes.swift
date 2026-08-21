import Foundation

/// The folders (and individual bundles) `AppIndex` scans for applications. Foundation-only and pure so `Tools/scopes-test.swift` can compile it standalone.
enum SearchScopes {
    /// Seeded into `AppSettings.searchScopes` on a fresh install. Order matters: `AppIndex.scan()` dedups by bundle ID and the first hit wins.
    static let defaults: [String] = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        "/System/Applications/Utilities",
        "/System/Library/CoreServices/Applications",
        // Safari and the other cryptex-delivered system apps; `/Applications/Safari.app` is only a symlink, and a hidden one, so `.skipsHiddenFiles` never sees it.
        "/System/Volumes/Preboot/Cryptexes/App/System/Applications",
        // The one user-facing app in CoreServices — the other ~120 bundles there are background agents with no reliable way to tell them apart, so the directory itself is not a default.
        "/System/Library/CoreServices/Finder.app",
        "~/Applications",
    ]

    /// Storage form: tilde-abbreviated and without a trailing slash, so the Settings list reads cleanly and a settings backup stays portable across machines.
    static func abbreviate(_ path: String) -> String {
        let trimmed = trimTrailingSlash(path)
        return (trimmed as NSString).abbreviatingWithTildeInPath
    }

    static func expand(_ path: String) -> String {
        (trimTrailingSlash(path) as NSString).expandingTildeInPath
    }

    /// Abbreviates every path and drops duplicates, preserving order.
    static func normalize(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        return paths.map(abbreviate).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// Every `.app` bundle the scopes point at. The walk descends one subfolder deep, so a vendor folder (`/Applications/Blackmagic Design/DaVinci Resolve.app`) is indexed without being added as its own scope; anything deeper still needs one. Missing or unreadable scopes are skipped.
    static func appBundles(in scopes: [String]) -> [URL] {
        let fm = FileManager.default
        var result: [URL] = []
        for scope in scopes {
            let url = URL(fileURLWithPath: expand(scope))
            if url.pathExtension == "app" {
                if fm.fileExists(atPath: url.path) { result.append(url) }
                continue
            }
            result.append(contentsOf: appBundles(under: url, subfolderDepth: 1))
        }
        return result
    }

    /// One bounded level of descent. An `.app` is always a leaf, so the walk never opens a bundle's own `Contents/` tree looking for helper apps.
    private static func appBundles(under url: URL, subfolderDepth: Int) -> [URL] {
        guard
            let items = try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else { return [] }

        var result: [URL] = []
        for item in items {
            if item.pathExtension == "app" {
                result.append(item)
            } else if subfolderDepth > 0,
                (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            {
                result.append(
                    contentsOf: appBundles(under: item, subfolderDepth: subfolderDepth - 1))
            }
        }
        return result
    }

    private static func trimTrailingSlash(_ path: String) -> String {
        var path = path.trimmingCharacters(in: .whitespaces)
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }
}
