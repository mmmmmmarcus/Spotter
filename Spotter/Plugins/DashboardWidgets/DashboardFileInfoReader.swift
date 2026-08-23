import Foundation

/// Turns the Finder selection into a snapshot, entirely off the main actor: one Apple Event, then a
/// `stat` per selected item.
enum DashboardFileInfoReader {
    /// A package is one item to the user, so it earns a size — the cap is what stops that sum from
    /// walking an unbounded tree for the rare package that is really an archive of a project.
    private static let packageFileLimit = 20_000

    private static let keys: Set<URLResourceKey> = [
        .localizedNameKey, .localizedTypeDescriptionKey, .fileSizeKey, .isDirectoryKey,
        .isPackageKey,
    ]

    static func read() async -> DashboardFileInfoSnapshot {
        let urls = await FinderSelection.selectedURLs()
        guard !urls.isEmpty else { return DashboardFileInfoSnapshot() }
        return await Task.detached(priority: .userInitiated) {
            DashboardFileInfoSnapshot(items: urls.compactMap(item(for:)))
        }.value
    }

    private static func item(for url: URL) -> DashboardFileInfoItem? {
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        let isDirectory = values.isDirectory ?? false
        let isPackage = values.isPackage ?? false
        let name = values.localizedName ?? url.lastPathComponent
        let kind = values.localizedTypeDescription ?? (isDirectory ? "Folder" : "File")
        guard isDirectory else {
            return DashboardFileInfoItem(
                path: url.path, name: name, kind: kind,
                byteCount: values.fileSize.map(Int64.init), childCount: nil)
        }
        guard isPackage else {
            return DashboardFileInfoItem(
                path: url.path, name: name, kind: kind, byteCount: nil,
                childCount: childCount(of: url))
        }
        return DashboardFileInfoItem(
            path: url.path, name: name, kind: kind, byteCount: packageSize(of: url),
            childCount: nil)
    }

    private static func childCount(of url: URL) -> Int? {
        try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ).count
    }

    private static func packageSize(of url: URL) -> Int64? {
        guard
            let enumerator = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
        else { return nil }
        var total: Int64 = 0
        var counted = 0
        for case let child as URL in enumerator {
            counted += 1
            guard counted <= packageFileLimit else { return nil }
            guard
                let values = try? child.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                values.isRegularFile == true, let size = values.fileSize
            else { continue }
            total += Int64(size)
        }
        return total
    }
}
