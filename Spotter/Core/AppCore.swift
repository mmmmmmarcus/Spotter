import AppKit
import SwiftUI

enum PaletteMode: Equatable, Identifiable {
    case launcher
    case clipboard
    case calculatorHistory
    case emoji
    case aiChat
    case updates
    case plugin(PluginID)

    var id: String {
        switch self {
        case .launcher: return "launcher"
        case .clipboard: return "clipboard"
        case .calculatorHistory: return "calculator-history"
        case .emoji: return "emoji"
        case .aiChat: return "ai-chat"
        case .updates: return "updates"
        case .plugin(let id): return "plugin:" + id.rawValue
        }
    }
    var pluginID: PluginID? {
        guard case .plugin(let id) = self else { return nil }
        return id
    }
    var title: String {
        switch self {
        case .launcher: return "Apps"
        case .clipboard: return "Clipboard"
        case .calculatorHistory: return "Calculator History"
        case .emoji: return "Emoji & Symbols"
        case .aiChat: return "AI Chat"
        case .updates: return "Software Update"
        case .plugin: return "Plugin"
        }
    }
    var systemImage: String {
        switch self {
        case .launcher: return "magnifyingglass"
        case .clipboard: return "doc.on.doc"
        case .calculatorHistory: return "plus.forwardslash.minus"
        case .emoji: return "face.smiling"
        case .aiChat: return "sparkles"
        case .updates: return "arrow.down.circle"
        case .plugin: return "puzzlepiece.extension"
        }
    }
    /// The Tab cycle's stops, in order, minus any whose plugin is switched off. The single source of
    /// truth for both the key handling and the header glyph, so the affordance can't promise a loop
    /// the keys don't perform. Apps and AI Chat are system features and always present; every mode
    /// left out is a sub-screen reached from the launcher and keeps its back chevron.
    static func cycle(isPluginEnabled: (PluginID) -> Bool) -> [PaletteMode] {
        var stops: [PaletteMode] = [.launcher, .aiChat]
        if isPluginEnabled(.clipboard) { stops.append(.clipboard) }
        if isPluginEnabled(.emoji) { stops.append(.emoji) }
        return stops
    }

    var placeholder: String {
        switch self {
        case .launcher: return "Search for apps and commands…"
        case .clipboard: return "Type to filter entries…"
        case .calculatorHistory: return "Do math, convert units, or search your past calculations…"
        case .emoji: return "Search emoji and symbols…"
        case .aiChat: return "Ask anything, then press ↵…"
        case .updates: return "Software Update"
        case .plugin: return "Search plugin results…"
        }
    }
}

/// The app a paste will land in, resolved once per palette show so the footer pill and menu rows can name it without re-reading `NSWorkspace` on every render.
struct PasteTarget: Equatable {
    let name: String
    /// Bundle path for `IconCache` — nil for a target with no on-disk bundle.
    let iconPath: String?

    init?(app: NSRunningApplication?) {
        guard let app, let name = app.localizedName else { return nil }
        self.name = name
        iconPath = app.bundleURL?.path
    }

    var pasteTitle: String { "Paste to \(name)" }
}

/// A destructive action awaiting an in-palette yes/no, rendered by `RootPaletteView` as a centered
/// overlay instead of a system dialog. The default highlight is always Cancel: every confirmed
/// action is one ↵ away in the palette, and a reflexive second ↵ must never be the confirmation.
struct PaletteConfirmation {
    let title: String
    let message: String
    let actionTitle: String
    /// Tints the action red. Selection defaults to Cancel either way.
    var isDestructive = true
    let onConfirm: () -> Void
}

/// View-model shared between the panel's SwiftUI tree and the coordinator.
@MainActor
final class PaletteViewModel: ObservableObject {
    @Published var mode: PaletteMode = .launcher {
        didSet {
            guard oldValue != mode else { return }
            clipboardFilter = .all
            onModeChanged?(oldValue, mode)
        }
    }
    @Published var query: String = ""
    @Published var selection: Int = 0
    /// Changes every time the palette is shown so the search field can re-focus.
    @Published var focusToken = UUID()
    /// Bumped when the palette hides, so the view can re-prime the summon animation without ever animating it.
    @Published var dismissToken = UUID()
    /// Changes only when `prepare` resets the palette, so the lists snap their scroll to the top even when query/mode were already at their defaults (`focusToken` can't serve: it bumps on every reopen, which must preserve a within-timeout scroll).
    @Published var resetToken = UUID()
    /// Changes when an action reorders the list under the selection (pinning a clip lifts it into the Pinned section), so the list scrolls the highlight back into view.
    @Published var followToken = UUID()
    /// Bumped by `PalettePanel` when ⌘. arrives in the clipboard. AppKit binds that chord to `cancelOperation:` alongside Escape, so the field editor consumes it and `onKeyPress(keys: ["."])` never fires — see docs/palette.md. `RootPaletteView` observes the token and resolves the row from the current results, so which row gets pinned still comes from one place.
    @Published var pinChordToken = UUID()
    /// ⌃⌥⌘C (Hyper-C): hand the typed draft to ChatGPT on the web.
    @Published var chatGPTChordToken = UUID()
    /// Bumped by `PalettePanel` when Shift-Tab arrives. AppKit routes it to the field editor's `insertBacktab:`, which walks the key-view loop and lands focus on the header's mode-glyph button, so `onKeyPress` never fires and the search field loses first responder — see docs/palette.md.
    @Published var backTabToken = UUID()
    /// The clipboard list's type filter. Reset to `.all` on every `prepare` and on any mode change: a filter left on from last time would silently hide history the user came back for.
    @Published var clipboardFilter: ClipboardFilter = .all
    /// Set by the compact bar's "…" overflow to expand into the full launcher without a query; cleared on every `prepare`.
    @Published var forceExpanded = false
    /// The app a paste would land in, mirrored from `PaletteWindowController.previousApp` on every show. Deliberately *not* cleared by `prepare` — pop-to-root resets the screen, not the paste target.
    @Published var pasteTarget: PasteTarget?
    /// A pending in-palette yes/no. While set, the overlay owns ↵ / Esc / ←→ and typing is frozen through the same mechanism as an open footer menu.
    @Published var confirmation: PaletteConfirmation?
    /// Gates the mouse-hover highlight: true only while the pointer is physically moving (armed on `.mouseMoved`, disarmed on any `.keyDown` in `PalettePanel.sendEvent`). Plain, not `@Published` — read at hover time, never drives a re-render.
    var hoverHighlightArmed = false
    /// True while a footer popover menu (⌘K Actions or the app menu) is open, so `PalettePanel.sendEvent` swallows text-editing keystrokes the field editor would otherwise consume — the query must stay frozen while a menu owns the keyboard (matches Raycast). Plain, not `@Published` — read at event time, mirrored from the view's menu state.
    var menuOpen = false { didSet { onMenuOpenChanged?(menuOpen) } }
    /// True only while the Actions menu can consume printable keys for title matching; confirmations and the app menu still freeze arbitrary typing.
    var menuTypeaheadEnabled = false
    @Published private(set) var menuTypeaheadQuery = ""
    private var menuTypeaheadBuffer = PaletteMenuTypeaheadBuffer()
    /// Fired when `menuOpen` flips so `PalettePanel` can hide/show the search field's caret while it keeps first-responder status (no focus swap, so the placeholder never reflows).
    var onMenuOpenChanged: ((Bool) -> Void)?
    var onModeChanged: ((PaletteMode, PaletteMode) -> Void)?

    func appendMenuTypeahead(_ characters: String, at now: Date = Date()) {
        menuTypeaheadBuffer.append(characters, at: now)
        menuTypeaheadQuery = menuTypeaheadBuffer.query
    }

    func deleteLastMenuTypeaheadCharacter() {
        menuTypeaheadBuffer.deleteLast()
        menuTypeaheadQuery = menuTypeaheadBuffer.query
    }

    func resetMenuTypeahead() {
        menuTypeaheadBuffer.reset()
        menuTypeaheadQuery = ""
    }

    func prepare(mode: PaletteMode) {
        self.mode = mode
        query = ""
        selection = 0
        clipboardFilter = .all
        forceExpanded = false
        hoverHighlightArmed = false
        menuOpen = false
        menuTypeaheadEnabled = false
        resetMenuTypeahead()
        confirmation = nil
        focusToken = UUID()
        resetToken = UUID()
    }
}

/// Single owner of every long-lived manager. Wired up once from the app delegate.
@MainActor
final class AppCore: ObservableObject {
    static let shared = AppCore()

    let launcherRanking: LauncherRankingStore
    let appIndex: AppIndex
    let customCommands = CustomCommandStore()
    let settingsSync = SettingsSyncManager()
    let clipboardStore = ClipboardStore()
    let clipboardManager: ClipboardManager
    let textReplacements: TextReplacementStore
    let textReplacementManager: TextReplacementManager
    let hotKeys = HotKeyManager()
    let hyperKeyTap = HyperKeyTap()
    let settings = AppSettings()
    let favorites = FavoritesStore()
    let visibility = VisibilityStore()
    let aliases = AliasStore()
    let calcHistory = CalculatorHistoryStore()
    let currencyRates = CurrencyRateStore()
    let emojiIndex = EmojiIndex()
    let frequentEmoji = FrequentEmojiStore()
    let runningApps = RunningAppsMonitor()
    let backgroundTasks = BackgroundTaskStore()
    let palette = PaletteViewModel()
    let plugins = PluginRegistry()
    let worldClock = WorldClockStore()
    let dashboardWidgets = DashboardWidgetsStore()
    let dashboardWeather = DashboardWeatherStore()
    let uptime = UptimeStore()
    let dashboardMusic = DashboardMusicStore()
    let dashboardDeviceBattery = DashboardDeviceBatteryStore()
    let dashboardFileInfo = DashboardFileInfoStore()
    let killProcess = KillProcessManager()
    let fileSearch = FileSearchSession()
    let changeCase = ChangeCaseStore()
    let openRouter = OpenRouterStore()
    let selectedTextCapture = SelectedTextCapture()
    let selectionTools: SelectionToolsManager
    let imageModification = ImageModificationManager()
    let notes: NoteStore
    let noteSync: NoteSyncManager
    let aiChat: AIChatStore
    let quicklinks = QuicklinkStore()
    let quicklinkManager: QuicklinkManager
    let windowMover = WindowMover()
    let mole = MoleManager()
    let onePassword = OnePasswordManager()
    let coffee = CoffeeManager()
    lazy var screenshot = ScreenshotManager(hotKeys: hotKeys)
    let updates = UpdateStore()
    let hud = CommandHUD()

    /// Which list the Coffee palette screen is showing; set by the command that opened it.
    var coffeeScreen: CoffeeScreen = .status

    private lazy var windowController = PaletteWindowController(core: self)
    private lazy var auxWindows = AuxWindowController { [weak self] in
        self?.syncActivationPolicy()
    }

    private init() {
        let launcherRanking = LauncherRankingStore()
        self.launcherRanking = launcherRanking
        appIndex = AppIndex(ranking: launcherRanking, aliases: aliases)
        clipboardManager = ClipboardManager(store: clipboardStore, settings: settings)
        let textReplacements = TextReplacementStore()
        self.textReplacements = textReplacements
        textReplacementManager = TextReplacementManager(store: textReplacements)
        selectionTools = SelectionToolsManager()
        let notes = NoteStore()
        self.notes = notes
        noteSync = NoteSyncManager(store: notes)
        aiChat = AIChatStore(openRouter: openRouter)
        quicklinkManager = QuicklinkManager(store: quicklinks)
        for registration in BuiltInPlugins.registrations(core: self) {
            plugins.register(registration)
        }
        palette.onModeChanged = { [weak self] oldMode, newMode in
            if let id = oldMode.pluginID { self?.plugins.deactivatePaletteScreen(id) }
            if let id = newMode.pluginID { self?.plugins.activatePaletteScreen(id) }
        }
        settings.onDockVisibilityChanged = { [weak self] in
            self?.syncActivationPolicy()
        }
    }

    func start() {
        // AppKit's default tooltip delay is ~2–3s; shorten it (in ms) so the compact-bar favorite tooltips appear promptly. Registration domain — never overrides a user default.
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 250])
        syncActivationPolicy()

        clipboardStore.maxAge = settings.clipboardRetention.maxAge
        appIndex.start(settings: settings)
        plugins.onCommandsChanged = { [weak self] commands in
            self?.appIndex.setPluginCommands(commands)
        }
        for entry in plugins.initiallyHiddenLauncherCommands {
            let key = "plugin.command.visibility-initialized." + entry.id
            guard !UserDefaults.standard.bool(forKey: key) else { continue }
            visibility.setItemVisible(false, for: entry)
            UserDefaults.standard.set(true, forKey: key)
        }
        // One-time unhide: the installer command shipped hidden while it was a Terminal hand-off;
        // now that it renders in-palette, installs that carry the old seed get the new default once.
        let installerMigration = "plugin.command.visibility-migrated.command:mole:installer"
        if !UserDefaults.standard.bool(forKey: installerMigration),
            let entry = plugins.launcherCommands.first(where: { $0.id == "command:mole:installer" })
        {
            visibility.setItemVisible(true, for: entry)
            UserDefaults.standard.set(true, forKey: installerMigration)
        }
        appIndex.setPluginCommands(plugins.launcherCommands)
        customCommands.onChange = { [weak self] _ in
            self?.plugins.reloadDynamicCommands(for: .commands)
        }
        quicklinks.onChange = { [weak self] in
            QuicklinkManager.invalidateOpenerCache()
            self?.plugins.reloadDynamicCommands(for: .quicklinks)
        }
        textReplacements.onSnippetsChanged = { [weak self] in
            self?.plugins.reloadDynamicCommands(for: .textReplacement)
        }
        // Each argument step reuses the same field, so the prompt has to start empty.
        quicklinkManager.onStepAdvanced = { [weak self] in
            self?.palette.query = ""
            self?.palette.selection = 0
        }
        Task { await appIndex.refresh() }
        plugins.start()
        settingsSync.start(core: self)

        // Selected-text actions borrow the pasteboard only as a last resort; keep that transient copy and restore out of history.
        selectedTextCapture.suspendClipboardCapture = { [weak self] in
            self?.clipboardManager.beginSuppressingCapture()
        }
        selectedTextCapture.resumeClipboardCapture = { [weak self] in
            self?.clipboardManager.endSuppressingCapture()
        }

        mole.onRunProgress = { [weak self] taskID, detail, progress in
            self?.backgroundTasks.update(id: taskID, detail: detail, progress: progress)
        }
        mole.onRunFinished = { [weak self] taskID, action, summary, succeeded in
            guard let self else { return }
            let detail = summary.first ?? "\(action.title) finished."
            if succeeded {
                self.backgroundTasks.complete(id: taskID, detail: detail)
            } else {
                self.backgroundTasks.fail(id: taskID, detail: detail)
            }
        }

        imageModification.onTaskStarted = { [weak self] operation, count in
            guard let self else { return UUID() }
            let noun = count == 1 ? "image" : "images"
            let taskID = self.backgroundTasks.begin(
                title: operation.title, detail: "Processing \(count) \(noun)…",
                systemImage: operation.systemImage)
            self.palette.prepare(mode: .launcher)
            self.showPalette(mode: .launcher)
            return taskID
        }
        imageModification.onTaskProgress = { [weak self] taskID, detail, progress in
            self?.backgroundTasks.update(id: taskID, detail: detail, progress: progress)
        }
        imageModification.onTaskFinished = { [weak self] taskID, succeeded, detail in
            if succeeded {
                self?.backgroundTasks.complete(id: taskID, detail: detail)
            } else {
                self?.backgroundTasks.fail(id: taskID, detail: detail)
            }
        }
        imageModification.onTaskCancelled = { [weak self] taskID in
            self?.backgroundTasks.discard(id: taskID)
        }

        aiChat.onRequestStarted = { [weak self] sessionID, sessionTitle in
            guard let self else { return UUID() }
            return self.backgroundTasks.begin(
                title: "Asking Spotter AI", detail: "Waiting for \(sessionTitle)…",
                systemImage: "sparkles",
                onOpen: { [weak self] in self?.openAIChat(sessionID: sessionID) })
        }
        aiChat.onRequestFinished = { [weak self] taskID, sessionID, succeeded, detail in
            guard let self else { return }
            // The row exists to carry a reply the user walked away from. Landing in front of them,
            // in that very conversation, is the reply being read — there is nothing to come back to.
            if isPaletteShowing, palette.mode == .aiChat, aiChat.currentID == sessionID {
                backgroundTasks.discard(id: taskID)
                return
            }
            if succeeded {
                backgroundTasks.complete(id: taskID, detail: detail)
            } else {
                backgroundTasks.fail(id: taskID, detail: detail)
            }
        }
        aiChat.onRequestCancelled = { [weak self] taskID in
            self?.backgroundTasks.discard(id: taskID)
        }

        // Terminate through NSApp so applicationWillTerminate still runs (Hyper Key remap cleanup) before the relaunch helper brings the new build up.
        updates.terminateForRelaunch = { NSApp.terminate(nil) }
        updates.start()
        // No-ops without consent and a chosen city, so it is safe to call unconditionally.
        dashboardWeather.start()
        // Likewise a no-op without consent — it installs no input monitors until then.
        uptime.start()

        hotKeys.onTogglePalette = { [weak self] in self?.togglePalette() }
        hotKeys.onRunPluginAction = { [weak self] action in self?.plugins.perform(action) }
        hotKeys.onRunCustomCommand = { [weak self] id in self?.runCustomCommand(id: id) }
        hotKeys.onRunBuiltInCommand = { [weak self] id in self?.runCommand(id) }
        hotKeys.onRunQuicklink = { [weak self] id in self?.runQuicklink(id: id) }
        hotKeys.start(
            pluginActions: plugins.shortcutActions,
            defaultPluginShortcuts: plugins.defaultShortcutActions,
            customCommandIDs: Set(customCommands.commands.map(\.id)),
            quicklinkIDs: Set(quicklinks.quicklinks.map(\.id)))
        // Deliberately keeps running while `hotKeys.recordingAction` pauses Carbon: the recorder relies on the tap's rewritten flags to capture Hyper shortcuts.
        hyperKeyTap.start(settings: settings)

        // First launch has no palette hotkey bound and shows nothing but the menu-bar icon; guide the user once. Marker is written at show-time so it stays one-time even if they Cmd-Q mid-flow.
        if !OnboardingState.hasOnboarded {
            OnboardingState.markShown()
            showOnboarding()
        }
    }

    // MARK: - Palette control

    /// The one way any feature asks a yes/no: an in-palette overlay, never a system dialog. Shows
    /// the palette first when the request came from a global hotkey with the panel closed.
    func confirmInPalette(_ confirmation: PaletteConfirmation) {
        if !windowController.isVisible {
            showPalette(mode: palette.mode, restoreAnyMode: true)
        }
        // The compact bar has no room for the card; expand without disturbing the query.
        palette.forceExpanded = true
        palette.confirmation = confirmation
    }

    func togglePalette() {
        if windowController.isVisible, palette.mode == .launcher {
            hidePalette()
        } else {
            showPalette(mode: .launcher, restoreAnyMode: true)
        }
    }

    func toggleClipboard() {
        guard plugins.isEnabled(.clipboard) else { return }
        if windowController.isVisible, palette.mode == .clipboard {
            hidePalette()
        } else {
            showPalette(mode: .clipboard)
        }
    }

    func toggleEmoji() {
        guard plugins.isEnabled(.emoji) else { return }
        if windowController.isVisible, palette.mode == .emoji {
            hidePalette()
        } else {
            showPalette(mode: .emoji)
        }
    }

    /// Shows the palette, honoring Pop to Root Search: a reopen within the timeout restores the pre-close state — any mode for the generic summon (`restoreAnyMode`), else only when the preserved mode already matches the requested one.
    func showPalette(mode: PaletteMode, restoreAnyMode: Bool = false) {
        let preserved = windowController.consumePreservedState()
        if !(preserved && (restoreAnyMode || palette.mode == mode)) {
            palette.prepare(mode: mode)
        }
        windowController.show()
        if let id = palette.mode.pluginID { plugins.activatePaletteScreen(id) }
        if palette.mode == .launcher {
            // Re-scan on open so an app uninstalled since the last scan drops out of the launcher.
            Task { await appIndex.refresh() }
            // Here rather than only in the card's own poll: with nothing reporting a level the card
            // isn't rendered, so it would never run to notice a device that has since connected.
            dashboardDeviceBattery.refresh()
            refreshDashboardFileInfo()
        }
        // Live only while the palette shows: the section's CPU/memory readings poll `ps`, and a hidden palette must not keep sampling.
        if settings.visibleLauncherSections.contains(.activeApps) {
            runningApps.startUsageSampling()
        }
    }

    func hidePalette(restoreFocus: Bool = true) {
        if let id = palette.mode.pluginID { plugins.deactivatePaletteScreen(id) }
        runningApps.stopUsageSampling()
        windowController.hide(restoreFocus: restoreFocus)
    }

    /// True when the palette should render as the slim compact bar: compact mode on, no background task to show, launcher root, empty query, and not force-expanded via the "…" overflow.
    var paletteIsCollapsed: Bool {
        settings.compactMode
            && backgroundTasks.tasks.isEmpty
            && !palette.forceExpanded
            && palette.mode == .launcher
            && palette.query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The compact bar's "…" overflow: expand into the full favorites-pinned launcher without typing.
    func expandFromCompact() {
        palette.forceExpanded = true
    }

    /// Resize the panel to match the current collapsed state; called by the view when `paletteIsCollapsed` flips while open.
    func syncPaletteSize() {
        windowController.applyCollapsed(paletteIsCollapsed)
    }

    /// Dock-icon / reopen always summons the launcher, even when Settings or another auxiliary window is already open.
    func handleReopen() {
        showPalette(mode: .launcher, restoreAnyMode: true)
    }

    /// The Dock preference is the idle policy; auxiliary windows temporarily require regular-app activation for native layering and focus.
    private func syncActivationPolicy() {
        let policy: NSApplication.ActivationPolicy =
            settings.showInDock || auxWindows.hasOpenWindows ? .regular : .accessory
        NSApp.setActivationPolicy(policy)
    }

    /// Settings runs in its own window (the SwiftUI `Settings` scene is unreliable for accessory apps). A fresh window mounts directly on `tab` (no first-frame flicker); an already-open one is switched in place.
    func showSettings(tab: SettingsTab = .general) {
        showSettings(destination: .system(tab))
    }

    func showSettings(plugin id: PluginID) {
        showSettings(destination: .plugin(id))
    }

    private func showSettings(destination: SettingsDestination) {
        let isNew = auxWindows.show(
            id: "settings", title: "Settings",
            size: CGSize(
                width: Theme.Size.settingsWindowWidth,
                height: Theme.Size.settingsWindowHeight),
            seamlessTitleBar: true
        ) {
            SettingsRootView(initialDestination: destination)
                .environmentObject(self.appIndex)
                .environmentObject(self.visibility)
                .environmentObject(self.aliases)
                .environmentObject(self.customCommands)
                .environmentObject(self.plugins)
                .environmentObject(self.settingsSync)
        }
        if !isNew {
            NotificationCenter.default.post(
                name: .spotterSelectSettingsDestination, object: destination)
        }
    }

    func showBackupSettings() {
        showSettings(tab: .backup)
    }

    func showAbout() {
        showSettings(tab: .about)
    }

    /// Launcher-first update flow: stay in the shared palette while the same store and installer used by Settings drive every state.
    func showUpdates() {
        palette.prepare(mode: .updates)
        Task { await updates.checkNow() }
    }

    func performUpdatePrimaryAction() {
        switch updates.status {
        case .available(let release) where release.zipAssetURL != nil:
            Task { await updates.installAvailableUpdate() }
        case .available(let release):
            NSWorkspace.shared.open(release.pageURL)
        case .idle, .upToDate, .failed:
            Task { await updates.checkNow() }
        case .checking, .installing:
            break
        }
    }

    /// Native plugin workspaces share AppCore's auxiliary-window owner instead of creating plugin-specific window singletons.
    @discardableResult
    func showPluginWindow<Content: View>(
        id: String, title: String, size: CGSize, resizable: Bool = false,
        floating: Bool = false, transparent: Bool = false, minimumSize: CGSize? = nil,
        closeButtonOnly: Bool = false, hidesStandardButtons: Bool = false,
        clearsInitialFocus: Bool = false, contentExtendsIntoTitleBar: Bool = false,
        movableByBackground: Bool = true,
        @ViewBuilder content: () -> Content
    ) -> Bool {
        auxWindows.show(
            id: "plugin." + id, title: title, size: size, seamlessTitleBar: true,
            resizable: resizable, floating: floating, transparent: transparent,
            minimumSize: minimumSize, closeButtonOnly: closeButtonOnly,
            hidesStandardButtons: hidesStandardButtons,
            clearsInitialFocus: clearsInitialFocus,
            contentExtendsIntoTitleBar: contentExtendsIntoTitleBar,
            movableByBackground: movableByBackground
        ) {
            content()
                .environmentObject(self)
                .environmentObject(self.plugins)
        }
    }

    /// Closes Settings, About and every plugin workspace — used before a capture so Spotter's own
    /// windows cannot end up in the shot.
    func closeAuxiliaryWindows() {
        auxWindows.closeAll()
    }

    func closePluginWindow(id: String) {
        auxWindows.close(id: "plugin." + id)
    }

    func isPluginWindowShowing(id: String) -> Bool {
        auxWindows.isShowing(id: "plugin." + id)
    }

    func resizePluginWindow(id: String, height: CGFloat, animated: Bool = true) {
        auxWindows.resizeHeight(id: "plugin." + id, to: height, animated: animated)
    }

    var previousApplication: NSRunningApplication? { windowController.previousApp }
    /// Whether the palette panel is on screen — window commands need it to pick their target app.
    var isPaletteShowing: Bool { windowController.isVisible }

    /// The first-run wizard: palette shortcut, Accessibility, Raycast import. Also re-runnable from Settings.
    func showOnboarding() {
        auxWindows.show(
            id: "onboarding", title: "Welcome to Spotter",
            size: OnboardingView.windowSize, seamlessTitleBar: true
        ) {
            OnboardingView()
        }
    }

    /// Final onboarding step: close the wizard and drop straight into the launcher.
    func finishOnboarding() {
        auxWindows.close(id: "onboarding")
        showPalette(mode: .launcher)
    }

    // MARK: - Actions invoked from the palette UI

    func launch(_ app: AppEntry, searchQuery: String? = nil) {
        if let searchQuery {
            launcherRanking.record(itemKey: app.preferenceKey, query: searchQuery)
        }
        // Commands dispatch before the palette hides: mode-switching commands keep it open.
        if app.kind == .command {
            if let id = CustomCommand.id(fromEntryID: app.id) {
                runCustomCommand(id: id)
            } else {
                runCommand(app)
            }
            return
        }
        hidePalette(restoreFocus: false)
        switch app.kind {
        case .application:
            AppLauncher.launch(app.url)
        case .systemSettings:
            guard let bundleID = app.bundleID else { return }
            AppLauncher.openSettingsPane(bundleID: bundleID)
        case .command:
            break  // handled above
        }
    }

    func resetRanking(for app: AppEntry) {
        launcherRanking.reset(itemKey: app.preferenceKey)
    }

    // MARK: - Custom commands

    @discardableResult
    func addCustomCommand(_ draft: CustomCommand) throws -> CustomCommand {
        try customCommands.add(draft)
    }

    func updateCustomCommand(_ draft: CustomCommand) throws {
        try customCommands.update(draft)
    }

    func deleteCustomCommand(id: UUID) {
        guard let command = customCommands.command(id: id) else { return }
        removeCustomCommandReferences(ids: [id], entryIDs: [command.entryID])
        customCommands.remove(id: id)
    }

    @discardableResult
    func replaceCustomCommands(_ commands: [CustomCommand]) -> Int {
        let previous = Dictionary(uniqueKeysWithValues: customCommands.commands.map { ($0.id, $0) })
        let count = customCommands.replace(with: commands)
        let liveIDs = Set(customCommands.commands.map(\.id))
        let removed = Set(previous.keys).subtracting(liveIDs)
        let removedEntryIDs = Set(removed.compactMap { previous[$0]?.entryID })
        removeCustomCommandReferences(ids: removed, entryIDs: removedEntryIDs)
        return count
    }

    /// The one funnel for both palette activation and the command's global hotkey, so the confirmation gate can't be bypassed by either.
    func runCustomCommand(id: UUID) {
        guard plugins.isEnabled(.commands),
            let command = customCommands.command(id: id)
        else { return }
        if command.requiresConfirmation {
            confirmInPalette(
                PaletteConfirmation(
                    title: command.name,
                    message: "Are you sure you want to run this command?",
                    actionTitle: "Run",
                    isDestructive: false
                ) { [weak self] in
                    self?.executeCustomCommand(command)
                })
            return
        }
        executeCustomCommand(command)
    }

    private func executeCustomCommand(_ command: CustomCommand) {
        if isPaletteShowing { hidePalette(restoreFocus: true) }
        Task {
            let outcome = await ShellCommandRunner.run(
                command.command, loadingShellEnvironment: command.loadsShellEnvironment)
            guard outcome != .success else {
                hud.show(title: "\(command.name) Finished", symbol: "checkmark.circle")
                return
            }
            AppLog.error("custom-commands", "“\(command.name)” failed: \(outcome)")
            self.presentCustomCommandFailure(command: command, outcome: outcome)
        }
    }

    private func removeCustomCommandReferences(ids: Set<UUID>, entryIDs: Set<String>) {
        for id in ids {
            let action = HotKeyAction.customCommand(id: id)
            if hotKeys.recordingAction == action { hotKeys.recordingAction = nil }
            hotKeys.setShortcut(nil, for: action)
        }
        favorites.remove(keys: entryIDs)
        visibility.removeItemKeys(entryIDs)
        aliases.removeKeys(entryIDs)
        for entryID in entryIDs {
            launcherRanking.reset(itemKey: entryID)
        }
    }

    private func presentCustomCommandFailure(
        command: CustomCommand, outcome: ShellCommandOutcome
    ) {
        let message: String
        // `127` is the shell's "command not found", so an alias or function that only exists in the user's config lands here.
        var suggestsShellEnvironment = false
        switch outcome {
        case .success:
            return
        case .launchFailure(let detail):
            message = "The shell could not be started.\n\n\(detail)"
        case .nonZeroExit(let status, let stderr):
            suggestsShellEnvironment = status == 127 && !command.loadsShellEnvironment
            message =
                "The command exited with status \(status)."
                + (stderr.map { "\n\n" + $0 } ?? "")
                + (suggestsShellEnvironment
                    ? "\n\nIf this is a shell alias or function, turn on Load Shell Environment for "
                        + "this command." : "")
        }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "“\(command.name)” Failed"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        if suggestsShellEnvironment { alert.addButton(withTitle: "Open Settings…") }
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        showSettings(plugin: .commands)
    }

    /// Quits the app behind an entry; a no-op (palette stays put) when it isn't running.
    func quit(_ app: AppEntry) {
        guard app.kind == .application, let bundleID = app.bundleID else { return }
        // Unlike `launch`, nothing here takes focus on its own — hand it back to where the user was, unless that's the app now on its way out.
        let quittingPreviousApp = windowController.previousApp?.bundleIdentifier == bundleID
        guard AppLauncher.quit(bundleID: bundleID) else { return }
        hidePalette(restoreFocus: !quittingPreviousApp)
    }

    /// Quit All: the one action whose blast radius reaches outside Spotter, so it confirms first. The target list is resolved once and both counted and terminated, so the set the user approves is the set that quits.
    private func quitAllApps() {
        let targets = AppLauncher.quitAllTargets()
        guard !targets.isEmpty else { return }
        confirmInPalette(
            PaletteConfirmation(
                title: targets.count == 1
                    ? "Quit 1 application?" : "Quit \(targets.count) applications?",
                message: "Applications with unsaved changes will ask you to save.",
                actionTitle: "Quit All"
            ) { [weak self] in
                self?.hidePalette(restoreFocus: false)
                for app in targets { app.terminate() }
            })
    }

    private func runCommand(_ entry: AppEntry) {
        if plugins.performCommand(entry.id) { return }
        guard let command = CommandRegistry.command(for: entry) else { return }
        runCommand(command)
    }

    /// The one dispatch for Spotter's own built-in commands — a launcher row and a global shortcut bound to the same command both land here.
    func runCommand(_ command: CommandID) {
        switch command {
        case .calculatorHistory:
            showPalette(mode: .calculatorHistory)
        case .checkForUpdates:
            showUpdates()
        case .exportSettings:
            hidePalette(restoreFocus: false)
            BackupActions.exportSettings()
        case .importSettings:
            hidePalette(restoreFocus: false)
            BackupActions.importSettings()
        case .importFromRaycast:
            hidePalette(restoreFocus: false)
            showBackupSettings()
        case .settings:
            hidePalette(restoreFocus: false)
            showSettings()
        case .about, .version:
            hidePalette(restoreFocus: false)
            showAbout()
        case .quitAllApps:
            // Hide before confirming: the palette is a floating panel and would sit above the alert.
            hidePalette(restoreFocus: false)
            quitAllApps()
        case .quit:
            NSApp.terminate(nil)
        }
    }

    /// Enter on the inline calculator card: copy the answer, remember the calculation, dismiss.
    func copyCalculatorResult(_ result: CalcResult) {
        guard case .value(let display, let copyText) = result.payload else { return }
        calcHistory.record(expression: result.expression, result: display)
        hidePalette(restoreFocus: false)
        Paster.copyPlainText(copyText)
    }

    /// Plugin inline answers are copied but never added to calculator history.
    func copyPluginQueryResult(_ result: PluginQueryResult) {
        hidePalette(restoreFocus: false)
        Paster.copyPlainText(result.copyText)
    }

    /// Enter on a Calculator History row: re-copy the stored answer (no re-record).
    func copyHistoryEntry(_ entry: CalcHistoryEntry) {
        hidePalette(restoreFocus: false)
        Paster.copyPlainText(entry.result.replacingOccurrences(of: ",", with: ""))
    }

    func copyHistoryExpression(_ entry: CalcHistoryEntry) {
        hidePalette(restoreFocus: false)
        Paster.copyPlainText(entry.expression)
    }

    func showInFinder(_ app: AppEntry) {
        hidePalette(restoreFocus: false)
        AppLauncher.showInFinder(app.url)
    }

    func paste(_ item: ClipboardItem) {
        let previous = windowController.previousApp
        hidePalette(restoreFocus: false)
        // A successful write promotes the item to the head of its section; follow it so any preserved (pop-to-root) or open clipboard state highlights the row that moved.
        if Paster.paste(item, store: clipboardStore, previousApp: previous) {
            selectClip(item)
        }
    }

    func pasteKeepingWindowOpen(_ item: ClipboardItem) {
        if windowController.pasteKeepingWindowOpen(item, store: clipboardStore) {
            selectClip(item)
        }
    }

    func copyToClipboard(_ item: ClipboardItem) {
        hidePalette(restoreFocus: false)
        if Paster.copy(item, store: clipboardStore) {
            selectClip(item)
        }
    }

    func revealClipboardImage(_ item: ClipboardItem) {
        guard let url = clipboardStore.imageURL(for: item) else { return }
        hidePalette(restoreFocus: false)
        AppLauncher.showInFinder(url)
    }

    /// Pin or unpin a clipboard entry: the row jumps into (or out of) the Pinned section at the top, so the selection and the scroll follow it.
    func togglePinnedClip(_ item: ClipboardItem) {
        clipboardStore.togglePinned(item)
        selectClip(item)
        palette.followToken = UUID()
    }

    func confirmDeleteClip(_ item: ClipboardItem) {
        confirmInPalette(
            PaletteConfirmation(
                title: "Delete Clipboard Entry?",
                message: "This item will be permanently removed from clipboard history.",
                actionTitle: "Delete"
            ) { [weak self] in
                self?.clipboardStore.remove(item)
            })
    }

    func confirmClearClipboardHistory() {
        guard !clipboardStore.items.isEmpty else { return }
        confirmInPalette(
            PaletteConfirmation(
                title: "Delete All Clipboard Entries?",
                message: "Pinned entries and the complete clipboard history will be permanently deleted.",
                actionTitle: "Delete All"
            ) { [weak self] in
                self?.clipboardStore.clearAll()
            })
    }

    /// Put the selection on `item`'s row in the list as currently filtered — pinned rows hold the top, so a row that moved isn't always index 0.
    private func selectClip(_ item: ClipboardItem) {
        palette.selection =
            clipboardStore.rowIndex(
                of: item, in: palette.query, filter: palette.clipboardFilter) ?? 0
    }

    // MARK: - Emoji actions (frequency is tallied on the base glyph; the configured tone is applied at copy time)

    func pasteEmoji(_ entry: EmojiEntry) {
        frequentEmoji.record(entry.glyph)
        let previous = windowController.previousApp
        hidePalette(restoreFocus: false)
        Paster.pasteString(entry.display(tone: settings.emojiSkinTone), previousApp: previous)
    }

    func copyEmoji(_ entry: EmojiEntry) {
        frequentEmoji.record(entry.glyph)
        hidePalette(restoreFocus: false)
        Paster.copyString(entry.display(tone: settings.emojiSkinTone))
    }

    func pasteEmojiKeepingWindowOpen(_ entry: EmojiEntry) {
        frequentEmoji.record(entry.glyph)
        windowController.pasteStringKeepingWindowOpen(entry.display(tone: settings.emojiSkinTone))
    }
}
