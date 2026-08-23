import Foundation

/// One selected Finder item, reduced to the facts the card states. Foundation-only and pure, so
/// `Tools/dashboard-widgets-test.swift` compiles the real summary rules standalone.
struct DashboardFileInfoItem: Equatable, Sendable {
    let path: String
    let name: String
    /// The Finder's own wording — "PNG image", "Application", "Folder".
    let kind: String
    /// Bytes, for the items a size describes: files, and packages the user sees as one file.
    let byteCount: Int64?
    /// Shallow child count, for a plain folder — the one item whose size would have to be crawled for.
    let childCount: Int?
}

/// What the card draws for the current selection: three stacked lines, squared off like every other
/// widget — what kind of thing it is, what it is called, and how big it is.
struct DashboardFileInfoSnapshot: Equatable, Sendable {
    var items: [DashboardFileInfoItem] = []

    var isEmpty: Bool { items.isEmpty }
    /// A multi-item selection borrows the first item's icon, the way a stacked Finder drag does.
    /// Nil with nothing selected, which is what puts the card in its resting state.
    var iconPath: String? { items.first?.path }
    var kindLine: String { DashboardFileInfoSummary.kindLine(for: items) }
    var nameLine: String { DashboardFileInfoSummary.nameLine(for: items) }
    var sizeLine: String { DashboardFileInfoSummary.sizeLine(for: items) }
    /// One spoken sentence, since the three lines are one fact split across a small square.
    var accessibilityLabel: String {
        [kindLine, nameLine, sizeLine].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

enum DashboardFileInfoSummary {
    /// The kind leads a single item; several items have no one kind, so the line names the selection.
    /// With nothing selected the card stays on the strip and names its source instead, since a
    /// widget that came and went with the Finder's selection couldn't be relied on to be there.
    static func kindLine(for items: [DashboardFileInfoItem]) -> String {
        guard let first = items.first else { return "Finder" }
        return items.count == 1 ? first.kind : "Selection"
    }

    static func nameLine(for items: [DashboardFileInfoItem]) -> String {
        guard let first = items.first else { return "No selection" }
        return items.count == 1 ? first.name : count(items.count, singular: "item", plural: "items")
    }

    /// The size, or the count that stands in for one. Empty when neither is known, so the card drops
    /// the line rather than drawing a placeholder.
    static func sizeLine(for items: [DashboardFileInfoItem]) -> String {
        guard !items.isEmpty else { return "" }
        if items.count == 1 {
            let item = items[0]
            if let bytes = item.byteCount { return size(bytes: bytes) }
            guard let children = item.childCount else { return "" }
            return count(children, singular: "item", plural: "items")
        }
        var parts: [String] = []
        let measured = items.compactMap(\.byteCount)
        if !measured.isEmpty { parts.append(size(bytes: measured.reduce(0, +))) }
        // Folders are counted rather than summed, so they are named instead of going silently
        // missing from a total that would otherwise read as the whole selection.
        let folders = items.count - measured.count
        if folders > 0 { parts.append(count(folders, singular: "folder", plural: "folders")) }
        return parts.joined(separator: " · ")
    }

    static func size(bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        return formatter.string(fromByteCount: max(0, bytes))
    }

    private static func count(_ value: Int, singular: String, plural: String) -> String {
        "\(value) \(value == 1 ? singular : plural)"
    }
}
