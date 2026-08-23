import Foundation

/// The user's per-entry launcher aliases — one per entry, keyed by `preferenceKey` like favorites, ranking and visibility. Data, not a capability: an alias grants nothing, it only renames.
@MainActor
final class AliasStore: ObservableObject {
    private let defaults = UserDefaults.standard
    private let defaultsKey = "launcherAliases"

    @Published private(set) var aliases: [String: String]
    /// Bumped on every write. `AppIndex` folds it into its match-cache key, since an edited alias changes a ranking without the query or the app list moving.
    @Published private(set) var revision = 0

    init() {
        aliases = defaults.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
    }

    func alias(for entryKey: String) -> String? { aliases[entryKey] }

    func alias(for entry: AppEntry) -> String? { aliases[entry.preferenceKey] }

    /// Stored as typed — trimming here would eat a space mid-word — but blank when trimmed means removal.
    func setAlias(_ alias: String, for entryKey: String) {
        let value = alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : alias
        guard aliases[entryKey] != value else { return }
        aliases[entryKey] = value
        commit()
    }

    /// Drops aliases for entries that no longer exist — a deleted command's alias would otherwise sit in the table forever.
    func removeKeys(_ keys: Set<String>) {
        let remaining = aliases.filter { !keys.contains($0.key) }
        guard remaining.count != aliases.count else { return }
        aliases = remaining
        commit()
    }

    /// Replace the whole table at once (used when importing a settings backup).
    func replace(_ new: [String: String]) {
        // An import obeys the same rule as typing: blank means none, or it lands unclearable.
        let cleaned = new.filter {
            !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard cleaned != aliases else { return }
        aliases = cleaned
        commit()
    }

    private func commit() {
        revision &+= 1
        defaults.set(aliases, forKey: defaultsKey)
    }
}
