import Foundation

/// A human-readable snapshot of Spotter's settings and content. Every field is optional so a manual import remains a non-destructive merge, while automatic sync treats a v3 snapshot as authoritative.
struct SettingsBackup: Codable, Sendable {
    var version = 3
    var settings: SettingsData?
    var hotkeys: HotkeyBackup?
    var customCommands: [CustomCommand]?
    var favoriteApps: [String]?
    var hiddenLauncherItems: [String]?
    /// Decode-only: a file written while launcher categories could be hidden wholesale. Every
    /// category is always on now, so the field is read and ignored rather than restoring a hidden one.
    var hiddenLauncherKinds: [String]?
    /// Per-entry launcher aliases, keyed by `preferenceKey`. Data, not a capability — an alias grants nothing, so it rides an untrusted restore like favorites do.
    var launcherAliases: [String: String]?
    var pluginStates: [String: Bool]?
    var pluginPrefs: PluginPrefs?
    var worldClockCities: [String]?
    var quicklinks: [Quicklink]?
    var textReplacement: TextReplacementBackup?
    var notes: NotesBackup?
    var clipboardHistory: [ClipboardSyncItem]?
    var calculatorHistory: [CalcHistoryEntry]?
    var aiChat: AIChatBackup?
    var backgroundTasks: [BackgroundTaskItem]?
    var frequentEmoji: [FrequentEmoji]?
    var launcherRanking: [LauncherRankingRecord]?

    /// Enum-backed settings are stored by raw value so the JSON stays legible and forward-compatible (an unknown value is ignored on import rather than failing the whole decode).
    struct SettingsData: Codable, Sendable {
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
            /// files written then; new files carry it in `PluginPrefs.Uptime` instead.
            var uptimeEnabled: Bool?
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
        var remembersPalettePosition: Bool?
        var lockInputToEnglish: Bool?
        // The key is the OpenRouter gate (owner decision): importing or syncing a file that carries one activates the AI path on this Mac.
        var openRouterAPIKey: String?
        var openRouterDefinitionModel: String?
        var openRouterGrammarModel: String?
        var openRouterChatModel: String?
        var openRouterChatWebSearch: Bool?
        var googleTranslationAPIKey: String?
        /// Decode-only: the separate translation consent toggle is gone, the API key is the gate.
        var googleTranslationEnabled: Bool?
        var googleTranslationTargets: [String]?
        var updateAutoCheckEnabled: Bool?
        var dashboardWidgets: DashboardWidgets?
    }

    struct HotkeyBackup: Codable, Sendable {
        var togglePalette: HotKeyBinding?
        var togglePaletteBackup: HotKeyBinding?
        // Legacy per-action fields, read on import only; `pluginActions` supersedes both on export.
        var toggleClipboard: HotKeyBinding?
        var toggleEmoji: HotKeyBinding?
        var apps: [String: HotKeyBinding]?
        var panes: [String: HotKeyBinding]?
        var customCommands: [String: HotKeyBinding]?
        /// Spotter's own built-in commands, keyed by `CommandID.rawValue`.
        var builtInCommands: [String: HotKeyBinding]?
        /// Per-quicklink bindings, keyed by quicklink UUID like `customCommands`.
        var quicklinks: [String: HotKeyBinding]?
        /// Every bound plugin shortcut, keyed `<plugin-id>.<action-id>` — new plugins sync automatically.
        var pluginActions: [String: HotKeyBinding]?
    }

    /// Per-plugin preferences that live in raw bundle-scoped `UserDefaults`. Gathered as effective values (defaults resolved), so a synced Mac lands on exactly what the source Mac shows.
    struct PluginPrefs: Codable, Sendable {
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
        struct OnePassword: Codable, Sendable {
            var cliPath: String?
            var primaryAction: String?
            var clearClipboard: Bool?
            var passwordLength: Int?
            var passwordDigits: Bool?
            var passwordSymbols: Bool?
        }
        struct Uptime: Codable, Sendable {
            // Consent travels with the trusted file: restoring one is itself the consent act. The
            // tallies themselves stay device-local.
            var enabled: Bool?
        }
        struct Note: Codable, Sendable {
            var iCloudSyncEnabled: Bool?
            var windowTransparency: Double?
        }
        var changeCase: ChangeCase?
        var killProcess: KillProcess?
        var imageModification: ImageModification?
        var screenshot: Screenshot?
        var selectionTools: SelectionTools?
        var caffeinate: Caffeinate?
        var windowManagement: WindowManagement?
        var mole: Mole?
        var onePassword: OnePassword?
        var note: Note?
        var uptime: Uptime?
        // Decode-only migration from development builds that briefly classified Dashboard as a plugin.
        var dashboardWidgets: SettingsData.DashboardWidgets?
    }

    struct TextReplacementBackup: Codable, Sendable {
        var prefix: String?
        var rules: [TextReplacementRule]?
    }

    struct NotesBackup: Codable, Sendable {
        var notes: [SpotterNote]
        var selectedID: UUID?
    }

    struct AIChatBackup: Codable, Sendable {
        var sessions: [AIChatSession]
        var currentID: UUID?
    }

    enum ApplyMode: Sendable {
        case merge
        case replace
    }

    enum NoteTransfer: Sendable {
        case include
        case exclude
    }

    /// A tally of what an import touched, for user-facing confirmation.
    struct ApplySummary: Sendable {
        var settingsFields = 0
        var hotkeys = 0
        var favorites = 0
        var hiddenItems = 0
        var launcherAliases = 0
        var customCommands = 0
        var plugins = 0
        var contentCollections = 0
    }
}

// MARK: - Gather / apply (main-actor: reads and writes the live stores)

@MainActor
extension SettingsBackup {
    static func gather(
        from core: AppCore = .shared, notes noteTransfer: NoteTransfer = .include
    ) async -> SettingsBackup {
        let s = core.settings
        let dashboard = core.dashboardWidgets.preferences
        var backup = SettingsBackup()
        backup.settings = SettingsData(
            clipboardRetentionDays: s.clipboardRetention.rawValue,
            clipboardDisabledApps: s.clipboardDisabledApps,
            launchAtLogin: s.launchAtLogin,
            hyperKey: s.hyperKey.rawValue,
            hyperKeyIncludesShift: s.hyperKeyIncludesShift,
            hyperKeyQuickPress: s.hyperKeyQuickPress.rawValue,
            hyperKeyReplacesGlyph: s.hyperKeyReplacesGlyph,
            emojiSkinTone: s.emojiSkinTone.rawValue,
            showInMenuBar: UserDefaults.standard.object(forKey: SettingsKey.showInMenuBar) as? Bool
                ?? true,
            showInDock: s.showInDock,
            popToRootSeconds: s.popToRootTimeout.rawValue,
            compactMode: s.compactMode,
            showFavoritesInCompactMode: s.showFavoritesInCompactMode,
            searchScopes: s.searchScopes,
            openOnCursorScreen: s.openOnCursorScreen,
            remembersPalettePosition: s.remembersPalettePosition,
            lockInputToEnglish: s.lockInputToEnglish,
            openRouterAPIKey: core.openRouter.apiKey,
            openRouterDefinitionModel: core.openRouter.definitionModel,
            openRouterGrammarModel: core.openRouter.grammarModel,
            openRouterChatModel: core.openRouter.chatModel,
            openRouterChatWebSearch: core.openRouter.chatWebSearch,
            googleTranslationAPIKey: core.selectionTools.apiKey,
            googleTranslationTargets: core.selectionTools.targetCodes,
            updateAutoCheckEnabled: core.updates.autoCheckEnabled,
            dashboardWidgets: SettingsData.DashboardWidgets(
                widgetOrder: dashboard.widgetOrder.map(\DashboardWidgetKind.rawValue),
                calendarSourceIdentifier: dashboard.calendarSourceIdentifier ?? "",
                includesAllDayEvents: dashboard.includesAllDayEvents,
                clockTimeZoneIdentifier: dashboard.clockTimeZoneIdentifier ?? "",
                weatherEnabled: core.dashboardWeather.isEnabled,
                weatherCity: core.dashboardWeather.encodedCity,
                weatherUnit: core.dashboardWeather.unit.rawValue,
                uptimeEnabled: nil))

        let hk = core.hotKeys
        var hotkeys = HotkeyBackup()
        hotkeys.togglePalette = hk.binding(for: .togglePalette)
        hotkeys.togglePaletteBackup = hk.binding(for: .togglePaletteBackup)
        // Covers every plugin action, clipboard/emoji included — their legacy fields are import-only now.
        hotkeys.pluginActions = Dictionary(
            uniqueKeysWithValues: core.plugins.shortcutActions.compactMap { key in
                hk.binding(for: .plugin(key)).map {
                    ("\(key.pluginID.rawValue).\(key.actionID)", $0)
                }
            })
        hotkeys.apps = Dictionary(
            uniqueKeysWithValues: hk.boundBundleIDs.compactMap { id in
                hk.binding(for: .app(bundleID: id)).map { (id, $0) }
            })
        hotkeys.panes = Dictionary(
            uniqueKeysWithValues: hk.boundPaneBundleIDs.compactMap { id in
                hk.binding(for: .settingsPane(bundleID: id)).map { (id, $0) }
            })
        hotkeys.customCommands = Dictionary(
            uniqueKeysWithValues: hk.boundCustomCommandIDs.compactMap { id in
                hk.binding(for: .customCommand(id: id)).map { (id.uuidString.lowercased(), $0) }
            })
        hotkeys.builtInCommands = Dictionary(
            uniqueKeysWithValues: CommandID.allCases.compactMap { id in
                hk.binding(for: .builtInCommand(id)).map { (id.rawValue, $0) }
            })
        hotkeys.quicklinks = Dictionary(
            uniqueKeysWithValues: hk.boundQuicklinkIDs.compactMap { id in
                hk.binding(for: .quicklink(id: id)).map { (id.uuidString.lowercased(), $0) }
            })
        backup.hotkeys = hotkeys

        backup.customCommands = core.customCommands.commands
        backup.favoriteApps = core.favorites.keys
        backup.hiddenLauncherItems = core.visibility.hiddenItemKeys.sorted()
        backup.launcherAliases = core.aliases.aliases
        backup.pluginStates = core.plugins.exportedEnabledStates()
        backup.pluginPrefs = gatherPluginPrefs(from: core)
        backup.worldClockCities = core.worldClock.cityIDs
        backup.quicklinks = core.quicklinks.sorted
        backup.textReplacement = TextReplacementBackup(
            prefix: core.textReplacements.prefix,
            rules: core.textReplacements.rules)
        if case .include = noteTransfer {
            backup.notes = NotesBackup(notes: core.notes.notes, selectedID: core.notes.selectedID)
        }
        backup.clipboardHistory = await core.clipboardStore.syncSnapshot()
        backup.calculatorHistory = core.calcHistory.entries
        backup.aiChat = AIChatBackup(
            sessions: core.aiChat.sessions, currentID: core.aiChat.currentID)
        backup.backgroundTasks = core.backgroundTasks.tasks
        backup.frequentEmoji = core.frequentEmoji.records
        backup.launcherRanking = core.launcherRanking.records
        return backup
    }

    /// Effective values, resolved with the same defaults their settings views use, so an export never carries "unset" holes.
    private static func gatherPluginPrefs(from core: AppCore) -> PluginPrefs {
        let d = UserDefaults.standard
        var prefs = PluginPrefs()
        prefs.changeCase = PluginPrefs.ChangeCase(
            source: d.string(forKey: "change-case.source")
                ?? ChangeCaseInputSource.selectedText.rawValue,
            primaryAction: d.string(forKey: "change-case.primary-action")
                ?? ChangeCasePrimaryAction.paste.rawValue,
            preserveCase: d.object(forKey: "change-case.preserve-case") == nil
                || d.bool(forKey: "change-case.preserve-case"),
            preservePunctuation: d.bool(forKey: "change-case.preserve-punctuation"),
            exceptions: d.string(forKey: "change-case.exceptions")
                ?? "iOS, iPadOS, iPhone, macOS, tvOS, watchOS",
            prefix: d.string(forKey: "change-case.prefix") ?? "",
            suffix: d.string(forKey: "change-case.suffix") ?? "",
            pinned: d.stringArray(forKey: "change-case.pinned") ?? [],
            recent: d.stringArray(forKey: "change-case.recent") ?? [],
            disabled: d.stringArray(forKey: "change-case.disabled") ?? [])
        prefs.killProcess = PluginPrefs.KillProcess(
            sort: d.string(forKey: "kill-process.sort") ?? ProcessSort.cpu.rawValue,
            groupApps: d.object(forKey: "kill-process.group-apps") == nil
                || d.bool(forKey: "kill-process.group-apps"),
            searchPaths: d.bool(forKey: "kill-process.search-paths"),
            searchPIDs: d.object(forKey: "kill-process.search-pids") == nil
                || d.bool(forKey: "kill-process.search-pids"),
            prioritizeApps: d.object(forKey: "kill-process.prioritize-apps") == nil
                || d.bool(forKey: "kill-process.prioritize-apps"),
            showPID: d.object(forKey: "kill-process.show-pid") == nil
                || d.bool(forKey: "kill-process.show-pid"),
            showPath: d.bool(forKey: "kill-process.show-path"),
            refreshSeconds: d.object(forKey: "kill-process.refresh-seconds") == nil
                ? 2.0 : d.double(forKey: "kill-process.refresh-seconds"))
        prefs.imageModification = PluginPrefs.ImageModification(
            output: d.string(forKey: "image-modification.output")
                ?? ImageOutputLocation.alongside.rawValue,
            format: d.string(forKey: "image-modification.format") ?? ImageFormat.png.rawValue)
        prefs.screenshot = PluginPrefs.Screenshot(
            roundedCorners: core.screenshot.roundedCorners,
            captureScale: core.screenshot.captureScale.rawValue,
            fileFormat: core.screenshot.fileFormat.rawValue,
            includesWindowShadow: core.screenshot.includesWindowShadow,
            hidesSpotterWindows: core.screenshot.hidesSpotterWindows,
            previewDuration: core.screenshot.previewDuration)
        prefs.selectionTools = PluginPrefs.SelectionTools(
            definitionPrompt: core.aiChat.definitionPrompt,
            grammarPrompt: core.aiChat.grammarPrompt)
        prefs.caffeinate = PluginPrefs.Caffeinate(
            keepsDisplayAwake: d.object(forKey: "coffee.keeps-display-awake") == nil
                || d.bool(forKey: "coffee.keeps-display-awake"),
            keepsDiskAwake: d.bool(forKey: "coffee.keeps-disk-awake"))
        prefs.windowManagement = PluginPrefs.WindowManagement(
            gap: d.integer(forKey: WindowManagementDefaults.gapKey),
            cycleOnRepeat: d.bool(forKey: WindowManagementDefaults.cycleKey))
        prefs.mole = PluginPrefs.Mole(binaryPath: d.string(forKey: "mole.binary-path") ?? "")
        prefs.onePassword = PluginPrefs.OnePassword(
            cliPath: core.onePassword.binaryPathOverride,
            primaryAction: d.string(forKey: OnePasswordManager.primaryActionKey)
                ?? OnePasswordItemAction.view.rawValue,
            clearClipboard: d.object(forKey: OnePasswordManager.clearClipboardKey) == nil
                || d.bool(forKey: OnePasswordManager.clearClipboardKey),
            passwordLength: d.object(forKey: OnePasswordManager.passwordLengthKey) == nil
                ? 20 : d.integer(forKey: OnePasswordManager.passwordLengthKey),
            passwordDigits: d.object(forKey: OnePasswordManager.passwordDigitsKey) == nil
                || d.bool(forKey: OnePasswordManager.passwordDigitsKey),
            passwordSymbols: d.object(forKey: OnePasswordManager.passwordSymbolsKey) == nil
                || d.bool(forKey: OnePasswordManager.passwordSymbolsKey))
        prefs.uptime = PluginPrefs.Uptime(enabled: core.uptime.isEnabled)
        prefs.note = PluginPrefs.Note(
            iCloudSyncEnabled: core.noteSync.isEnabled,
            windowTransparency: core.notes.windowTransparency)
        return prefs
    }

    @discardableResult
    func apply(
        to core: AppCore = .shared, mode: ApplyMode = .merge,
        notes noteTransfer: NoteTransfer = .include
    ) async -> ApplySummary {
        var summary = ApplySummary()
        if let s = settings {
            summary.settingsFields = applySettings(s, to: core, mode: mode)
        }
        if let pluginStates {
            summary.plugins = core.plugins.applyEnabledStates(pluginStates)
        }
        if let customCommands {
            summary.customCommands = core.replaceCustomCommands(customCommands)
        }
        // Before `hotkeys`, like custom commands above: a per-quicklink binding only applies to a quicklink that already exists.
        if let quicklinks {
            core.quicklinks.replace(with: quicklinks)
            summary.settingsFields += 1
        }
        if let hotkeys { summary.hotkeys = applyHotkeys(hotkeys, to: core, mode: mode) }
        if let favoriteApps {
            core.favorites.replace(keys: favoriteApps)
            summary.favorites = favoriteApps.count
        }
        if let hiddenLauncherItems {
            core.visibility.replace(hiddenItems: hiddenLauncherItems)
            summary.hiddenItems = hiddenLauncherItems.count
        }
        if let launcherAliases {
            core.aliases.replace(launcherAliases)
            summary.launcherAliases = launcherAliases.count
        }
        if let pluginPrefs {
            summary.settingsFields += Self.applyPluginPrefs(pluginPrefs, to: core)
        }
        if let worldClockCities {
            core.worldClock.replace(cityIDs: worldClockCities)
            summary.settingsFields += 1
        }
        if let textReplacement {
            core.textReplacements.replace(
                prefix: textReplacement.prefix, rules: textReplacement.rules ?? [])
            summary.settingsFields += 1
        }
        if case .include = noteTransfer, let notes {
            core.notes.replace(notes: notes.notes, selectedID: notes.selectedID)
            summary.contentCollections += 1
        }
        if let enabled = pluginPrefs?.note?.iCloudSyncEnabled {
            core.noteSync.setEnabled(enabled)
            summary.settingsFields += 1
        }
        if let clipboardHistory {
            await core.clipboardStore.replace(with: clipboardHistory)
            summary.contentCollections += 1
        }
        if let calculatorHistory {
            core.calcHistory.replace(entries: calculatorHistory)
            summary.contentCollections += 1
        }
        if let aiChat, core.aiChat.replace(sessions: aiChat.sessions, currentID: aiChat.currentID) {
            summary.contentCollections += 1
        }
        if let backgroundTasks {
            core.backgroundTasks.replace(tasks: backgroundTasks)
            summary.contentCollections += 1
        }
        if let frequentEmoji {
            core.frequentEmoji.replace(records: frequentEmoji)
            summary.contentCollections += 1
        }
        if let launcherRanking {
            core.launcherRanking.replace(records: launcherRanking)
            summary.contentCollections += 1
        }
        return summary
    }

    private static func applyPluginPrefs(_ prefs: PluginPrefs, to core: AppCore) -> Int {
        let d = UserDefaults.standard
        var count = 0
        func set(_ value: Any?, _ key: String) {
            guard let value else { return }
            d.set(value, forKey: key)
            count += 1
        }
        if let c = prefs.changeCase {
            set(c.source, "change-case.source")
            set(c.primaryAction, "change-case.primary-action")
            set(c.preserveCase, "change-case.preserve-case")
            set(c.preservePunctuation, "change-case.preserve-punctuation")
            set(c.exceptions, "change-case.exceptions")
            set(c.prefix, "change-case.prefix")
            set(c.suffix, "change-case.suffix")
            set(c.pinned, "change-case.pinned")
            set(c.recent, "change-case.recent")
            set(c.disabled, "change-case.disabled")
            // Pinned/recent are cached as `@Published` state; re-read so the browser reflects the import without a relaunch.
            core.changeCase.reloadPersisted()
        }
        if let k = prefs.killProcess {
            set(k.sort, "kill-process.sort")
            set(k.groupApps, "kill-process.group-apps")
            set(k.searchPaths, "kill-process.search-paths")
            set(k.searchPIDs, "kill-process.search-pids")
            set(k.prioritizeApps, "kill-process.prioritize-apps")
            set(k.showPID, "kill-process.show-pid")
            set(k.showPath, "kill-process.show-path")
            set(k.refreshSeconds, "kill-process.refresh-seconds")
        }
        if let i = prefs.imageModification {
            set(i.output, "image-modification.output")
            set(i.format, "image-modification.format")
        }
        if let roundedCorners = prefs.screenshot?.roundedCorners {
            core.screenshot.roundedCorners = roundedCorners
            count += 1
        }
        if let scale = prefs.screenshot?.captureScale
            .flatMap(ScreenshotCaptureScale.init(rawValue:))
        {
            core.screenshot.captureScale = scale
            count += 1
        }
        if let format = prefs.screenshot?.fileFormat
            .flatMap(ScreenshotFileFormat.init(rawValue:))
        {
            core.screenshot.fileFormat = format
            count += 1
        }
        if let shadow = prefs.screenshot?.includesWindowShadow {
            core.screenshot.includesWindowShadow = shadow
            count += 1
        }
        if let duration = prefs.screenshot?.previewDuration {
            core.screenshot.previewDuration = ScreenshotManager.clampPreviewDuration(duration)
        }
        if let hides = prefs.screenshot?.hidesSpotterWindows {
            core.screenshot.hidesSpotterWindows = hides
            count += 1
        }
        if let selection = prefs.selectionTools {
            if let prompt = selection.definitionPrompt {
                core.aiChat.setDefinitionPrompt(prompt)
                count += 1
            }
            if let prompt = selection.grammarPrompt {
                core.aiChat.setGrammarPrompt(prompt)
                count += 1
            }
        }
        if let c = prefs.caffeinate {
            // Through the manager, not raw defaults: options are cached `@Published` state, and a
            // live caffeinate session restarts so the imported flags actually apply.
            var options = core.coffee.options
            if let display = c.keepsDisplayAwake { options.keepsDisplayAwake = display }
            if let disk = c.keepsDiskAwake { options.keepsDiskAwake = disk }
            if options != core.coffee.options {
                core.coffee.options = options
                count += 1
            }
        }
        if let w = prefs.windowManagement {
            set(w.gap, WindowManagementDefaults.gapKey)
            set(w.cycleOnRepeat, WindowManagementDefaults.cycleKey)
        }
        if let m = prefs.mole, let path = m.binaryPath {
            // Through the manager so `binaryPath` re-resolves; an empty string clears the override.
            core.mole.setBinaryPathOverride(path)
            count += 1
        }
        if let p = prefs.onePassword {
            if let path = p.cliPath {
                core.onePassword.setBinaryPathOverride(path)
                count += 1
            }
            set(p.primaryAction, OnePasswordManager.primaryActionKey)
            set(p.clearClipboard, OnePasswordManager.clearClipboardKey)
            set(p.passwordLength, OnePasswordManager.passwordLengthKey)
            set(p.passwordDigits, OnePasswordManager.passwordDigitsKey)
            set(p.passwordSymbols, OnePasswordManager.passwordSymbolsKey)
        }
        if let transparency = prefs.note?.windowTransparency {
            core.notes.setWindowTransparency(transparency)
            count += 1
        }
        if let dashboard = prefs.dashboardWidgets {
            count += core.dashboardWidgets.applyPreferences(
                widgetOrderRawValues: dashboard.widgetOrder,
                calendarSourceIdentifier: dashboard.calendarSourceIdentifier,
                includesAllDayEvents: dashboard.includesAllDayEvents,
                clockTimeZoneIdentifier: dashboard.clockTimeZoneIdentifier)
            count += core.dashboardWeather.applyPreferences(
                enabled: dashboard.weatherEnabled, cityData: dashboard.weatherCity,
                unitRawValue: dashboard.weatherUnit)
        }
        // Uptime's own field wins; the widget-era field is the fallback for files written before it
        // became a plugin, so restoring an older snapshot still carries the user's consent across.
        count += core.uptime.applyPreferences(
            enabled: prefs.uptime?.enabled ?? prefs.dashboardWidgets?.uptimeEnabled)
        return count
    }

    private func applySettings(_ s: SettingsData, to core: AppCore, mode: ApplyMode) -> Int {
        let settings = core.settings
        var count = 0
        if let days = s.clipboardRetentionDays, let retention = ClipboardRetention(rawValue: days) {
            settings.clipboardRetention = retention
            core.clipboardStore.maxAge = retention.maxAge
            core.clipboardStore.enforceLimits()
            count += 1
        }
        if let apps = s.clipboardDisabledApps {
            settings.clipboardDisabledApps = apps
            count += 1
        }
        if let launch = s.launchAtLogin {
            settings.launchAtLogin = launch
            count += 1
        }
        if let raw = s.hyperKey, let key = HyperKeyPhysicalKey(rawValue: raw) {
            settings.hyperKey = key
            count += 1
        }
        if let flag = s.hyperKeyIncludesShift {
            settings.hyperKeyIncludesShift = flag
            count += 1
        }
        if let raw = s.hyperKeyQuickPress, let quick = HyperKeyQuickPress(rawValue: raw) {
            settings.hyperKeyQuickPress = quick
            count += 1
        }
        if let flag = s.hyperKeyReplacesGlyph {
            settings.hyperKeyReplacesGlyph = flag
            count += 1
        }
        if let raw = s.emojiSkinTone, let tone = EmojiSkinTone(rawValue: raw) {
            settings.emojiSkinTone = tone
            count += 1
        }
        if let show = s.showInMenuBar {
            UserDefaults.standard.set(show, forKey: SettingsKey.showInMenuBar)
            count += 1
        }
        if let show = s.showInDock {
            settings.showInDock = show
            count += 1
        }
        if let secs = s.popToRootSeconds, let timeout = PopToRootTimeout(rawValue: secs) {
            settings.popToRootTimeout = timeout
            count += 1
        }
        if let flag = s.compactMode {
            settings.compactMode = flag
            count += 1
        }
        if let flag = s.showFavoritesInCompactMode {
            settings.showFavoritesInCompactMode = flag
            count += 1
        }
        if let scopes = s.searchScopes {
            settings.searchScopes = SearchScopes.normalize(scopes)
            count += 1
        }
        if let flag = s.openOnCursorScreen {
            settings.openOnCursorScreen = flag
            count += 1
        }
        if let flag = s.remembersPalettePosition {
            settings.remembersPalettePosition = flag
            count += 1
        }
        if let flag = s.lockInputToEnglish {
            settings.lockInputToEnglish = flag
            count += 1
        }
        if let key = s.openRouterAPIKey {
            core.openRouter.setAPIKey(key)
            count += 1
        } else if mode == .replace && version >= 3 {
            core.openRouter.setAPIKey("")
            count += 1
        }
        if let model = s.openRouterDefinitionModel {
            core.openRouter.setDefinitionModel(model)
            count += 1
        }
        if let model = s.openRouterGrammarModel {
            core.openRouter.setGrammarModel(model)
            count += 1
        }
        if let model = s.openRouterChatModel {
            core.openRouter.setChatModel(model)
            count += 1
        }
        if let webSearch = s.openRouterChatWebSearch {
            core.openRouter.setChatWebSearch(webSearch)
            count += 1
        }
        if let key = s.googleTranslationAPIKey {
            core.selectionTools.setAPIKey(key)
            count += 1
        } else if mode == .replace && version >= 3 {
            core.selectionTools.setAPIKey("")
            count += 1
        }
        if let targets = s.googleTranslationTargets {
            core.selectionTools.setTargets(targets)
            count += 1
        }
        if let enabled = s.updateAutoCheckEnabled {
            core.updates.setAutoCheck(enabled)
            count += 1
        }
        if let dashboard = s.dashboardWidgets {
            count += core.dashboardWidgets.applyPreferences(
                widgetOrderRawValues: dashboard.widgetOrder,
                calendarSourceIdentifier: dashboard.calendarSourceIdentifier,
                includesAllDayEvents: dashboard.includesAllDayEvents,
                clockTimeZoneIdentifier: dashboard.clockTimeZoneIdentifier)
            count += core.dashboardWeather.applyPreferences(
                enabled: dashboard.weatherEnabled, cityData: dashboard.weatherCity,
                unitRawValue: dashboard.weatherUnit)
        }
        // The widget-era field, for files written before Uptime became a plugin of its own. New
        // files carry consent in `PluginPrefs.Uptime`, applied above; applying the same value twice
        // is a no-op either way.
        count += core.uptime.applyPreferences(enabled: s.dashboardWidgets?.uptimeEnabled)
        return count
    }

    private func applyHotkeys(
        _ hotkeys: HotkeyBackup, to core: AppCore, mode: ApplyMode
    ) -> Int {
        let hk = core.hotKeys
        var count = 0
        // Skip a binding whose combo is already claimed by an earlier-applied (or existing) action: two actions on the same key would make Carbon's second RegisterEventHotKey fail with eventHotKeyExistsErr, silently killing that shortcut. The recorder does this check interactively; imports must too.
        func apply(_ s: HotKeyBinding, _ action: HotKeyAction) {
            guard hk.conflictOwner(of: s, excluding: action) == nil else { return }
            hk.setBinding(s, for: action)
            count += 1
        }
        if mode == .replace {
            hk.setBinding(nil, for: .togglePalette)
            hk.setBinding(nil, for: .togglePaletteBackup)
            for key in core.plugins.shortcutActions { hk.setBinding(nil, for: .plugin(key)) }
            let remoteAppIDs = Set(hotkeys.apps?.keys.map { $0 } ?? [])
            for id in Set(hk.boundBundleIDs).union(remoteAppIDs) {
                hk.setBinding(nil, for: .app(bundleID: id))
            }
            let remotePaneIDs = Set(hotkeys.panes?.keys.map { $0 } ?? [])
            for id in Set(hk.boundPaneBundleIDs).union(remotePaneIDs) {
                hk.setBinding(nil, for: .settingsPane(bundleID: id))
            }
            let remoteCommandIDs = Set(
                (hotkeys.customCommands?.keys.map { $0 } ?? []).compactMap(UUID.init(uuidString:)))
            for id in Set(hk.boundCustomCommandIDs).union(remoteCommandIDs) {
                hk.setBinding(nil, for: .customCommand(id: id))
            }
            for id in CommandID.allCases { hk.setBinding(nil, for: .builtInCommand(id)) }
            let remoteQuicklinkIDs = Set(
                (hotkeys.quicklinks?.keys.map { $0 } ?? []).compactMap(UUID.init(uuidString:)))
            for id in Set(hk.boundQuicklinkIDs).union(remoteQuicklinkIDs) {
                hk.setBinding(nil, for: .quicklink(id: id))
            }
        }
        if let s = hotkeys.togglePalette { apply(s, .togglePalette) }
        if let s = hotkeys.togglePaletteBackup { apply(s, .togglePaletteBackup) }
        // Legacy single-action fields from older files; `pluginActions` below carries these in new exports.
        if let s = hotkeys.toggleClipboard { apply(s, .plugin(.openClipboard)) }
        if let s = hotkeys.toggleEmoji { apply(s, .plugin(.openEmoji)) }
        if let pluginActions = hotkeys.pluginActions {
            // Resolve through the registry so a binding only lands on an action this build actually has.
            for key in core.plugins.shortcutActions {
                let currentID = "\(key.pluginID.rawValue).\(key.actionID)"
                let legacyID: String?
                if key.pluginID == .selectionTools, key.actionID == "translate" {
                    legacyID = "ai-chat.translate"
                } else if key.pluginID == .aiChat,
                    ["define", "grammar"].contains(key.actionID)
                {
                    legacyID = "selection-tools.\(key.actionID)"
                } else if key.pluginID == .commands, key.actionID.hasPrefix("system.") {
                    legacyID =
                        "system-commands."
                        + String(key.actionID.dropFirst("system.".count))
                } else {
                    legacyID = nil
                }
                if let s = pluginActions[currentID] ?? legacyID.flatMap({ pluginActions[$0] }) {
                    apply(s, .plugin(key))
                }
            }
        }
        for id in (hotkeys.apps?.keys.sorted() ?? []) {
            if let binding = hotkeys.apps?[id] { apply(binding, .app(bundleID: id)) }
        }
        for id in (hotkeys.panes?.keys.sorted() ?? []) {
            if let binding = hotkeys.panes?[id] { apply(binding, .settingsPane(bundleID: id)) }
        }
        for rawID in (hotkeys.customCommands?.keys.sorted() ?? []) {
            guard let s = hotkeys.customCommands?[rawID] else { continue }
            guard let id = UUID(uuidString: rawID), core.customCommands.command(id: id) != nil else {
                continue
            }
            apply(s, .customCommand(id: id))
        }
        // Resolved through `CommandID`, so a command this build no longer ships is skipped rather than left bound to nothing.
        for rawID in (hotkeys.builtInCommands?.keys.sorted() ?? []) {
            guard let s = hotkeys.builtInCommands?[rawID], let id = CommandID(rawValue: rawID) else {
                continue
            }
            apply(s, .builtInCommand(id))
        }
        // The quicklinks themselves were applied before this call, so the target exists by now.
        for rawID in (hotkeys.quicklinks?.keys.sorted() ?? []) {
            guard let s = hotkeys.quicklinks?[rawID], let id = UUID(uuidString: rawID),
                core.quicklinks.quicklinks.contains(where: { $0.id == id })
            else { continue }
            apply(s, .quicklink(id: id))
        }
        return count
    }
}

// MARK: - Serialization

extension SettingsBackup {
    /// Newest format this build can interpret. Older files decode fine (every field is optional), but a newer file could carry semantics this build would silently misapply, so it is rejected instead.
    static let supportedVersion = 3

    enum DecodeError: LocalizedError {
        case unsupportedVersion(Int)

        var errorDescription: String? {
            switch self {
            case .unsupportedVersion(let version):
                return "This backup was written by a newer Spotter (format \(version)); update Spotter to import it."
            }
        }
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    func encodedOffMain() async throws -> Data {
        let snapshot = self
        return try await Task.detached(priority: .utility) { try snapshot.encoded() }.value
    }

    static func decodedOffMain(_ data: Data) async throws -> SettingsBackup {
        try await Task.detached(priority: .utility) { try SettingsBackup(json: data) }.value
    }

    init(json: Data) throws {
        let decoded = try JSONDecoder().decode(SettingsBackup.self, from: json)
        guard decoded.version <= Self.supportedVersion else {
            throw DecodeError.unsupportedVersion(decoded.version)
        }
        self = decoded
    }
}
