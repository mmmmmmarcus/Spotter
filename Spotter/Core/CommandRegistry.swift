import Foundation

/// Turns `CommandID` — which owns the identity and metadata, in `CommandID.swift` — into launcher entries. The split is what lets the command-to-shortcut mapping compile in `Tools/commands-test.swift` without dragging `AppEntry` in.
enum CommandRegistry {
    /// Sorted by name to keep the AppIndex sort invariant; the URL is a placeholder since commands are never launched from disk.
    nonisolated static let all: [AppEntry] =
        CommandID.allCases
        .map { id in
            AppEntry(
                id: id.rawValue, name: id.name,
                url: URL(
                    string: "spotter://" + id.rawValue.replacingOccurrences(of: ":", with: "/"))!,
                bundleID: nil, kind: .command, symbolImage: id.sfSymbol,
                detailLabel: id == .version ? AppVersion.current.short : nil)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    static func command(for entry: AppEntry) -> CommandID? {
        CommandID(rawValue: entry.id)
    }
}
