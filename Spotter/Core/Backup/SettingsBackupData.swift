import Foundation

/// The two dependency-free halves of a `SettingsBackup`: every scalar setting, credential and
/// per-plugin preference. Kept out of `SettingsBackup.swift` — which reaches the live stores — so
/// `Tools/settings-sync-test.swift` compiles the real format and pins its JSON contract.
///
/// Enum-backed settings are stored by raw value so the JSON stays legible and forward-compatible (an
/// unknown value is ignored on import rather than failing the whole decode).
struct SettingsBackupData: Codable, Sendable {
    struct DashboardWidgets: Codable, Sendable {
        /// The strip's arrangement. Absent in files written before it was configurable, which
        /// simply leaves the receiving Mac on the default order.
        var widgetOrder: [String]?
        var calendarSourceIdentifier: String?
        var includesAllDayEvents: Bool?
        var clockTimeZoneIdentifier: String?
        // Weather consent travels with the trusted file: restoring one is itself the consent act.
        var weatherEnabled: Bool?
        var weatherCity: Data?
        var weatherUnit: String?
        /// Consent to count input, from before Uptime became a plugin of its own. Read for
        /// files written then; new files carry it in `SettingsBackupPluginPrefs.Uptime` instead.
    }

    var clipboardRetentionDays: Int?
    var clipboardDisabledApps: [String]?
    var launchAtLogin: Bool?
    var hyperKey: String?
    var hyperKeyIncludesShift: Bool?
    var hyperKeyQuickPress: String?
    var hyperKeyReplacesGlyph: Bool?
    var emojiSkinTone: String?
    var showInMenuBar: Bool?
    var showInDock: Bool?
    var popToRootSeconds: Int?
    var compactMode: Bool?
    var showFavoritesInCompactMode: Bool?
    var searchScopes: [String]?
    var openOnCursorScreen: Bool?
    var launcherSectionOrder: [String]?
    var launcherHiddenSections: [String]?
    var preferredTerminal: String?
    var remembersPalettePosition: Bool?
    var lockInputToEnglish: Bool?
    // The key is the OpenRouter gate (owner decision): importing or syncing a file that carries one activates the AI path on this Mac.
    var openRouterAPIKey: String?
    /// The two built-in AI commands' models, from before each command carried its own. Still
    /// written, so an older build reading this file keeps them; only read when the file carries
    /// no `aiCommands`.
    var openRouterDefinitionModel: String?
    var openRouterGrammarModel: String?
    var openRouterChatModel: String?
    var openRouterChatWebSearch: Bool?
    var googleTranslationAPIKey: String?
    /// Decode-only: the separate translation consent toggle is gone, the API key is the gate.
    var googleTranslationEnabled: Bool?
    var googleTranslationTargets: [String]?
    var updateAutoCheckEnabled: Bool?
    // Currency-conversion consent, like the update check: restoring a trusted file is the consent act.
    var currencyRatesEnabled: Bool?
    var dashboardWidgets: DashboardWidgets?
}

/// Per-plugin preferences that live in raw bundle-scoped `UserDefaults`. Gathered as effective values (defaults resolved), so a synced Mac lands on exactly what the source Mac shows.
struct SettingsBackupPluginPrefs: Codable, Sendable {
    struct ChangeCase: Codable, Sendable {
        var source: String?
        var primaryAction: String?
        var preserveCase: Bool?
        var preservePunctuation: Bool?
        var exceptions: String?
        var prefix: String?
        var suffix: String?
        var pinned: [String]?
        var recent: [String]?
        var disabled: [String]?
    }
    struct KillProcess: Codable, Sendable {
        var sort: String?
        var groupApps: Bool?
        var searchPaths: Bool?
        var searchPIDs: Bool?
        var prioritizeApps: Bool?
        var showPID: Bool?
        var showPath: Bool?
        var refreshSeconds: Double?
    }
    struct ImageModification: Codable, Sendable {
        var output: String?
        var format: String?
    }
    struct Screenshot: Codable, Sendable {
        var roundedCorners: Bool?
        var captureScale: String?
        var fileFormat: String?
        var includesWindowShadow: Bool?
        var hidesSpotterWindows: Bool?
        var previewDuration: Double?
    }
    struct SelectionTools: Codable, Sendable {
        /// The two built-in AI commands' prompts, from before commands were records. Still
        /// written for older builds; only read when the file carries no `aiCommands`.
        var definitionPrompt: String?
        var grammarPrompt: String?
    }
    struct Caffeinate: Codable, Sendable {
        var keepsDisplayAwake: Bool?
        var keepsDiskAwake: Bool?
    }
    struct WindowManagement: Codable, Sendable {
        var gap: Int?
        var cycleOnRepeat: Bool?
    }
    struct Mole: Codable, Sendable {
        // A manual path override; harmless across machines — the locator ignores a path that isn't executable there.
        var binaryPath: String?
    }
    struct Note: Codable, Sendable {
        // A file written before Notes moved to a folder carries `iCloudSyncEnabled`. It is
        // neither written nor read now: an old snapshot can never start the dormant CloudKit
        // engine, and the Notes folder is a device-local path that does not travel.
        var windowTransparency: Double?
        var autoWindowSizing: Bool?
    }
    var changeCase: ChangeCase?
    var killProcess: KillProcess?
    var imageModification: ImageModification?
    var screenshot: Screenshot?
    var selectionTools: SelectionTools?
    var caffeinate: Caffeinate?
    var windowManagement: WindowManagement?
    var mole: Mole?
    var note: Note?
    // Decode-only migration from development builds that briefly classified Dashboard as a plugin.
    var dashboardWidgets: SettingsBackupData.DashboardWidgets?
}
