import Foundation

enum ClipboardShortcutMigration {
    static let marker = "clipboard.quick-history-default-migrated"

    static func apply(defaults: UserDefaults, legacyKey: String, quickKey: String, legacyUsesDefault: Bool) {
        guard !defaults.bool(forKey: marker) else { return }
        defer { defaults.set(true, forKey: marker) }
        guard legacyUsesDefault, defaults.object(forKey: quickKey) == nil,
            let binding = defaults.string(forKey: legacyKey) else { return }
        // Runs before hotkey registration, so the old action never competes for the transferred chord.
        defaults.set(binding, forKey: quickKey)
        defaults.removeObject(forKey: legacyKey)
    }
}
