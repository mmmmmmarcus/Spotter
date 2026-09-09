import Foundation

/// A human-readable snapshot of Spotter's settings and content. Every field is optional so a manual import remains a non-destructive merge, while automatic sync treats a v3 snapshot as authoritative.
struct SettingsBackup: Codable, Sendable {
    var version = 3
    var settings: SettingsBackupData?
    var hotkeys: HotkeyBackup?
    var customCommands: [CustomCommand]?
    /// The AI commands, built-ins included: names, prompts and per-command model choices. User
    /// content, so it rides the trusted snapshot the way quicklinks and custom commands do.
    var aiCommands: [AICommand]?
    var favoriteApps: [String]?
    var hiddenLauncherItems: [String]?
    /// Decode-only: a file written while launcher categories could be hidden wholesale. Every
    /// category is always on now, so the field is read and ignored rather than restoring a hidden one.
    var hiddenLauncherKinds: [String]?
    /// Per-entry launcher aliases, keyed by `preferenceKey`. Data, not a capability — an alias grants nothing, so it rides an untrusted restore like favorites do.
    var launcherAliases: [String: String]?
    var pluginPrefs: SettingsBackupPluginPrefs?
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
        /// Per-AI-command bindings, keyed by UUID. The two built-ins have fixed UUIDs, so they
        /// round-trip here; they are also mirrored into `pluginActions` for older builds.
        var aiCommands: [String: HotKeyBinding]?
        /// Every bound plugin shortcut, keyed `<plugin-id>.<action-id>` — new plugins sync automatically.
        var pluginActions: [String: HotKeyBinding]?
    }

    struct TextReplacementBackup: Codable, Sendable {
        var prefix: String?
        var rules: [Snippet]?
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
        backup.settings = SettingsBackupData(
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
            launcherSectionOrder: s.launcherSectionOrder.map(\.rawValue),
            launcherHiddenSections: s.launcherHiddenSections.map(\.rawValue).sorted(),
            preferredTerminal: s.preferredTerminal.rawValue,
            remembersPalettePosition: s.remembersPalettePosition,
            lockInputToEnglish: s.lockInputToEnglish,
            openRouterAPIKey: core.openRouter.apiKey,
            openRouterDefinitionModel: core.aiCommands.command(.define)?.model,
            openRouterGrammarModel: core.aiCommands.command(.grammar)?.model,
            openRouterChatModel: core.openRouter.chatModel,
            openRouterChatWebSearch: core.openRouter.chatWebSearch,
            googleTranslationAPIKey: core.translate.apiKey,
            googleTranslationTargets: core.translate.targetCodes,
            updateAutoCheckEnabled: core.updates.autoCheckEnabled,
            currencyRatesEnabled: core.currencyRates.isEnabled,
            dashboardWidgets: SettingsBackupData.DashboardWidgets(
                widgetOrder: dashboard.widgetOrder.map(\DashboardWidgetKind.rawValue),
                calendarSourceIdentifier: dashboard.calendarSourceIdentifier ?? "",
                includesAllDayEvents: dashboard.includesAllDayEvents,
                weatherEnabled: core.dashboardWeather.isEnabled,
                weatherUnit: core.dashboardWeather.unit.rawValue))

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
        hotkeys.aiCommands = Dictionary(
            uniqueKeysWithValues: core.aiCommands.commands.compactMap { command in
                hk.binding(for: .aiCommand(id: command.id))
                    .map { (command.id.uuidString.lowercased(), $0) }
            })
        // Mirror the two built-ins under the plugin-action keys they had before AI Commands, so a
        // build that predates this file still reads a Define or Grammar binding out of it.
        for kind in AIBuiltInCommand.allCases {
            guard let binding = hk.binding(for: .aiCommand(id: kind.id)) else { continue }
            hotkeys.pluginActions?[kind.legacyBackupKey] = binding
        }
        backup.hotkeys = hotkeys

        backup.customCommands = core.customCommands.commands
        backup.aiCommands = core.aiCommands.commands
        backup.favoriteApps = core.favorites.keys
        backup.hiddenLauncherItems = core.visibility.hiddenItemKeys.sorted()
        backup.launcherAliases = core.aliases.aliases
        backup.pluginPrefs = gatherPluginPrefs(from: core)
        backup.worldClockCities = core.worldClock.cityIDs
        backup.quicklinks = core.quicklinks.sorted
        backup.textReplacement = TextReplacementBackup(
            prefix: core.textReplacements.prefix,
            rules: core.textReplacements.snippets)
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
    private static func gatherPluginPrefs(from core: AppCore) -> SettingsBackupPluginPrefs {
        let d = UserDefaults.standard
        var prefs = SettingsBackupPluginPrefs()
        prefs.changeCase = SettingsBackupPluginPrefs.ChangeCase(
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
        prefs.killProcess = SettingsBackupPluginPrefs.KillProcess(
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
        prefs.imageModification = SettingsBackupPluginPrefs.ImageModification(
            output: d.string(forKey: "image-modification.output")
                ?? ImageOutputLocation.alongside.rawValue,
            format: d.string(forKey: "image-modification.format") ?? ImageFormat.png.rawValue)
        prefs.screenshot = SettingsBackupPluginPrefs.Screenshot(
            roundedCorners: core.screenshot.roundedCorners,
            captureScale: core.screenshot.captureScale.rawValue,
            fileFormat: core.screenshot.fileFormat.rawValue,
            includesWindowShadow: core.screenshot.includesWindowShadow,
            hidesSpotterWindows: core.screenshot.hidesSpotterWindows,
            previewDuration: core.screenshot.previewDuration)
        prefs.selectionTools = SettingsBackupPluginPrefs.SelectionTools(
            definitionPrompt: core.aiCommands.command(.define)?.prompt,
            grammarPrompt: core.aiCommands.command(.grammar)?.prompt)
        prefs.caffeinate = SettingsBackupPluginPrefs.Caffeinate(
            keepsDisplayAwake: d.object(forKey: "coffee.keeps-display-awake") == nil
                || d.bool(forKey: "coffee.keeps-display-awake"),
            keepsDiskAwake: d.bool(forKey: "coffee.keeps-disk-awake"))
        prefs.windowManagement = SettingsBackupPluginPrefs.WindowManagement(
            gap: d.integer(forKey: WindowManagementDefaults.gapKey),
            cycleOnRepeat: d.bool(forKey: WindowManagementDefaults.cycleKey))
        prefs.mole = SettingsBackupPluginPrefs.Mole(binaryPath: d.string(forKey: "mole.binary-path") ?? "")
        prefs.note = SettingsBackupPluginPrefs.Note(
            windowTransparency: core.notes.windowTransparency,
            autoWindowSizing: core.notes.autoWindowSizing)
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
        if let customCommands {
            summary.customCommands = core.replaceCustomCommands(customCommands)
        }
        // Before `hotkeys` for the same reason as custom commands: a per-command binding only
        // applies to a command that already exists.
        if let aiCommands {
            core.replaceAICommands(aiCommands)
            summary.settingsFields += 1
        } else if let selection = pluginPrefs?.selectionTools {
            // A file written before AI Commands: its prompts belong to the two built-in records.
            if let prompt = selection.definitionPrompt {
                core.aiCommands.setPrompt(prompt, for: AIBuiltInCommand.define.id)
                summary.settingsFields += 1
            }
            if let prompt = selection.grammarPrompt {
                core.aiCommands.setPrompt(prompt, for: AIBuiltInCommand.grammar.id)
                summary.settingsFields += 1
            }
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
                prefix: textReplacement.prefix, snippets: textReplacement.rules ?? [])
            summary.settingsFields += 1
        }
        if case .include = noteTransfer, let notes {
            core.notes.replace(notes: notes.notes, selectedID: notes.selectedID)
            summary.contentCollections += 1
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

    private static func applyPluginPrefs(_ prefs: SettingsBackupPluginPrefs, to core: AppCore) -> Int {
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
        if let transparency = prefs.note?.windowTransparency {
            core.notes.setWindowTransparency(transparency)
            count += 1
        }
        if let autoWindowSizing = prefs.note?.autoWindowSizing {
            core.notes.setAutoWindowSizing(autoWindowSizing)
            count += 1
        }
        if let dashboard = prefs.dashboardWidgets {
            count += core.dashboardWidgets.applyPreferences(
                widgetOrderRawValues: dashboard.widgetOrder,
                calendarSourceIdentifier: dashboard.calendarSourceIdentifier,
                includesAllDayEvents: dashboard.includesAllDayEvents)
            count += core.dashboardWeather.applyPreferences(
                enabled: dashboard.weatherEnabled, unitRawValue: dashboard.weatherUnit)
        }
        return count
    }

    private func applySettings(_ s: SettingsBackupData, to core: AppCore, mode: ApplyMode) -> Int {
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
        if let raw = s.preferredTerminal, let terminal = PreferredTerminal(rawValue: raw) {
            settings.preferredTerminal = terminal
            count += 1
        }
        if let raw = s.launcherSectionOrder {
            settings.launcherSectionOrder = LauncherSectionsEngine.order(fromRaw: raw)
            count += 1
        }
        if let raw = s.launcherHiddenSections {
            settings.launcherHiddenSections = LauncherSectionsEngine.hidden(fromRaw: raw)
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
        // Only for a file written before each command carried its own model; a file that carries
        // `aiCommands` already said everything about them.
        if aiCommands == nil {
            if let model = s.openRouterDefinitionModel {
                core.aiCommands.setModel(model, for: AIBuiltInCommand.define.id)
                count += 1
            }
            if let model = s.openRouterGrammarModel {
                core.aiCommands.setModel(model, for: AIBuiltInCommand.grammar.id)
                count += 1
            }
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
            core.translate.setAPIKey(key)
            count += 1
        } else if mode == .replace && version >= 3 {
            core.translate.setAPIKey("")
            count += 1
        }
        if let targets = s.googleTranslationTargets {
            core.translate.setTargets(targets)
            count += 1
        }
        if let enabled = s.updateAutoCheckEnabled {
            core.updates.setAutoCheck(enabled)
            count += 1
        }
        count += core.currencyRates.applyPreferences(enabled: s.currencyRatesEnabled)
        if let dashboard = s.dashboardWidgets {
            count += core.dashboardWidgets.applyPreferences(
                widgetOrderRawValues: dashboard.widgetOrder,
                calendarSourceIdentifier: dashboard.calendarSourceIdentifier,
                includesAllDayEvents: dashboard.includesAllDayEvents)
            count += core.dashboardWeather.applyPreferences(
                enabled: dashboard.weatherEnabled, unitRawValue: dashboard.weatherUnit)
        }
        // is a no-op either way.
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
            let remoteAICommandIDs = Set(
                (hotkeys.aiCommands?.keys.map { $0 } ?? []).compactMap(UUID.init(uuidString:)))
            for id in Set(core.aiCommands.commands.map(\.id)).union(remoteAICommandIDs) {
                hk.setBinding(nil, for: .aiCommand(id: id))
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
                let legacyIDs: [String]
                if key.pluginID == .translate {
                    // Translation has lived under both owners; newest spelling first.
                    legacyIDs = ["selection-tools.\(key.actionID)", "ai-chat.\(key.actionID)"]
                } else if key.pluginID == .commands, key.actionID.hasPrefix("system.") {
                    legacyIDs = [
                        "system-commands." + String(key.actionID.dropFirst("system.".count))
                    ]
                } else {
                    legacyIDs = []
                }
                if let s = pluginActions[currentID]
                    ?? legacyIDs.lazy.compactMap({ pluginActions[$0] }).first
                {
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
        // Likewise applied before this call, built-ins included.
        for rawID in (hotkeys.aiCommands?.keys.sorted() ?? []) {
            guard let s = hotkeys.aiCommands?[rawID], let id = UUID(uuidString: rawID),
                core.aiCommands.command(id: id) != nil
            else { continue }
            apply(s, .aiCommand(id: id))
        }
        // A file written before AI Commands carried the two built-ins as plugin actions — under
        // AI Chat's ids, or Selection Tools' older ones.
        if hotkeys.aiCommands == nil, let pluginActions = hotkeys.pluginActions {
            for kind in AIBuiltInCommand.allCases {
                guard
                    let s = pluginActions[kind.legacyBackupKey] ?? pluginActions[kind.olderBackupKey]
                else { continue }
                apply(s, .aiCommand(id: kind.id))
            }
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
