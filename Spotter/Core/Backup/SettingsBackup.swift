import Foundation

/// A passwordless, human-readable snapshot of Spotter's configuration. Every field is optional so an import applies only the keys actually present (non-destructive merge): a partial file — or one from Raycast — leaves everything it omits untouched.
struct SettingsBackup: Codable {
    var version = 2
    var settings: SettingsData?
    var hotkeys: HotkeyBackup?
    var customCommands: [CustomCommand]?
    var favoriteApps: [String]?
    var hiddenLauncherItems: [String]?
    var hiddenLauncherKinds: [String]?
    var pluginStates: [String: Bool]?
    var pluginPrefs: PluginPrefs?
    var worldClockCities: [String]?
    var quicklinks: [Quicklink]?
    var textReplacement: TextReplacementBackup?

    /// Enum-backed settings are stored by raw value so the JSON stays legible and forward-compatible (an unknown value is ignored on import rather than failing the whole decode).
    struct SettingsData: Codable {
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
        var openRouterTranslationModel: String?
        var openRouterDefinitionModel: String?
        var openRouterGrammarModel: String?
        var openRouterChatModel: String?
        var openRouterChatWebSearch: Bool?
    }

    struct HotkeyBackup: Codable {
        var togglePalette: HotKeyBinding?
        // Legacy per-action fields, read on import only; `pluginActions` supersedes both on export.
        var toggleClipboard: HotKeyBinding?
        var toggleEmoji: HotKeyBinding?
        var apps: [String: HotKeyBinding]?
        var panes: [String: HotKeyBinding]?
        var customCommands: [String: HotKeyBinding]?
        /// Every bound plugin shortcut, keyed `<plugin-id>.<action-id>` — new plugins sync automatically.
        var pluginActions: [String: HotKeyBinding]?
    }

    /// Per-plugin preferences that live in raw bundle-scoped `UserDefaults`. Gathered as effective values (defaults resolved), so a synced Mac lands on exactly what the source Mac shows.
    struct PluginPrefs: Codable {
        struct ChangeCase: Codable {
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
        struct KillProcess: Codable {
            var sort: String?
            var groupApps: Bool?
            var searchPaths: Bool?
            var searchPIDs: Bool?
            var prioritizeApps: Bool?
            var showPID: Bool?
            var showPath: Bool?
            var refreshSeconds: Double?
        }
        struct ImageModification: Codable {
            var output: String?
            var format: String?
        }
        struct SelectionTools: Codable {
            var translationPrompt: String?
            var definitionPrompt: String?
            var grammarPrompt: String?
        }
        struct Caffeinate: Codable {
            var keepsDisplayAwake: Bool?
            var keepsDiskAwake: Bool?
        }
        struct WindowManagement: Codable {
            var gap: Int?
            var cycleOnRepeat: Bool?
        }
        struct Mole: Codable {
            // A manual path override; harmless across machines — the locator ignores a path that isn't executable there.
            var binaryPath: String?
        }
        var changeCase: ChangeCase?
        var killProcess: KillProcess?
        var imageModification: ImageModification?
        var selectionTools: SelectionTools?
        var caffeinate: Caffeinate?
        var windowManagement: WindowManagement?
        var mole: Mole?
    }

    struct TextReplacementBackup: Codable {
        var prefix: String?
        var rules: [TextReplacementRule]?
    }

    /// A tally of what an import touched, for user-facing confirmation.
    struct ApplySummary {
        var settingsFields = 0
        var hotkeys = 0
        var favorites = 0
        var hiddenItems = 0
        var customCommands = 0
        var plugins = 0
    }
}

// MARK: - Gather / apply (main-actor: reads and writes the live stores)

@MainActor
extension SettingsBackup {
    static func gather(from core: AppCore = .shared) -> SettingsBackup {
        let s = core.settings
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
            openRouterAPIKey: core.openRouter.apiKey.isEmpty ? nil : core.openRouter.apiKey,
            openRouterTranslationModel: core.openRouter.translationModel,
            openRouterDefinitionModel: core.openRouter.definitionModel,
            openRouterGrammarModel: core.openRouter.grammarModel,
            openRouterChatModel: core.openRouter.chatModel,
            openRouterChatWebSearch: core.openRouter.chatWebSearch)

        let hk = core.hotKeys
        var hotkeys = HotkeyBackup()
        hotkeys.togglePalette = hk.binding(for: .togglePalette)
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
        backup.hotkeys = hotkeys

        backup.customCommands = core.customCommands.commands
        backup.favoriteApps = core.favorites.keys
        backup.hiddenLauncherItems = core.visibility.hiddenItemKeys.sorted()
        backup.hiddenLauncherKinds = core.visibility.hiddenKinds.sorted()
        backup.pluginStates = core.plugins.exportedEnabledStates()
        backup.pluginPrefs = gatherPluginPrefs(from: core)
        backup.worldClockCities = core.worldClock.cityIDs
        backup.quicklinks = core.quicklinks.sorted
        backup.textReplacement = TextReplacementBackup(
            prefix: core.textReplacements.prefix,
            rules: core.textReplacements.rules)
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
        prefs.selectionTools = PluginPrefs.SelectionTools(
            translationPrompt: core.aiChat.translationPrompt,
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
        return prefs
    }

    @discardableResult
    func apply(to core: AppCore = .shared) -> ApplySummary {
        var summary = ApplySummary()
        if let s = settings { summary.settingsFields = applySettings(s, to: core) }
        if let pluginStates {
            summary.plugins = core.plugins.applyEnabledStates(pluginStates)
        }
        if let customCommands {
            summary.customCommands = core.replaceCustomCommands(customCommands)
        }
        if let hotkeys { summary.hotkeys = applyHotkeys(hotkeys, to: core) }
        if let favoriteApps {
            core.favorites.replace(keys: favoriteApps)
            summary.favorites = favoriteApps.count
        }
        if hiddenLauncherItems != nil || hiddenLauncherKinds != nil {
            let items = hiddenLauncherItems ?? Array(core.visibility.hiddenItemKeys)
            let kinds = hiddenLauncherKinds ?? Array(core.visibility.hiddenKinds)
            core.visibility.replace(hiddenItems: items, hiddenKinds: kinds)
            summary.hiddenItems = items.count
        }
        if let pluginPrefs {
            summary.settingsFields += Self.applyPluginPrefs(pluginPrefs, to: core)
        }
        if let worldClockCities {
            core.worldClock.replace(cityIDs: worldClockCities)
            summary.settingsFields += 1
        }
        if let quicklinks {
            core.quicklinks.replace(with: quicklinks)
            summary.settingsFields += 1
        }
        if let textReplacement {
            core.textReplacements.replace(
                prefix: textReplacement.prefix, rules: textReplacement.rules ?? [])
            summary.settingsFields += 1
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
        if let selection = prefs.selectionTools {
            if let prompt = selection.translationPrompt {
                core.aiChat.setTranslationPrompt(prompt)
                count += 1
            }
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
        return count
    }

    private func applySettings(_ s: SettingsData, to core: AppCore) -> Int {
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
        }
        if let model = s.openRouterTranslationModel {
            core.openRouter.setTranslationModel(model)
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
        return count
    }

    private func applyHotkeys(_ hotkeys: HotkeyBackup, to core: AppCore) -> Int {
        let hk = core.hotKeys
        var count = 0
        // Skip a binding whose combo is already claimed by an earlier-applied (or existing) action: two actions on the same key would make Carbon's second RegisterEventHotKey fail with eventHotKeyExistsErr, silently killing that shortcut. The recorder does this check interactively; imports must too.
        func apply(_ s: HotKeyBinding, _ action: HotKeyAction) {
            guard hk.conflictOwner(of: s, excluding: action) == nil else { return }
            hk.setBinding(s, for: action)
            count += 1
        }
        if let s = hotkeys.togglePalette { apply(s, .togglePalette) }
        // Legacy single-action fields from older files; `pluginActions` below carries these in new exports.
        if let s = hotkeys.toggleClipboard { apply(s, .plugin(.openClipboard)) }
        if let s = hotkeys.toggleEmoji { apply(s, .plugin(.openEmoji)) }
        if let pluginActions = hotkeys.pluginActions {
            // Resolve through the registry so a binding only lands on an action this build actually has.
            for key in core.plugins.shortcutActions {
                let currentID = "\(key.pluginID.rawValue).\(key.actionID)"
                let legacyID: String?
                if key.pluginID == .aiChat,
                    ["translate", "define", "grammar"].contains(key.actionID)
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
        for (id, s) in hotkeys.apps ?? [:] { apply(s, .app(bundleID: id)) }
        for (id, s) in hotkeys.panes ?? [:] { apply(s, .settingsPane(bundleID: id)) }
        for (rawID, s) in hotkeys.customCommands ?? [:] {
            guard let id = UUID(uuidString: rawID), core.customCommands.command(id: id) != nil else {
                continue
            }
            apply(s, .customCommand(id: id))
        }
        return count
    }
}

// MARK: - Serialization

extension SettingsBackup {
    /// Newest format this build can interpret. Older files decode fine (every field is optional), but a newer file could carry semantics this build would silently misapply, so it is rejected instead.
    static let supportedVersion = 2

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

    init(json: Data) throws {
        let decoded = try JSONDecoder().decode(SettingsBackup.self, from: json)
        guard decoded.version <= Self.supportedVersion else {
            throw DecodeError.unsupportedVersion(decoded.version)
        }
        self = decoded
    }
}
