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
    static let textReplacement = PluginID(rawValue: "text-replacement")
    static let emoji = PluginID(rawValue: "emoji-symbols")
    static let worldClock = PluginID(rawValue: "world-clock")
    static let killProcess = PluginID(rawValue: "kill-process")
    static let changeCase = PluginID(rawValue: "change-case")
    static let selectionTools = PluginID(rawValue: "selection-tools")
    static let imageModification = PluginID(rawValue: "image-modification")
    static let note = PluginID(rawValue: "note")
    static let quicklinks = PluginID(rawValue: "quicklinks")
    static let aiChat = PluginID(rawValue: "ai-chat")
    static let commands = PluginID(rawValue: "commands")
    static let mole = PluginID(rawValue: "mole")
    static let coffee = PluginID(rawValue: "coffee")
    static let windowManagement = PluginID(rawValue: "window-management")
    static let dashboardWidgets = PluginID(rawValue: "dashboard-widgets")
    static let screenshot = PluginID(rawValue: "screenshot")
    static let fileSearch = PluginID(rawValue: "file-search")
}

/// The small fixed palette Settings uses for plugin sidebar icon tiles.
enum PluginTint: String, Sendable {
    case blue, cyan, green, orange, purple, red, teal, yellow
}

/// System grants a plugin may use. Consent to a network provider is plugin-owned, not a macOS grant.
enum PluginPermission: String, CaseIterable, Sendable {
    case accessibility
    case automation
    case calendar
    case screenRecording
}

/// Display-only metadata. Keeping it free of SwiftUI lets permission and backup code inspect plugins.
struct PluginMetadata: Identifiable, Sendable {
    let id: PluginID
    let name: String
    let summary: String
    let systemImage: String
    let tint: PluginTint
    var settingsPlacement: PluginSettingsPlacement = .plugin
}

enum PluginSettingsPlacement: Equatable, Sendable {
    case system
    case plugin
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
struct PluginQueryCompanion: Equatable, Sendable {
    let display: String
    let badge: String?
}

struct PluginQueryResult: Equatable, Sendable {
    let pluginID: PluginID
    let sectionTitle: String
    let expression: String
    let sourceBadge: String?
    let targetBadge: String?
    let display: String
    let copyText: String
    let actionTitle: String
    var companion: PluginQueryCompanion?
    var supportsHourlyAdjustment: Bool

    init(
        pluginID: PluginID, sectionTitle: String, expression: String,
        sourceBadge: String?, targetBadge: String?, display: String,
        copyText: String, actionTitle: String,
        companion: PluginQueryCompanion? = nil, supportsHourlyAdjustment: Bool = false
    ) {
        self.pluginID = pluginID
        self.sectionTitle = sectionTitle
        self.expression = expression
        self.sourceBadge = sourceBadge
        self.targetBadge = targetBadge
        self.display = display
        self.copyText = copyText
        self.actionTitle = actionTitle
        self.companion = companion
        self.supportsHourlyAdjustment = supportsHourlyAdjustment
    }
}

/// Pure synchronous query hook. Providers should reject unrelated input before doing expensive work.
protocol PluginQueryProvider: Sendable {
    func evaluate(_ query: String, now: Date, calendar: Calendar) -> PluginQueryResult?
}

/// A palette-screen row icon that stays Foundation-only until the shared SwiftUI list renders it.
enum PluginPaletteIcon: Equatable, Sendable {
    case symbol(String)
    case file(path: String)
}

/// Compact trailing metadata rendered by the shared palette row grammar.
struct PluginPaletteAccessory: Equatable, Sendable {
    let systemImage: String
    let text: String
}

/// One selectable result supplied by a plugin palette screen.
struct PluginPaletteItem: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let icon: PluginPaletteIcon
    var accessories: [PluginPaletteAccessory] = []
    var titleLineLimit: Int? = 1
    var subtitleLineLimit: Int? = 1
    let primaryActionTitle: String
}

/// An immutable screen snapshot; filtering happens in the plugin, rendering and selection stay shared.
struct PluginPaletteSnapshot: Equatable, Sendable {
    let sectionTitle: String
    let items: [PluginPaletteItem]
    var isLoading = false
    var loadingMessage = "Loading…"
    var errorMessage: String?
    let emptyMessage: String
}
