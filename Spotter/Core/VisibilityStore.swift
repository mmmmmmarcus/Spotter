import Foundation

/// Persists which launcher items the user has hidden (only exclusions are stored); hiding affects the launcher list only, leaving favorites and hotkey bindings intact. There is deliberately no category-level switch: every category is always on, so an item is the only thing that can be hidden.
@MainActor
final class VisibilityStore: ObservableObject {
    private let defaults = UserDefaults.standard
    private let itemsKey = "hiddenLauncherItems"

    @Published private(set) var hiddenItemKeys: Set<String>

    init() {
        hiddenItemKeys = Set(defaults.stringArray(forKey: itemsKey) ?? [])
    }

    /// Replace the exclusion set (used when importing a settings backup).
    func replace(hiddenItems: [String]) {
        hiddenItemKeys = Set(hiddenItems)
        defaults.set(Array(hiddenItemKeys), forKey: itemsKey)
    }

    func key(for entry: AppEntry) -> String { entry.preferenceKey }

    /// Whether the entry appears in the launcher.
    func isVisible(_ entry: AppEntry) -> Bool { isItemVisible(entry) }

    func isItemVisible(_ entry: AppEntry) -> Bool {
        !hiddenItemKeys.contains(key(for: entry))
    }

    func setItemVisible(_ visible: Bool, for entry: AppEntry) {
        let k = key(for: entry)
        if visible { hiddenItemKeys.remove(k) } else { hiddenItemKeys.insert(k) }
        defaults.set(Array(hiddenItemKeys), forKey: itemsKey)
    }

    func removeItemKeys(_ keys: Set<String>) {
        guard !keys.isEmpty else { return }
        let previous = hiddenItemKeys
        hiddenItemKeys.subtract(keys)
        guard hiddenItemKeys != previous else { return }
        defaults.set(Array(hiddenItemKeys), forKey: itemsKey)
    }
}
