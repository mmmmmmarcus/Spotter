import Foundation

/// Stable, persistence-safe identity for a built-in Spotter plugin.
struct PluginID: RawRepresentable, Hashable, Codable, Sendable, Identifiable {
    let rawValue: String
    var id: String { rawValue }

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static let currencyConversion = PluginID(rawValue: "currency-conversion")
    static let clipboard = PluginID(rawValue: "clipboard")
    static let emoji = PluginID(rawValue: "emoji-symbols")
    static let worldClock = PluginID(rawValue: "world-clock")
    static let killProcess = PluginID(rawValue: "kill-process")
    static let changeCase = PluginID(rawValue: "change-case")
    static let imageModification = PluginID(rawValue: "image-modification")
    static let quickTimeRecording = PluginID(rawValue: "quicktime-recording")
}

/// The small fixed palette Settings uses for plugin sidebar icon tiles.
enum PluginTint: String, Sendable {
    case blue, green, orange, purple, red, teal, yellow
}

/// System grants a plugin may use. Consent to a network provider is plugin-owned, not a macOS grant.
enum PluginPermission: String, CaseIterable, Sendable {
    case accessibility
    case automation
}

/// Display-only metadata. Keeping it free of SwiftUI lets permission and backup code inspect plugins.
struct PluginMetadata: Identifiable, Sendable {
    let id: PluginID
    let name: String
    let summary: String
    let systemImage: String
    let tint: PluginTint
}

/// A plugin-owned action that may be assigned a global shortcut.
struct PluginActionKey: Hashable, Sendable {
    let pluginID: PluginID
    let actionID: String
    let title: String
    let defaultsKey: String

    static let openClipboard = PluginActionKey(
        pluginID: .clipboard,
        actionID: "open",
        title: "Clipboard History",
        defaultsKey: "KeyboardShortcuts_toggleClipboard"
    )

    static let openEmoji = PluginActionKey(
        pluginID: .emoji,
        actionID: "open",
        title: "Emoji & Symbols",
        defaultsKey: "KeyboardShortcuts_toggleEmoji"
    )

    static func standard(pluginID: PluginID, actionID: String, title: String) -> PluginActionKey {
        PluginActionKey(
            pluginID: pluginID,
            actionID: actionID,
            title: title,
            defaultsKey: "KeyboardShortcuts_plugin.\(pluginID.rawValue).\(actionID)"
        )
    }
}

/// Generic inline answer returned by a plugin query provider.
struct PluginQueryResult: Equatable, Sendable {
    let pluginID: PluginID
    let sectionTitle: String
    let expression: String
    let sourceBadge: String?
    let targetBadge: String?
    let display: String
    let copyText: String
    let actionTitle: String
}

/// Pure synchronous query hook. Providers should reject unrelated input before doing expensive work.
protocol PluginQueryProvider: Sendable {
    func evaluate(_ query: String, now: Date, calendar: Calendar) -> PluginQueryResult?
}
