import SwiftUI

struct RootPaletteView: View {
    @EnvironmentObject private var core: AppCore
    @EnvironmentObject private var vm: PaletteViewModel
    @EnvironmentObject private var appIndex: AppIndex
    @EnvironmentObject private var store: ClipboardStore
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var visibility: VisibilityStore
    @EnvironmentObject private var aliases: AliasStore
    @EnvironmentObject private var calcHistory: CalculatorHistoryStore
    /// Observed so the inline card re-evaluates the moment a fresh FX snapshot lands, or the user
    /// turns currency conversion on or off.
    @EnvironmentObject private var currencyRates: CurrencyRateStore
    @EnvironmentObject private var emojiIndex: EmojiIndex
    @EnvironmentObject private var frequentEmoji: FrequentEmojiStore
    @EnvironmentObject private var plugins: PluginRegistry
    @ObservedObject private var updates = AppCore.shared.updates
    @ObservedObject private var backgroundTasks = AppCore.shared.backgroundTasks
    /// Observed so a skin tone changed in Settings re-renders the grid glyphs immediately.
    @ObservedObject private var settings = AppCore.shared.settings
    @FocusState private var searchFocused: Bool
    @State private var openMenu: OpenMenu?
    /// The entry whose alias is being edited, if any. Its own state rather than a `PaletteMode`: the launcher stays exactly as it was underneath, and Esc puts the caret back in the search field.
    @State private var aliasTarget: AppEntry?
    @State private var aliasDraft = ""
    @FocusState private var aliasFocused: Bool
    /// The selection's running state, sampled once by `openActions` — an app launching or quitting elsewhere must not add or drop the Quit row while the menu is up. `RunningAppsMonitor` is deliberately not observed here: only `LauncherList` needs live running state, and observing it would re-render the whole palette on every workspace launch/terminate.
    @State private var selectionIsRunning = false
    /// Highlighted row of whichever popover menu is open; reset to the first row on open, moved by ↑/↓ and hover, activated by ↵/click.
    @State private var menuSelection = 0
    /// Hour offset applied only to an adjustable plugin query card; typing another query resets it.
    @State private var pluginQueryHourOffset = 0
    /// Highlighted button of the in-palette confirmation: 0 = Cancel (the default), 1 = the action.
    @State private var confirmSelection = 0
    /// The pending scroll request for whichever list or grid is mounted (modes are exclusive, so one piece of state serves all of them). Set only by keyboard nav and resets; mouse selection targets a visible row, so it leaves this and the scroll position put.
    @State private var scroll = ScrollIntent(kind: .top)

    private var isQueryEmpty: Bool { vm.query.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Slim compact bar vs. full window — the single source of truth lives on `AppCore` so the window controller and this view can never disagree.
    private var isCollapsed: Bool { core.paletteIsCollapsed }

    private var modePlaceholder: String {
        guard let id = activePluginID else { return vm.mode.placeholder }
        return plugins.paletteScreenPlaceholder(for: id) ?? vm.mode.placeholder
    }

    /// Favorite slots shown in the compact bar: up to 5 launchable apps, or the first 4 plus an overflow "…" that expands the window. Evaluated only in the compact render and on the rare ⌘N keypress.
    private var compactFavoriteSlots: [CompactFavoriteSlot] {
        let favs = favorites.ordered(appIndex.matches("").filter(visibility.isVisible)).favorites
        if favs.count <= 5 { return favs.map(CompactFavoriteSlot.app) }
        return favs.prefix(4).map(CompactFavoriteSlot.app) + [.more]
    }

    /// Ordered launcher results (the single source of truth for list, selection and activation): empty query pins favorites to the top, otherwise plain ranked matches.
    private var appResults: [AppEntry] {
        // Visibility filtering stays downstream of `matches` so its one-deep memo cache is never keyed on hidden state; hidden favorites drop out here too.
        let base = appIndex.matches(vm.query)
            .filter(visibility.isVisible)
            .filter { plugins.isCommandEnabled($0.id) }
        guard isQueryEmpty, !favorites.keys.isEmpty else { return base }
        let split = favorites.ordered(base)
        return split.favorites + split.rest
    }
    private var clipResults: [ClipboardItem] {
        store.search(vm.query, filter: vm.clipboardFilter)
    }
    private var histResults: [CalcHistoryEntry] { calcHistory.search(vm.query) }
    private var emojiSections: [EmojiGridSection] {
        EmojiGrid.sections(query: vm.query, index: emojiIndex, frequent: frequentEmoji)
    }
    /// Flat grid order across sections — what `vm.selection` indexes in emoji mode.
    private var emojiResults: [EmojiEntry] { emojiSections.flatMap(\.entries) }
    private var activePluginID: PluginID? { vm.mode.pluginID }
    private var pluginSnapshot: PluginPaletteSnapshot? {
        guard let id = activePluginID else { return nil }
        return plugins.paletteSnapshot(for: id, query: vm.query)
    }
    private var pluginResults: [PluginPaletteItem] { pluginSnapshot?.items ?? [] }

    /// Calculator stays available as core functionality; currency syntax is gated by its plugin.
    private var calcResult: CalcResult? {
        vm.mode == .launcher || vm.mode == .calculatorHistory
            ? CalcMemo.evaluate(vm.query, currency: currencyRates.source) : nil
    }

    private var launcherInlineResult: PaletteInlineResult? {
        let now = Date().addingTimeInterval(TimeInterval(pluginQueryHourOffset * 3_600))
        if let result = plugins.evaluate(vm.query, now: now) { return .plugin(result) }
        return calcResult.map(PaletteInlineResult.calculator)
    }

    private var inlineResult: PaletteInlineResult? {
        switch vm.mode {
        case .launcher: return launcherInlineResult
        case .calculatorHistory: return calcResult.map(PaletteInlineResult.calculator)
        case .clipboard, .emoji, .aiChat, .updates, .plugin: return nil
        }
    }

    private var inlineCount: Int { inlineResult == nil ? 0 : 1 }
    private var launcherFallbackResults: [LauncherFallback] {
        guard vm.mode == .launcher else { return [] }
        return LauncherFallback.suggestions(for: vm.query)
    }
    /// Tasks are a resting-state surface, not a search result: typing a query is asking for something
    /// else, so the rows step aside rather than sitting above every match.
    private var launcherTaskCount: Int {
        vm.mode == .launcher && isQueryEmpty ? backgroundTasks.tasks.count : 0
    }

    private var resultCount: Int {
        switch vm.mode {
        case .launcher:
            return appResults.count + launcherFallbackResults.count + launcherTaskCount + inlineCount
        case .clipboard: return clipResults.count
        case .calculatorHistory: return histResults.count + inlineCount
        case .emoji: return emojiResults.count
        case .aiChat: return 0
        case .updates: return 0
        case .plugin: return pluginResults.count
        }
    }
    /// Selection clamped into the current results — the single source of truth for highlight, preview and activation so the list and preview can never disagree.
    private var selection: Int { resultCount == 0 ? 0 : min(max(vm.selection, 0), resultCount - 1) }

    private var menuOpen: Bool { openMenu != nil }
    private var aliasEditorOpen: Bool { aliasTarget != nil }
    /// The in-palette yes/no overlay. It outranks the menus for every key it owns.
    private var confirmOpen: Bool { vm.confirmation != nil }

    // MARK: - Popover menu content
    //
    // These resolve the current selection for whichever menu is open. They are evaluated only inside the
    // menu overlays (menu visible) or on a keypress (rare), so re-running the unmemoized `appResults`
    // filter here is fine — the same idiom the other rare event handlers use.

    private var selectedInlineResult: PaletteInlineResult? {
        guard inlineCount > 0, selection == launcherTaskCount else { return nil }
        return inlineResult
    }
    private var selectedBackgroundTask: BackgroundTaskItem? {
        guard selection < launcherTaskCount, backgroundTasks.tasks.indices.contains(selection) else {
            return nil
        }
        return backgroundTasks.tasks[selection]
    }
    private var selectedAppEntry: AppEntry? {
        let index = selection - launcherTaskCount - inlineCount
        return appResults.indices.contains(index) ? appResults[index] : nil
    }
    private var selectedLauncherFallback: LauncherFallback? {
        let index = selection - launcherTaskCount - inlineCount - appResults.count
        return launcherFallbackResults.indices.contains(index) ? launcherFallbackResults[index] : nil
    }
    private var selectedClipItem: ClipboardItem? {
        clipResults.indices.contains(selection) ? clipResults[selection] : nil
    }
    private var selectedHistEntry: CalcHistoryEntry? {
        let index = selection - inlineCount
        return histResults.indices.contains(index) ? histResults[index] : nil
    }
    private var selectedEmojiEntry: EmojiEntry? {
        emojiResults.indices.contains(selection) ? emojiResults[selection] : nil
    }
    private var selectedPluginItem: PluginPaletteItem? {
        pluginResults.indices.contains(selection) ? pluginResults[selection] : nil
    }

    /// The bottom-right Actions menu content for the current mode's selection, or nil when the selection has no actions.
    private var actionsContent: PopoverMenuContent? {
        switch vm.mode {
        case .launcher:
            if selectedBackgroundTask != nil { return nil }
            if selectedLauncherFallback != nil { return nil }
            if let inline = selectedInlineResult {
                switch inline {
                case .calculator(let result):
                    guard result.isActionable else { return nil }
                    return CalcActionsMenu.content(result: result, core: core)
                case .plugin(let result):
                    return PluginQueryActionsMenu.content(result: result, core: core)
                }
            }
            if let app = selectedAppEntry {
                return AppActionsMenu.content(
                    app: app, searchQuery: vm.query, core: core, favorites: favorites,
                    running: selectionIsRunning,
                    alias: aliases.alias(for: app),
                    onSetAlias: { openAliasEditor(for: app) },
                    onResetRanking: {
                        core.resetRanking(for: app)
                        // Reset can move the item; keep the highlight on the item whose action ran.
                        if let index = appResults.firstIndex(of: app) {
                            vm.selection = index + launcherTaskCount + inlineCount
                        }
                    })
            }
            return nil
        case .clipboard:
            if let clip = selectedClipItem {
                return ClipboardActionsMenu.content(
                    item: clip, core: core, target: vm.pasteTarget)
            }
            return nil
        case .calculatorHistory:
            if let inline = selectedInlineResult,
                case .calculator(let result) = inline, result.isActionable
            {
                return CalcActionsMenu.content(result: result, core: core)
            }
            if let hist = selectedHistEntry {
                return CalcHistoryActionsMenu.content(
                    entry: hist, core: core, calcHistory: calcHistory)
            }
            return nil
        case .emoji:
            if let emoji = selectedEmojiEntry {
                return EmojiActionsMenu.content(
                    entry: emoji, core: core, target: vm.pasteTarget)
            }
            return nil
        case .aiChat:
            return AIChatActionsMenu.content(core: core)
        case .updates:
            return nil
        case .plugin(let id):
            guard let item = selectedPluginItem else { return nil }
            return plugins.paletteActions(pluginID: id, itemID: item.id)
        }
    }

    /// The bottom-left menu: About/Settings everywhere, the session list in chat mode.
    private var appMenuContent: PopoverMenuContent {
        if vm.mode == .aiChat { return AIChatSessionsMenu.content(core: core) }
        return PopoverMenuContent(items: [
            PopoverMenuItem(title: "About Spotter", systemImage: "info.circle") {
                core.showAbout()
            },
            PopoverMenuItem(title: "Settings", systemImage: "gearshape", shortcut: "⌘,") {
                core.showSettings()
            },
        ])
    }

    /// Which in-window menu owns the keyboard, or nil. One optional rather than a Bool per menu: "exactly one is open" then holds structurally, instead of needing a pairwise handler for every pair.
    private enum OpenMenu {
        case actions
        case app
        case clipboardFilter
    }

    /// Whichever menu is open — the source for keyboard navigation and activation.
    private var menuContent: PopoverMenuContent? {
        switch openMenu {
        case .actions: return actionsContent
        case .app: return appMenuContent
        case .clipboardFilter: return clipboardFilterContent
        case nil: return nil
        }
    }

    /// The clipboard's type filter, as a menu. No search field and no separators: a fixed five rows that open highlighting the active one, the way a pop-up button does.
    private var clipboardFilterContent: PopoverMenuContent {
        PopoverMenuContent(
            header: "Filter by Type",
            items: ClipboardFilter.allCases.map { filter in
                PopoverMenuItem(title: filter.title, systemImage: filter.systemImage) {
                    vm.clipboardFilter = filter
                    vm.selection = 0
                    scroll = ScrollIntent(kind: .top)
                }
            })
    }

    var body: some View {
        // Filter once per render for the active mode only, so the matcher/search doesn't run several times per render (rare event handlers use the computed properties above).
        let apps = vm.mode == .launcher ? appResults : []
        let tasks = vm.mode == .launcher && isQueryEmpty ? backgroundTasks.tasks : []
        let clips = vm.mode == .clipboard ? clipResults : []
        let hist = vm.mode == .calculatorHistory ? histResults : []
        let emojiSections = vm.mode == .emoji ? emojiSections : []
        let emojis = emojiSections.flatMap(\.entries)
        let plugin = activePluginID.flatMap { plugins.paletteSnapshot(for: $0, query: vm.query) }
        let pluginItems = plugin?.items ?? []
        let dashboard = vm.mode == .launcher && isQueryEmpty
            ? plugins.launcherDashboardView() : nil
        // Newest stored clip + the reorder token: the pair changes only when the store mutates, never when a query filters the list.
        let clipFollow = ClipFollowKey(id: store.items.first?.id, token: vm.followToken)
        // Every count/selection below derives from the same task/inline offsets, so the flat index always matches the visible row order.
        let inline = inlineResult
        let fallbacks = vm.mode == .launcher ? LauncherFallback.suggestions(for: vm.query) : []
        let inlineOffset = inline == nil ? 0 : 1
        let taskOffset = tasks.count
        // Only the active mode is non-empty.
        let count =
            apps.count + fallbacks.count + taskOffset + inlineOffset + clips.count + hist.count
            + emojis.count
            + pluginItems.count
        let sel = count == 0 ? 0 : min(max(vm.selection, 0), count - 1)
        let selectedTask = tasks.indices.contains(sel) ? tasks[sel] : nil
        let inlineSelected = inline != nil && sel == taskOffset
        let inlineActionTitle = inlineSelected && inline?.result.isActionable == true
            ? inline?.actionTitle : nil
        let showSections = vm.mode == .launcher && isQueryEmpty
        let favoriteCount =
            showSections ? apps.prefix(while: { favorites.isFavorite($0) }).count : 0
        let appIndex = sel - taskOffset - inlineOffset
        let selectedApp = apps.indices.contains(appIndex) ? apps[appIndex] : nil
        let fallbackIndex = appIndex - apps.count
        let selectedFallback = fallbacks.indices.contains(fallbackIndex)
            ? fallbacks[fallbackIndex] : nil
        let selectedPlugin = pluginItems.indices.contains(sel) ? pluginItems[sel] : nil
        // Derive the footer label from the already-resolved selection so `bottomBar` doesn't re-run `appResults` (its filter/sort aren't memoized). The primary/Actions group is hidden when there's nothing to act on: no results in any mode, or an error calc card (selectable but action-less).
        let pillLabel = actionPillLabel(
            selectedTask: selectedTask, selectedApp: selectedApp, selectedPlugin: selectedPlugin,
            selectedFallback: selectedFallback, inlineActionTitle: inlineActionTitle)
        let showActionGroup = selectedTask.map { $0.isDismissible || backgroundTasks.canOpen(id: $0.id) }
            ?? (((count > 0 || vm.mode == .aiChat)
                && !(inlineSelected && inlineActionTitle == nil))
                || (vm.mode == .updates && updatePrimaryActionTitle != nil))
        let showActionsButton = vm.mode != .updates && selectedTask == nil
            && selectedFallback == nil

        let layout = paletteLayout(
            apps: apps, tasks: tasks, clips: clips, hist: hist, emojiSections: emojiSections,
            inline: inline, fallbacks: fallbacks, plugin: plugin, dashboard: dashboard,
            selection: sel,
            favoriteCount: favoriteCount,
            showSections: showSections, pillLabel: pillLabel,
            showActionGroup: showActionGroup, showActionsButton: showActionsButton
        )
        let statefulLayout = paletteWithStateHandlers(
            layout, clips: clips, clipFollow: clipFollow)
        return paletteWithKeyHandlers(statefulLayout)
    }

    private func paletteLayout(
        apps: [AppEntry], tasks: [BackgroundTaskItem], clips: [ClipboardItem],
        hist: [CalcHistoryEntry],
        emojiSections: [EmojiGridSection], inline: PaletteInlineResult?,
        fallbacks: [LauncherFallback],
        plugin: PluginPaletteSnapshot?, dashboard: AnyView?,
        selection: Int, favoriteCount: Int,
        showSections: Bool, pillLabel: String, showActionGroup: Bool,
        showActionsButton: Bool
    ) -> some View {
        // The `header` (and its single search field) is always attached in the same position via safeAreaInset so its focus survives the compact↔expanded swap — only the results below it toggle. Collapsed shows the bar alone; expanded floats header + action bar over the list with edge-dissolve (see docs/ui.md).
        Group {
            if isCollapsed {
                Color.clear
            } else {
                content(
                    apps: apps, tasks: tasks, clips: clips, hist: hist,
                    emojiSections: emojiSections, inline: inline, fallbacks: fallbacks, plugin: plugin,
                    dashboard: dashboard, selection: selection,
                    favoriteCount: favoriteCount, showSections: showSections
                )
            }
        }
        .safeAreaInset(edge: .top, spacing: Theme.Size.headerContentGap) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isCollapsed {
                bottomBar(
                    pillLabel: pillLabel, showActionGroup: showActionGroup,
                    showActionsButton: showActionsButton)
            }
        }
        // Menus are in-window overlays anchored to a bottom corner, so they stay clipped inside the panel — never a system popover spilling outside the window.
        .overlay {
            if openMenu != nil {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: closeMenus)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if openMenu == .app {
                let content = appMenuContent
                PopoverMenu(
                    header: content.header, items: content.items, selection: $menuSelection,
                    onActivate: activateMenuItem
                )
                .padding(Self.menuInset)
                .transition(Self.menuTransition(.bottomLeading))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if openMenu == .actions, let content = actionsContent {
                PopoverMenu(
                    header: content.header, items: content.items, selection: $menuSelection,
                    onActivate: activateMenuItem
                )
                .padding(Self.menuInset)
                .transition(Self.menuTransition(.bottomTrailing))
            }
        }
        // The filter hangs under its own header button rather than off the footer, so it opens where it was clicked.
        .overlay(alignment: .topTrailing) {
            if openMenu == .clipboardFilter {
                let content = clipboardFilterContent
                PopoverMenu(
                    header: content.header, items: content.items, selection: $menuSelection,
                    width: Self.filterMenuWidth, onActivate: activateMenuItem
                )
                .padding(.top, Theme.Size.headerHeight + Theme.Size.headerPadding)
                .padding(.trailing, Self.menuInset * 2)
                .transition(Self.menuTransition(.topTrailing))
            }
        }
        // The alias editor owns the keyboard through its own focused field, so the click-catcher only has to stop the list and footer from stealing it back.
        .overlay {
            if aliasEditorOpen {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: closeAliasEditor)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let target = aliasTarget {
                AliasEditorCard(
                    entry: target, draft: $aliasDraft, isFocused: $aliasFocused,
                    onSave: commitAlias, onClose: closeAliasEditor
                )
                .padding(Self.menuInset)
                .transition(Self.menuTransition(.bottomTrailing))
            }
        }
        // The in-palette yes/no. Above the menus, dim layer cancels, and Cancel is the ↵ default.
        .overlay {
            if let confirmation = vm.confirmation {
                ZStack {
                    Theme.Colors.panelScrim
                        .contentShape(Rectangle())
                        .onTapGesture { activateConfirmation(false) }
                    ConfirmationCard(
                        confirmation: confirmation, selection: $confirmSelection,
                        onActivate: activateConfirmation)
                }
                .transition(.opacity)
            }
        }
        // The window's own frame (driven by `PaletteWindowController`) is the size source of truth; filling it keeps the glass background and corner clip matched to the current compact/expanded window height.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Colors.panelScrim)
        .background(VisualEffectView())
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
    }

    private func paletteWithStateHandlers<Content: View>(
        _ content: Content, clips: [ClipboardItem], clipFollow: ClipFollowKey
    ) -> some View {
        content
        // Every show bumps focusToken — refocus search and drop any menu left open from last time (e.g. dismissed by clicking away with a context menu up). The scroll snaps home too: a reopen that preserved its state should still start reading from the top.
        .onChange(of: vm.focusToken) {
            aliasTarget = nil
            aliasFocused = false
            searchFocused = vm.mode != .updates
            openMenu = nil
            scroll = ScrollIntent(kind: .top)
        }
        .onChange(of: vm.query) {
            vm.selection = 0
            pluginQueryHourOffset = 0
            scroll = ScrollIntent(kind: .top)
        }
        .onChange(of: vm.mode) {
            vm.selection = 0
            pluginQueryHourOffset = 0
            openMenu = nil
            aliasTarget = nil
            aliasFocused = false
            scroll = ScrollIntent(kind: .top)
            searchFocused = vm.mode != .updates
        }
        // Pop-to-root: `prepare` clears query/selection, but if both were already at their defaults the handlers above never fire — this intent guarantees the scroll itself snaps back to the origin.
        .onChange(of: vm.resetToken) {
            scroll = ScrollIntent(kind: .top)
        }
        // An opening menu always starts with a highlight; the filter starts on the active row the way a pop-up button does, everything else on its first.
        .onChange(of: openMenu) {
            switch openMenu {
            case .clipboardFilter:
                menuSelection = ClipboardFilter.allCases.firstIndex(of: vm.clipboardFilter) ?? 0
            case .actions, .app:
                menuSelection = 0
            case nil:
                break
            }
            vm.resetMenuTypeahead()
            syncMenuInputState()
        }
        // The confirmation rides the same input-freeze channel as the menus: caret hidden, typing swallowed, nav keys through. Highlight always starts on Cancel.
        .onChange(of: confirmOpen) {
            if confirmOpen {
                closeMenus()
                confirmSelection = 0
            }
            syncMenuInputState()
        }
        .onChange(of: vm.menuTypeaheadQuery) {
            guard openMenu == .actions, let items = actionsContent?.items,
                let index = PaletteMenuTypeahead.bestMatch(
                    query: vm.menuTypeaheadQuery, titles: items.map(\.title))
            else { return }
            menuSelection = index
        }
        // Follow a row the store moved: a fresh capture (or promote-on-paste) lands at the head of its section, and pinning lifts a row into the Pinned section. With a query typed the highlight stays put; `AppCore` has already placed it for pin/paste.
        .onChange(of: clipFollow) { old, new in
            // A nil `old.id` is the first load landing, not a row that moved.
            guard vm.mode == .clipboard, old.id != nil else { return }
            if isQueryEmpty, old.id != new.id, let id = new.id,
                let index = clips.firstIndex(where: { $0.id == id })
            {
                vm.selection = index
            }
            scroll = ScrollIntent(kind: .follow)
        }
        // ⌘. reaches us as a token because AppKit gives the chord to the field editor; the row still comes from the same results the list renders.
        .onChange(of: vm.pinChordToken) {
            guard vm.mode == .clipboard, clips.indices.contains(selection) else { return }
            core.togglePinnedClip(clips[selection])
        }
        // Shift-Tab reaches us as a token for the same reason ⌘. does: AppKit gives the chord to the field editor before `onKeyPress` can see it.
        .onChange(of: vm.backTabToken) { handleTab(shift: true) }
        // Hyper-C: hand the typed draft to ChatGPT on the web, from the launcher or the chat composer.
        .onChange(of: vm.chatGPTChordToken) {
            guard vm.mode == .aiChat || vm.mode == .launcher else { return }
            sendChatGPTMessage()
        }
        .onAppear { searchFocused = vm.mode != .updates }
        // Typing/clearing/overflow/settings all flip `paletteIsCollapsed`; resize the window to match.
        .onChange(of: core.paletteIsCollapsed) { core.syncPaletteSize() }
    }

    private func paletteWithKeyHandlers<Content: View>(_ content: Content) -> some View {
        content
        // ⌘1–⌘5 launch the compact bar's favorite slots (or expand, for the "…" overflow slot).
        .onKeyPress(keys: ["1", "2", "3", "4", "5"], phases: .down) { press in
            guard !aliasEditorOpen, isCollapsed, settings.showFavoritesInCompactMode,
                press.modifiers.contains(.command),
                let digit = press.key.character.wholeNumberValue
            else { return .ignored }
            let slots = compactFavoriteSlots
            let index = digit - 1
            guard slots.indices.contains(index) else { return .ignored }
            switch slots[index] {
            case .app(let app): core.launch(app)
            case .more: core.expandFromCompact()
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if confirmOpen || aliasEditorOpen { return .handled }
            if isCollapsed {
                // The compact bar has no visible selection; Down reveals the list at its first row
                // while the shared search field stays mounted and focused.
                vm.selection = 0
                core.expandFromCompact()
                return .handled
            }
            if menuOpen {
                moveMenu(1)
                return .handled
            }
            if vm.mode == .emoji { moveEmojiRow(1) } else { move(1) }
            return .handled
        }
        .onKeyPress(.upArrow) {
            if confirmOpen || aliasEditorOpen { return .handled }
            if isCollapsed { return .ignored }
            if menuOpen {
                moveMenu(-1)
                return .handled
            }
            if vm.mode == .emoji { moveEmojiRow(-1) } else { move(-1) }
            return .handled
        }
        // Horizontal arrows step the emoji grid and adjust an hourly inline card (← rewinds, → advances — ↑/↓ stay pure list navigation); everywhere else they stay with the field editor's caret. An open menu swallows them so the list behind never moves.
        .onKeyPress(.leftArrow) {
            if confirmOpen {
                confirmSelection = 0
                return .handled
            }
            if aliasEditorOpen { return .ignored }
            if menuOpen { return .handled }
            if adjustPluginQueryHour(by: -1) { return .handled }
            if adjustPluginScreenHour(by: -1) { return .handled }
            guard vm.mode == .emoji else { return .ignored }
            move(-1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            if confirmOpen {
                confirmSelection = 1
                return .handled
            }
            if aliasEditorOpen { return .ignored }
            if menuOpen { return .handled }
            if adjustPluginQueryHour(by: 1) { return .handled }
            if adjustPluginScreenHour(by: 1) { return .handled }
            guard vm.mode == .emoji else { return .ignored }
            move(1)
            return .handled
        }
        // With a menu open, plain ↵ activates its highlighted row. A modified ↵ always runs the selection's own action regardless of menu state: ⌘↵ the advertised secondary action, ⌥↵ paste-in-place; plain ↵ (no menu) falls through to the field's onSubmit.
        .onKeyPress(keys: [.return], phases: .down) { press in
            if aliasEditorOpen { return .handled }
            let command = press.modifiers.contains(.command)
            let option = press.modifiers.contains(.option)
            if confirmOpen {
                activateConfirmation(confirmSelection == 1)
                return .handled
            }
            if menuOpen, !command, !option {
                activateMenuItem(menuSelection)
                return .handled
            }
            guard command || option else { return .ignored }
            switch vm.mode {
            case .emoji:
                guard emojiResults.indices.contains(selection) else { return .ignored }
                if command {
                    core.copyEmoji(emojiResults[selection])
                } else {
                    core.pasteEmojiKeepingWindowOpen(emojiResults[selection])
                }
            case .clipboard:
                guard command, clipResults.indices.contains(selection) else { return .ignored }
                core.copyToClipboard(clipResults[selection])
            case .calculatorHistory:
                // The inline calc card (index 0 when present) has no secondary action; only stored entries respond.
                let index = selection - inlineCount
                guard command, histResults.indices.contains(index) else { return .ignored }
                core.copyHistoryExpression(histResults[index])
            case .launcher:
                guard command, let app = selectedAppEntry, app.canRevealInFinder
                else { return .ignored }
                core.showInFinder(app)
            case .plugin(let id):
                guard command, let item = selectedPluginItem,
                    plugins.performPaletteSecondaryAction(pluginID: id, itemID: item.id)
                else { return .ignored }
            case .aiChat, .updates:
                return .ignored
            }
            return .handled
        }
        .onKeyPress(.escape) {
            if confirmOpen {
                activateConfirmation(false)
                return .handled
            }
            if aliasEditorOpen {
                closeAliasEditor()
                return .handled
            }
            if openMenu != nil {
                closeMenus()
                return .handled
            }
            // Esc backs out one layer, matching Raycast: sub-screen → launcher, typed query →
            // cleared; only Esc at the empty launcher root dismisses the palette. A multi-level
            // plugin screen consumes the step first (1Password's item view → its list).
            if case .plugin(let id) = vm.mode, plugins.performPaletteBack(pluginID: id) {
                return .handled
            }
            if vm.mode != .launcher {
                exitToLauncher()
                return .handled
            }
            if !vm.query.isEmpty {
                vm.query = ""
                vm.selection = 0
                return .handled
            }
            core.hidePalette()
            return .handled
        }
        .onKeyPress(keys: [.tab], phases: .down) { press in
            handleTab(shift: press.modifiers.contains(.shift))
            return .handled
        }
        .onKeyPress(keys: [","], phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            core.showSettings()
            return .handled
        }
        // ⌘K toggles the actions panel for the current selection.
        .onKeyPress(keys: ["k"], phases: .down) { press in
            guard press.modifiers.contains(.command), !aliasEditorOpen else { return .ignored }
            // The Actions menu has no anchor in the compact bar (no bottom bar); swallow ⌘K there.
            guard !isCollapsed else { return .handled }
            // Chat has no selectable rows but a fixed menu; every other mode needs a selection.
            guard resultCount > 0 || vm.mode == .aiChat else { return .handled }
            if selectedBackgroundTask != nil { return .handled }
            // An informational inline card can be selected without exposing an empty actions panel.
            if inlineCount > 0, selection == launcherTaskCount,
                inlineResult?.result.isActionable != true
            {
                return .handled
            }
            if selectedLauncherFallback != nil { return .handled }
            toggleActions()
            return .handled
        }
        // Bare backspace (back out of a sub-screen when the search is empty) is intercepted by PalettePanel.sendEvent — the field editor consumes it before onKeyPress could fire.
        .onKeyPress(keys: [.delete, .deleteForward], phases: .down) { press in
            if menuOpen { return .handled }
            guard press.modifiers.contains(.command) else { return .ignored }
            switch vm.mode {
            case .clipboard:
                deleteSelectedClip()
            case .calculatorHistory:
                deleteSelectedHistoryEntry()
            case .launcher, .emoji, .aiChat, .updates, .plugin:
                return .ignored
            }
            return .handled
        }
        // ⌘N starts a fresh chat session — the same action as the session menu's top row, and like
        // the other advertised chords it works while a footer menu is open.
        .onKeyPress(keys: ["n"], phases: .down) { press in
            guard press.modifiers.contains(.command), vm.mode == .aiChat, !aliasEditorOpen
            else { return .ignored }
            core.aiChat.startNewSession()
            vm.query = ""
            vm.selection = 0
            closeMenus()
            return .handled
        }
        // ⌘P opens the clipboard's type filter; the pin it used to serve moved to ⌘. (see `pinChordToken`), so one chord keeps one meaning app-wide.
        .onKeyPress(keys: ["p"], phases: .down) { press in
            guard press.modifiers.contains(.command), vm.mode == .clipboard, !isCollapsed,
                !aliasEditorOpen
            else { return .ignored }
            toggleClipboardFilter()
            return .handled
        }
        // Both cases are listed because Shift uppercases the reported key. The compact bar is excluded like ⌘K — it shows no selection to aim a destructive action at.
        .onKeyPress(keys: ["q", "Q"], phases: .down) { press in
            guard press.modifiers.contains(.control), press.modifiers.contains(.shift),
                !isCollapsed, !aliasEditorOpen, vm.mode == .launcher, let app = selectedAppEntry,
                app.kind == .application, core.runningApps.isRunning(app)
            else { return .ignored }
            core.quit(app)
            return .handled
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            // A Tab-cycle stop shows its own mode glyph, so the header names the surface you are on
            // rather than offering a way back out of it. Every other mode is a sub-screen of the root
            // search and keeps the back chevron. The swap is instant — it fires on every Tab, and a
            // transition there reads as lag, not as polish.
            if modeCycle.contains(vm.mode) {
                Button { cycleMode(forward: true) } label: {
                    Image(systemName: vm.mode.systemImage)
                        .font(Theme.Typography.headerIcon)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .frame(width: Theme.Size.headerIconSlot)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // Nothing in the palette is reachable by focus-walking — the search field is the one first responder, and a focus ring here would be a stray control appearing mid-typing.
                .focusable(false)
                .help("Switch surface (⇥)")
            } else {
                Button(action: backOneLevel) {
                    Image(systemName: "chevron.left")
                        .font(Theme.Typography.headerIcon)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .frame(width: Theme.Size.headerIconSlot)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if vm.mode == .updates {
                Text(vm.mode.title)
                    .font(Theme.Typography.searchField)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                searchField
            }
            // The clipboard's type filter sits at the trailing edge of its own search bar, where it filters.
            if vm.mode == .clipboard, !isCollapsed {
                ClipboardFilterButton(
                    filter: vm.clipboardFilter, isOpen: openMenu == .clipboardFilter,
                    action: toggleClipboardFilter)
            }
            // Compact bar pins favorites to the right of the field; expanded shows them as list rows instead.
            if isCollapsed, settings.showFavoritesInCompactMode {
                let slots = compactFavoriteSlots
                if !slots.isEmpty {
                    CompactFavoritesRow(
                        slots: slots,
                        onLaunch: { core.launch($0) },
                        onOverflow: { core.expandFromCompact() }
                    )
                }
            }
        }
        // Align the search icon with the list rows and section headers below (list inset + row inset).
        .padding(.horizontal, Theme.Spacing.md * 2)
        // Fixed row height + top padding, identical in both states, so typing (which flips compact→expanded) can't move the search bar. Compact centers the row in symmetric slack; expanded floats the same row over the list.
        .frame(height: Theme.Size.headerHeight)
        .padding(.top, Theme.Size.headerPadding)
        .frame(maxWidth: .infinity)
    }

    /// The one search field, kept in a single tree position (the `header`) so its focus survives the compact↔expanded swap.
    private var searchField: some View {
        TextField(
            "", text: $vm.query,
            prompt: Text(modePlaceholder).foregroundStyle(Theme.Colors.textTertiary)
        )
        .textFieldStyle(.plain)
        .font(Theme.Typography.searchField)
        .tint(.primary)
        .focused($searchFocused)
        .onSubmit(activateSelection)
    }

    @ViewBuilder
    private func content(
        apps: [AppEntry], tasks: [BackgroundTaskItem], clips: [ClipboardItem],
        hist: [CalcHistoryEntry],
        emojiSections: [EmojiGridSection], inline: PaletteInlineResult?,
        fallbacks: [LauncherFallback],
        plugin: PluginPaletteSnapshot?, dashboard: AnyView?,
        selection: Int, favoriteCount: Int, showSections: Bool
    ) -> some View {
        switch vm.mode {
        case .launcher:
            let taskOffset = tasks.count
            let inlineOffset = inline == nil ? 0 : 1
            let selectedTask = tasks.indices.contains(selection) ? tasks[selection] : nil
            let inlineSelected = inline != nil && selection == taskOffset
            let appIndex = selection - taskOffset - inlineOffset
            let selectedID = apps.indices.contains(appIndex) ? apps[appIndex].id : nil
            let fallbackIndex = appIndex - apps.count
            let selectedFallbackID = fallbacks.indices.contains(fallbackIndex)
                ? fallbacks[fallbackIndex].id : nil
            LauncherList(
                results: apps,
                selectedID: selectedTask == nil && !inlineSelected ? selectedID : nil,
                favoriteCount: favoriteCount,
                showSections: showSections,
                scroll: scroll,
                backgroundTasks: tasks,
                inline: inline,
                dashboard: dashboard,
                fallbacks: fallbacks,
                selectedTaskID: selectedTask?.id,
                inlineSelected: inlineSelected,
                selectedFallbackID: selectedFallbackID,
                onActivateTask: { task in
                    guard let index = tasks.firstIndex(of: task) else { return }
                    vm.selection = index
                    activateSelection()
                },
                onActivateInline: {
                    vm.selection = taskOffset
                    activateSelection()
                },
                onInlineActions: {
                    guard inline?.result.isActionable == true else { return }
                    vm.selection = taskOffset
                    openActions()
                },
                onActivateFallback: { fallback in
                    guard let index = fallbacks.firstIndex(of: fallback) else { return }
                    vm.selection = taskOffset + inlineOffset + apps.count + index
                    core.performLauncherFallback(fallback)
                },
                onActivate: { core.launch($0, searchQuery: vm.query) },
                onActions: { app in
                    if let index = apps.firstIndex(of: app) {
                        vm.selection = index + taskOffset + inlineOffset
                    }
                    openActions()
                }
            )
        case .clipboard:
            // Empty history: center one message across the whole panel rather than wedging it into the narrow list column beside a blank preview.
            if clips.isEmpty {
                EmptyResults(text: vm.clipboardFilter.emptyMessage)
            } else {
                let selected = clips.indices.contains(selection) ? clips[selection] : nil
                HStack(spacing: 0) {
                    ClipboardList(
                        results: clips,
                        selectedID: selected?.id,
                        scroll: scroll,
                        onSelect: { item in vm.selection = clips.firstIndex(of: item) ?? 0 },
                        onActivate: activateSelection,
                        onActions: { item in
                            if let index = clips.firstIndex(of: item) { vm.selection = index }
                            openActions()
                        }
                    )
                    .frame(width: Theme.Size.clipboardListWidth)
                    Rectangle()
                        .fill(Theme.Colors.separator)
                        .frame(width: 1)
                    ClipboardPreview(item: selected)
                }
            }
        case .calculatorHistory:
            let calc = inline?.result
            if hist.isEmpty && calc == nil {
                EmptyResults(
                    text: isQueryEmpty ? "No calculations yet" : "No matching calculations")
            } else {
                let offset = calc == nil ? 0 : 1
                let calcSelected = calc != nil && selection == 0
                let histIndex = selection - offset
                let selected = hist.indices.contains(histIndex) ? hist[histIndex] : nil
                CalculatorHistoryList(
                    results: hist,
                    selectedID: calcSelected ? nil : selected?.id,
                    scroll: scroll,
                    calc: calc,
                    calcSelected: calcSelected,
                    onActivateCalc: {
                        vm.selection = 0
                        activateSelection()
                    },
                    onCalcActions: {
                        guard let calc, case .value = calc.payload else { return }
                        vm.selection = 0
                        openActions()
                    },
                    onSelect: { entry in
                        if let index = hist.firstIndex(of: entry) { vm.selection = index + offset }
                    },
                    onActivate: activateSelection,
                    onActions: { entry in
                        if let index = hist.firstIndex(of: entry) { vm.selection = index + offset }
                        openActions()
                    }
                )
            }
        case .aiChat:
            AIChatView(chat: core.aiChat, scroll: scroll)
        case .updates:
            UpdatePaletteView()
        case .emoji:
            if !emojiIndex.isLoaded {
                EmptyResults(text: "Loading emoji…")
            } else if emojiSections.isEmpty {
                EmptyResults(text: "No emoji found")
            } else {
                EmojiGridView(
                    sections: emojiSections,
                    selection: selection,
                    tone: settings.emojiSkinTone,
                    scroll: scroll,
                    onSelect: { vm.selection = $0 },
                    onActivate: activateSelection,
                    onActions: { flat in
                        vm.selection = flat
                        openActions()
                    }
                )
            }
        case .plugin:
            if let error = plugin?.errorMessage {
                EmptyResults(text: error)
            } else if plugin?.isLoading == true, plugin?.items.isEmpty == true {
                EmptyResults(text: plugin?.loadingMessage ?? "Loading…")
            } else if let plugin, plugin.items.isEmpty {
                EmptyResults(text: plugin.emptyMessage)
            } else if let plugin {
                let selected = plugin.items.indices.contains(selection) ? plugin.items[selection] : nil
                PluginPaletteList(
                    sectionTitle: plugin.sectionTitle,
                    items: plugin.items,
                    selectedID: selected?.id,
                    scroll: scroll,
                    onActivate: { item in
                        if let index = plugin.items.firstIndex(of: item) { vm.selection = index }
                        activateSelection()
                    },
                    onActions: { item in
                        if let index = plugin.items.firstIndex(of: item) { vm.selection = index }
                        openActions()
                    })
            } else {
                EmptyResults(text: "Plugin unavailable")
            }
        }
    }

    private func bottomBar(
        pillLabel: String, showActionGroup: Bool, showActionsButton: Bool
    ) -> some View {
        // No bar — just floating glass controls over the list; the edge dissolve ghosts rows passing beneath, so the buttons read clearly without a hard-edged strip.
        HStack(spacing: 0) {
            appMenuButton
            Spacer()
            if showActionGroup {
                actionGroup(pillLabel: pillLabel, showActionsButton: showActionsButton)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: Theme.Size.bottomBarHeight)
        .frame(maxWidth: .infinity)
    }

    private var appMenuButton: some View {
        MenuCircleButton {
            withAnimation(Self.menuAnimation) { openMenu = openMenu == .app ? nil : .app }
        }
    }

    /// The footer control group: primary action and the Actions toggle sharing one glass capsule.
    private func actionGroup(pillLabel: String, showActionsButton: Bool) -> some View {
        HStack(spacing: 2) {
            if vm.mode == .aiChat {
                BarButton(action: sendChatMessage) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Text(pillLabel)
                            .font(Theme.Typography.bar)
                            .foregroundStyle(.primary)
                        KeyCapChip(text: "Tab", style: .outline)
                    }
                }
                BarButton(action: sendChatGPTMessage) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Text("ChatGPT")
                            .font(Theme.Typography.bar)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        HStack(spacing: Theme.Spacing.xxs) {
                            KeyCapChip(text: "⇧", style: .outline)
                            KeyCapChip(text: "Tab", style: .outline)
                        }
                    }
                }
            } else {
                BarButton(action: activateSelection) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Text(pillLabel)
                            .font(Theme.Typography.bar)
                            .foregroundStyle(.primary)
                        KeyCapChip(text: "↵", style: .outline)
                    }
                }
            }
            if showActionsButton {
                BarButton(action: toggleActions) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Text("Actions")
                            .font(Theme.Typography.bar)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        HStack(spacing: Theme.Spacing.xxs) {
                            KeyCapChip(text: "⌘", style: .outline)
                            KeyCapChip(text: "K", style: .outline)
                        }
                    }
                }
            }
        }
        .padding(Theme.Spacing.xs)
        .frosted(in: Capsule())
    }

    /// Pill label for the current selection, derived from the selection already resolved in `body` so it never re-runs the (unmemoized) `appResults` filter/sort.
    private func actionPillLabel(
        selectedTask: BackgroundTaskItem?, selectedApp: AppEntry?,
        selectedPlugin: PluginPaletteItem?, selectedFallback: LauncherFallback?,
        inlineActionTitle: String?
    ) -> String {
        switch vm.mode {
        case .clipboard, .emoji:
            return vm.pasteTarget?.pasteTitle ?? "Paste"
        case .aiChat:
            return core.aiChat.isWaiting ? "Thinking…" : "Send"
        case .updates:
            return updatePrimaryActionTitle ?? "Check Again"
        case .calculatorHistory:
            return "Copy Answer"
        case .launcher:
            if let selectedTask {
                if selectedTask.isDismissible { return "Dismiss" }
                if backgroundTasks.canOpen(id: selectedTask.id) { return "Open" }
            }
            if let inlineActionTitle { return inlineActionTitle }
            if let selectedFallback { return selectedFallback.action.title }
            switch selectedApp?.kind {
            case .systemSettings: return "Open System Setting"
            case .command: return "Run Command"
            default: return "Open Application"
            }
        case .plugin:
            return selectedPlugin?.primaryActionTitle ?? "Run Action"
        }
    }

    private var updatePrimaryActionTitle: String? {
        switch updates.status {
        case .idle: "Check for Updates"
        case .checking, .installing: nil
        case .upToDate: "Check Again"
        case .available(let release): release.zipAssetURL == nil ? "View Release" : "Install Update"
        case .failed: "Try Again"
        }
    }

    /// The single path that opens the Actions menu: samples the state its rows depend on, then shows it. Callers set `vm.selection` first, so the sample matches the row the menu is for.
    private func openActions() {
        // Only the launcher's menu carries a Quit row, so the other modes skip the (unmemoized) `appResults` walk entirely.
        if vm.mode == .launcher, let app = selectedAppEntry {
            selectionIsRunning = core.runningApps.isRunning(app)
        } else {
            selectionIsRunning = false
        }
        withAnimation(Self.menuAnimation) { openMenu = .actions }
    }

    private func toggleActions() {
        if openMenu == .actions {
            withAnimation(Self.menuAnimation) { openMenu = nil }
        } else {
            openActions()
        }
    }

    private func toggleClipboardFilter() {
        withAnimation(Self.menuAnimation) {
            openMenu = openMenu == .clipboardFilter ? nil : .clipboardFilter
        }
    }

    private func closeMenus() {
        withAnimation(Self.menuAnimation) { openMenu = nil }
    }

    /// ⌘K hands off to the editor in place: the menu closes, the card takes its corner, and the caret moves into the card's own field.
    private func openAliasEditor(for entry: AppEntry) {
        aliasDraft = aliases.alias(for: entry) ?? ""
        withAnimation(Self.menuAnimation) {
            openMenu = nil
            aliasTarget = entry
        }
        searchFocused = false
        aliasFocused = true
    }

    /// The one commit path — ↵ or the Save button. A draft that is blank once trimmed removes the alias, which is how an alias is cleared.
    private func commitAlias() {
        guard let target = aliasTarget else { return }
        let removing = aliasDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hadAlias = aliases.alias(for: target) != nil
        aliases.setAlias(aliasDraft, for: target.preferenceKey)
        closeAliasEditor()
        guard !removing || hadAlias else { return }
        core.hud.show(
            title: removing ? "Alias Removed" : "Alias Set",
            symbol: removing ? "tag.slash" : "tag")
    }

    private func closeAliasEditor() {
        withAnimation(Self.menuAnimation) { aliasTarget = nil }
        aliasDraft = ""
        aliasFocused = false
        searchFocused = vm.mode != .updates
    }

    private func syncMenuInputState() {
        vm.menuOpen = menuOpen || confirmOpen
        vm.menuTypeaheadEnabled = openMenu == .actions && !confirmOpen
    }

    /// Inset of the menu panels from the window's bottom corners, kept just inside the rounded corner so the menu's own corner isn't clipped.
    private static let menuInset: CGFloat = 8
    private static let menuAnimation: Animation = .easeOut(duration: Theme.Animation.quick)
    /// Narrower than the footer menus: five fixed rows of two words each.
    private static let filterMenuWidth: CGFloat = 196

    private static func menuTransition(_ anchor: UnitPoint) -> AnyTransition {
        .opacity.combined(with: .scale(scale: 0.96, anchor: anchor))
    }

    private func deleteSelectedClip() {
        guard clipResults.indices.contains(selection) else { return }
        core.confirmDeleteClip(clipResults[selection])
    }

    private func deleteSelectedHistoryEntry() {
        let index = selection - inlineCount  // the inline card can't be deleted
        guard histResults.indices.contains(index) else { return }
        calcHistory.remove(histResults[index])
    }

    // MARK: - Actions

    private func move(_ delta: Int) {
        guard resultCount > 0 else { return }
        vm.selection = min(max(selection + delta, 0), resultCount - 1)
        scroll = ScrollIntent(kind: .follow)
    }

    /// ← rewinds and → advances the represented instant by one hour while an hourly inline card is selected. Deliberately takes the horizontal arrows from the field editor's caret in that state — retyping resets the offset, and ↑/↓ keep moving the flat selection.
    private func adjustPluginQueryHour(by delta: Int) -> Bool {
        guard vm.mode == .launcher,
            selectedInlineResult?.pluginResult?.supportsHourlyAdjustment == true
        else { return false }
        pluginQueryHourOffset += delta
        return true
    }

    /// The palette-screen sibling of the hourly card: ←/→ scrub a plugin screen that opts in (World
    /// Clock), but only while the query is empty so a typed filter keeps its caret movement.
    private func adjustPluginScreenHour(by delta: Int) -> Bool {
        guard vm.query.isEmpty, let id = activePluginID,
            let adjust = plugins.paletteHourAdjustment(for: id)
        else { return false }
        adjust(delta)
        return true
    }

    /// The single activation path for the confirmation overlay, shared by keys and clicks.
    private func activateConfirmation(_ confirmed: Bool) {
        guard let confirmation = vm.confirmation else { return }
        vm.confirmation = nil
        if confirmed { confirmation.onConfirm() }
    }

    /// Move the open menu's highlight, clamped at the ends (no wrap — consistent with `move`).
    private func moveMenu(_ delta: Int) {
        guard let count = menuContent?.items.count, count > 0 else { return }
        menuSelection = min(max(menuSelection + delta, 0), count - 1)
    }

    /// The single activation path for a menu row, shared by a click and Return: run the row's action, then close.
    private func activateMenuItem(_ index: Int) {
        guard let items = menuContent?.items, items.indices.contains(index) else { return }
        items[index].action()
        closeMenus()
    }

    /// Vertical grid move: one visual row within a section, spilling into the neighbor while keeping the column.
    private func moveEmojiRow(_ delta: Int) {
        let geometry = EmojiGridGeometry(
            counts: emojiSections.map(\.entries.count), columns: EmojiGrid.columns)
        guard resultCount > 0 else { return }
        vm.selection = delta > 0 ? geometry.down(from: selection) : geometry.up(from: selection)
        scroll = ScrollIntent(kind: .follow)
    }

    /// Tab and Shift-Tab in one place: the plain chord arrives through `onKeyPress`, the shifted one
    /// as `backTabToken` (AppKit hands Shift-Tab to the field editor), and both must mean the same
    /// thing everywhere — a confirmation or an open menu owns the chord before any cycling happens.
    private func handleTab(shift: Bool) {
        if aliasEditorOpen { return }
        if confirmOpen {
            confirmSelection = confirmSelection == 0 ? 1 : 0
            return
        }
        if menuOpen { return }
        let hasDraft = !vm.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasDraft, !shift, vm.mode == .aiChat {
            sendChatMessage()
            return
        }
        // Shift-Tab is always the backward cycle; the ChatGPT web handoff lives on ⌃⌥⌘C.
        cycleMode(forward: !shift)
    }

    /// The Tab cycle's stops for the current plugin set; also decides which modes get the header disc.
    private var modeCycle: [PaletteMode] { PaletteMode.cycle(isPluginEnabled: plugins.isEnabled) }

    /// Tab walks the empty root surfaces forward, Shift-Tab backward, so any stop is at most one
    /// press away in some direction. A typed launcher query starts a fresh AI Chat turn instead, and
    /// a sub-screen (which is not a stop) exits to the launcher.
    private func cycleMode(forward: Bool) {
        let cycle = modeCycle
        guard cycle.count > 1 else { return }
        guard let index = cycle.firstIndex(of: vm.mode) else {
            vm.prepare(mode: .launcher)
            return
        }
        let step = forward ? 1 : cycle.count - 1
        let next = cycle[(index + step) % cycle.count]
        // Chat carries the draft in; every other stop arrives fresh. `prepare` rather than a bare
        // mode assignment: each surface has its own row order, so a selection carried across would
        // point at the wrong row.
        if next == .aiChat {
            // Only the launcher's query is a question worth asking; a clipboard or emoji filter
            // string arriving as a chat prompt would be a stray message nobody typed.
            enterChat(prompt: vm.mode == .launcher ? vm.query : "")
        } else {
            vm.prepare(mode: next)
        }
    }

    /// Tab's chat contract: always a fresh session, and typed content is sent on arrival — type a
    /// question in the launcher, Tab, and it's already asked. Without a key the text stays in the
    /// composer next to the add-a-key notice.
    private func enterChat(prompt: String) {
        vm.selection = 0
        core.startAIChat(prompt: prompt)
    }

    /// The chat composer is the shared search field: Tab or ↵ sends through Spotter and clears it.
    private func sendChatMessage() {
        let text = vm.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !core.aiChat.isWaiting else { return }
        if core.aiChat.send(text) { vm.query = "" }
    }

    /// Hyper-C hands the draft to a new ChatGPT web query and lets the browser own the session.
    private func sendChatGPTMessage() {
        let text = vm.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if core.sendAIChatPromptToChatGPT(text) { vm.query = "" }
    }

    /// Back out to a fresh root search — `prepare` is the same reset used when the palette is shown (clears query/selection, bumps focusToken to refocus the field).
    private func exitToLauncher() {
        vm.prepare(mode: .launcher)
    }

    /// The header chevron steps a multi-level plugin screen back one level before leaving it.
    private func backOneLevel() {
        if case .plugin(let id) = vm.mode, plugins.performPaletteBack(pluginID: id) { return }
        exitToLauncher()
    }

    private func activateSelection() {
        // Nothing is visibly selected in the collapsed compact bar; launch only via ⌘1–⌘5 or by typing.
        guard !isCollapsed else { return }
        switch vm.mode {
        case .launcher:
            if let task = selectedBackgroundTask {
                // Running: jump to the surface doing the work. Finished: the only action is Dismiss.
                if !backgroundTasks.open(id: task.id) { backgroundTasks.dismiss(id: task.id) }
                return
            }
            if let inline = selectedInlineResult {
                activate(inline)
                return
            }
            let index = selection - launcherTaskCount - inlineCount
            if appResults.indices.contains(index) {
                core.launch(appResults[index], searchQuery: vm.query)
                return
            }
            let fallbackIndex = index - appResults.count
            guard launcherFallbackResults.indices.contains(fallbackIndex) else { return }
            core.performLauncherFallback(launcherFallbackResults[fallbackIndex])
        case .clipboard:
            guard clipResults.indices.contains(selection) else { return }
            core.paste(clipResults[selection])
        case .calculatorHistory:
            if let calcResult, selection == 0 {
                // A fresh calculation typed into the history search: copy + record like the launcher card (error cards no-op).
                core.copyCalculatorResult(calcResult)
                return
            }
            let index = selection - inlineCount
            guard histResults.indices.contains(index) else { return }
            core.copyHistoryEntry(histResults[index])
        case .emoji:
            guard emojiResults.indices.contains(selection) else { return }
            core.pasteEmoji(emojiResults[selection])
        case .aiChat:
            sendChatMessage()
        case .updates:
            core.performUpdatePrimaryAction()
        case .plugin(let id):
            guard pluginResults.indices.contains(selection) else { return }
            plugins.performPalettePrimaryAction(pluginID: id, itemID: pluginResults[selection].id)
        }
    }

    private func activate(_ inline: PaletteInlineResult) {
        switch inline {
        case .calculator(let result):
            core.copyCalculatorResult(result)
        case .plugin(let result):
            core.copyPluginQueryResult(result)
        }
    }
}

/// Change key for the clipboard list's follow-the-moved-row handler: the newest stored clip (a capture or promote puts a different row there) plus the token an action bumps when it reorders the list (pin/unpin). Deliberately read from the store, not the filtered results, so typing a query never reads as a row that moved.
private struct ClipFollowKey: Equatable {
    let id: ClipboardItem.ID?
    let token: UUID
}

/// The footer's glass menu circle; hover lives here so a mouse sweep never re-renders the palette body.
private struct MenuCircleButton: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Capsule().frame(width: 14, height: 1.5)
                Capsule().frame(width: 8, height: 1.5)
            }
            .foregroundStyle(Theme.Colors.textSecondary)
            .frame(width: Theme.Size.menuButton, height: Theme.Size.menuButton)
            .background(Circle().fill(hovered ? Theme.Colors.rowHover : Color.clear))
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .frosted(in: Circle())
    }
}

/// The clipboard header's type-filter control: states the active filter, opens the menu that changes it. `.help()` rather than the in-house `Tooltip`, which renders above its view and would clip at the panel's top edge.
private struct ClipboardFilterButton: View {
    let filter: ClipboardFilter
    let isOpen: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xxs) {
                Image(systemName: filter.systemImage)
                    .font(Theme.Typography.bar)
                    .symbolRenderingMode(.hierarchical)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(
                filter == .all ? Theme.Colors.textSecondary : Color.primary
            )
            .padding(.horizontal, Theme.Spacing.sm)
            .frame(height: 26)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.menuRow, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.menuRow, style: .continuous)
                    .fill(hovered || isOpen ? Theme.Colors.rowHover : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help("\(filter.title) (⌘P)")
    }
}

/// Footer button: bare label at rest, a faint capsule fill on hover.
private struct BarButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: Label
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            label
                .padding(.horizontal, Theme.Spacing.md)
                .frame(height: 28)
                .contentShape(Capsule())
                .background(Capsule().fill(hovered ? Theme.Colors.rowHover : Color.clear))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

extension View {
    /// Faint mouse-hover highlight for a palette row, lit only while the pointer is physically moving (`hoverHighlightArmed`) so it never fires on open or when rows slide under a still pointer during keyboard nav. Independent of the keyboard selection, so both coexist.
    func armedHover(_ hovered: Binding<Bool>) -> some View {
        onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active: hovered.wrappedValue = AppCore.shared.palette.hoverHighlightArmed
            case .ended: hovered.wrappedValue = false
            }
        }
    }
}

struct EmptyResults: View {
    let text: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.largeTitle)
                .symbolRenderingMode(.hierarchical).foregroundStyle(.tertiary)
            Text(text).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A slot in the compact bar's favorites strip: a launchable app, or the "…" overflow that expands the window.
enum CompactFavoriteSlot {
    case app(AppEntry)
    case more

    // Stable identity so a slot keeps its icon tied to its app, not its position, when favorites reorder.
    var id: String {
        switch self {
        case .app(let app): return app.id
        case .more: return "__spotter.more__"
        }
    }
}

/// The compact bar's favorites strip — up to 5 icon buttons, ⌘1–⌘5 mirrored in each tooltip.
private struct CompactFavoritesRow: View {
    let slots: [CompactFavoriteSlot]
    let onLaunch: (AppEntry) -> Void
    let onOverflow: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                switch slot {
                case .app(let app):
                    CompactFavoriteButton(help: "\(app.name)  ⌘\(index + 1)") {
                        onLaunch(app)
                    } content: {
                        AppIconView(app: app)
                            .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
                    }
                case .more:
                    CompactFavoriteButton(help: "Show all  ⌘\(index + 1)", action: onOverflow) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Theme.Colors.controlSurface)
                                    .padding(Theme.Spacing.xxs)
                            )
                    }
                }
            }
        }
    }
}

/// A single compact favorite icon: bare icon, native tooltip, click action — no hover chrome, kept tight so the strip reads as one cluster.
private struct CompactFavoriteButton<Content: View>: View {
    let help: String
    let action: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        Button(action: action) {
            content
                .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
