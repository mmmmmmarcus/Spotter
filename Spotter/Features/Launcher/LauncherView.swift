import SwiftUI

struct LauncherList: View {
    let results: [AppEntry]
    let selectedID: AppEntry.ID?
    let favoriteCount: Int
    let showSections: Bool
    /// Changes only when the list should scroll (keyboard nav / reset), so mouse selection never yanks the scroll position.
    let scroll: ScrollIntent
    /// Long-running work sits below the dashboard and above every selectable launcher result.
    var backgroundTasks: [BackgroundTaskItem] = []
    /// Inline calculator/plugin answer; follows any background-task rows.
    var inline: PaletteInlineResult?
    /// Non-selectable plugin dashboard shown only for an empty launcher query.
    var dashboard: AnyView?
    /// Explicit destinations appended after the normal results of every typed query.
    var fallbacks: [LauncherFallback] = []
    var selectedTaskID: BackgroundTaskItem.ID?
    var inlineSelected = false
    var selectedFallbackID: LauncherFallback.ID?
    var onActivateTask: (BackgroundTaskItem) -> Void = { _ in }
    var onActivateInline: () -> Void = {}
    var onInlineActions: () -> Void = {}
    var onActivateFallback: (LauncherFallback) -> Void = { _ in }
    let onActivate: (AppEntry) -> Void
    let onActions: (AppEntry) -> Void
    @EnvironmentObject private var runningApps: RunningAppsMonitor

    private nonisolated static let inlineRowID = "inline-card"

    private nonisolated static func taskRowID(_ id: BackgroundTaskItem.ID) -> String {
        "background-task:" + id.uuidString
    }

    private nonisolated static func fallbackRowID(_ id: LauncherFallback.ID) -> String {
        "launcher-fallback:" + id
    }

    private enum Row: Identifiable {
        case header(String)
        case inline(PaletteInlineResult)
        case app(AppEntry)
        case fallback(LauncherFallback)
        var id: String {
            switch self {
            case .header(let title): return "header-" + title
            case .inline: return LauncherList.inlineRowID
            case .app(let app): return app.id
            case .fallback(let fallback): return LauncherList.fallbackRowID(fallback.id)
            }
        }
    }

    /// Scroll target for the current selection.
    private var selectedRowID: String? {
        if let selectedTaskID { return Self.taskRowID(selectedTaskID) }
        if inlineSelected { return Self.inlineRowID }
        if let selectedFallbackID { return Self.fallbackRowID(selectedFallbackID) }
        return selectedID
    }

    /// Whether the selection sits on the first selectable row, including a pinned task when present.
    private var firstRowSelected: Bool {
        if let first = backgroundTasks.first { return selectedTaskID == first.id }
        if inline != nil { return inlineSelected }
        if let first = results.first { return selectedID == first.id }
        if let first = fallbacks.first { return selectedFallbackID == first.id }
        return false
    }

    private var rows: [Row] {
        var inlineRows: [Row] = []
        if let inline { inlineRows = [.header(inline.sectionTitle), .inline(inline)] }
        guard showSections else {
            var rows = inlineRows
            if !results.isEmpty {
                rows.append(.header("Results"))
                rows.append(contentsOf: results.map(Row.app))
            }
            if !fallbacks.isEmpty {
                rows.append(.header("Try With"))
                rows.append(contentsOf: fallbacks.map(Row.fallback))
            }
            return rows
        }
        var rows: [Row] = inlineRows
        let favorites = results.prefix(favoriteCount)
        let rest = results.dropFirst(favoriteCount)
        // `rest` is apps-then-panes-then-commands by the AppIndex sort invariant, so filtering by kind keeps row order identical and the flat selection index valid.
        let apps = rest.filter { $0.kind == .application }
        let panes = rest.filter { $0.kind == .systemSettings }
        let commands = rest.filter { $0.kind == .command }
        for (title, group) in [
            ("Favorites", Array(favorites)), ("Applications", apps),
            ("System Settings", panes), ("Commands", commands),
        ]
        where !group.isEmpty {
            rows.append(.header(title))
            rows.append(contentsOf: group.map(Row.app))
        }
        return rows
    }

    var body: some View {
        let rows = rows
        return Group {
            if results.isEmpty && backgroundTasks.isEmpty && inline == nil && dashboard == nil
                && fallbacks.isEmpty
            {
                EmptyResults(text: "No apps found")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            if let dashboard {
                                dashboard
                                    .padding(.bottom, Theme.Spacing.md)
                            }
                            if !backgroundTasks.isEmpty {
                                SectionHeader(title: "Background Tasks", isFirst: true)
                                ForEach(backgroundTasks) { task in
                                    BackgroundTaskRow(
                                        task: task, selected: task.id == selectedTaskID)
                                    .id(Self.taskRowID(task.id))
                                    .contentShape(Rectangle())
                                    .onTapGesture { onActivateTask(task) }
                                }
                            }
                            ForEach(rows) { row in
                                switch row {
                                case .header(let title):
                                    SectionHeader(
                                        title: title,
                                        isFirst: backgroundTasks.isEmpty && row.id == rows.first?.id)
                                case .inline(let inline):
                                    CalculatorCard(
                                        result: inline.result, selected: inlineSelected,
                                        companion: inline.companion)
                                        .contentShape(Rectangle())
                                        .onTapGesture(perform: onActivateInline)
                                        .onRightClick(perform: onInlineActions)
                                        .padding(.bottom, Theme.Spacing.xs)
                                case .app(let app):
                                    AppRow(
                                        app: app,
                                        selected: app.id == selectedID,
                                        running: runningApps.isRunning(app)
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture { onActivate(app) }
                                    .onRightClick { onActions(app) }
                                case .fallback(let fallback):
                                    LauncherFallbackRow(
                                        fallback: fallback,
                                        selected: fallback.id == selectedFallbackID)
                                    .contentShape(Rectangle())
                                    .onTapGesture { onActivateFallback(fallback) }
                                }
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.top, Theme.Spacing.xs)
                        .padding(.bottom, Theme.Spacing.md)
                        .hideNativeScrollers()
                        .scrollOriginAnchor()
                    }
                    .edgeDissolve()
                    .thinScrollbar()
                    .onChange(of: scroll) { _, scroll in
                        switch scroll.kind {
                        case .top:
                            proxy.scrollToOrigin()
                        case .follow:
                            // On the first row, snap to the origin so its section header shows too — a nil anchor won't, since the row is already visible.
                            if firstRowSelected {
                                proxy.scrollToOrigin()
                            } else if let selectedRowID {
                                proxy.reveal(selectedRowID)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct LauncherFallbackRow: View {
    let fallback: LauncherFallback
    let selected: Bool
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Image(systemName: fallback.action.systemImage)
                .font(.body)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
            Text(fallback.action.title)
                .font(Theme.Typography.rowTitle)
                .lineLimit(1)
            Spacer()
            Text(fallback.action.contextLabel)
                .font(Theme.Typography.rowTrailing)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(fill)
        )
        .armedHover($hovered)
    }
}

private struct BackgroundTaskRow: View {
    let task: BackgroundTaskItem
    let selected: Bool
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Image(systemName: task.state == .running ? task.systemImage : task.state.systemImage)
                .font(.body)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(task.title)
                    .font(Theme.Typography.rowTitle)
                    .lineLimit(1)
                Text(task.detail)
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            if task.state == .running {
                if let progress = task.progress {
                    VStack(alignment: .trailing, spacing: Theme.Spacing.xxs) {
                        Text("\(Int((progress * 100).rounded()))%")
                            .font(Theme.Typography.rowTrailing)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        ProgressView(value: progress)
                            .frame(width: Theme.Size.backgroundTaskProgressWidth)
                    }
                } else {
                    ProgressView()
                        .controlSize(.small)
                    Text(task.state.label)
                        .font(Theme.Typography.rowTrailing)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            } else {
                Text(task.state.label)
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(fill)
        )
        .armedHover($hovered)
    }
}

/// Section label above a group of rows, shared by every palette list so they use one identical header + row layout.
struct SectionHeader: View {
    let title: String
    /// The list's first header hugs the top; every later header gets `sectionSpacing` above it, which reads as bottom padding on the section that just ended.
    var isFirst = false
    var body: some View {
        Text(title)
            .font(Theme.Typography.sectionHeader)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, isFirst ? Theme.Spacing.xs : Theme.Spacing.sectionSpacing)
            .padding(.bottom, Theme.Spacing.sectionHeaderBottom)
    }
}

private struct AppRow: View {
    let app: AppEntry
    let selected: Bool
    let running: Bool
    /// Observed so a hotkey set/cleared in Settings re-renders the row's keycaps immediately.
    @EnvironmentObject private var hotKeys: HotKeyManager
    /// Observed for the same reason: the Hyper Key display settings (✦ collapse, Include Shift) change how `keycaps` renders.
    @ObservedObject private var settings = AppCore.shared.settings
    /// And again: an alias set from ⌘K or Settings must re-render this row's chip at once.
    @EnvironmentObject private var aliases: AliasStore
    @State private var hovered = false

    /// Selection wins over hover when a row is both; otherwise hover shows its fainter layer.
    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    /// Keycaps for this entry's hotkey, or `nil` if none is bound. Both binding kinds render through the same path, so a double-tap shows as its doubled glyph.
    private var shortcutCaps: [String]? {
        guard let action = app.hotKeyAction,
            let binding = hotKeys.binding(for: action)
        else { return nil }
        return binding.keycaps
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            AppIconView(app: app)
                .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
                .overlay(alignment: .bottom) {
                    if running {
                        Circle()
                            .fill(.secondary)
                            .frame(width: 3, height: 3)
                            .offset(y: 3)
                    }
                }
            Text(app.name)
                .font(Theme.Typography.rowTitle)
                .lineLimit(1)
            if let alias = aliases.alias(for: app) {
                Text(alias)
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xxs)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.keyCap, style: .continuous)
                            .fill(Theme.Colors.controlSurface))
            }
            if let caps = shortcutCaps {
                HStack(spacing: Theme.Spacing.xxs) {
                    ForEach(Array(caps.enumerated()), id: \.offset) { _, cap in
                        KeyCapChip(text: cap, style: .outline)
                    }
                }
            }
            Spacer()
            Text(app.kindLabel)
                .font(Theme.Typography.rowTrailing)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(fill)
        )
        .armedHover($hovered)
    }
}

/// Row icon that decodes off the main thread (mirrors `ImageThumbnail`), so surfacing new apps while typing never rasterizes on-main during render. Warm icons seed synchronously so there's no placeholder flash on re-open.
struct AppIconView: View {
    let app: AppEntry
    /// A symbol tile is a rasterized bitmap, so unlike a live `Image(systemName:)` it can't follow
    /// the appearance on its own — the scheme joins the task id so a system flip redraws it.
    @Environment(\.colorScheme) private var scheme
    @State private var image: NSImage?

    init(app: AppEntry) {
        self.app = app
        _image = State(
            initialValue: app.isSymbolIcon
                ? IconCache.cachedSymbol(
                    named: app.symbolIconName, dark: NSApp.effectiveAppearance.isDark)
                : IconCache.cached(forFile: app.iconPath))
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable()
            } else {
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(Theme.Colors.surfaceGlow)
            }
        }
        .task(id: Reload(id: app.id, dark: scheme == .dark)) {
            // An app icon is appearance-independent, so only a symbol tile re-decodes on a flip.
            guard image == nil || app.isSymbolIcon else { return }
            image =
                app.isSymbolIcon
                ? await IconCache.loadSymbolAsync(
                    named: app.symbolIconName, dark: scheme == .dark)
                : await IconCache.loadAsync(forFile: app.iconPath)
        }
    }

    private struct Reload: Equatable {
        let id: String
        let dark: Bool
    }
}

/// Actions menu content for a launcher app, shown bottom-right on right-click or from the Actions pill.
@MainActor
enum AppActionsMenu {
    static func content(
        app: AppEntry, searchQuery: String, core: AppCore, favorites: FavoritesStore,
        running: Bool, alias: String?, onSetAlias: @escaping () -> Void,
        onResetRanking: @escaping () -> Void
    ) -> PopoverMenuContent {
        var items: [PopoverMenuItem] = [
            PopoverMenuItem(
                title: openTitle(app), systemImage: "list.bullet.rectangle", shortcut: "↵"
            ) { core.launch(app, searchQuery: searchQuery) }
        ]
        if favorites.isFavorite(app) {
            items.append(
                PopoverMenuItem(title: "Remove from Favorites", systemImage: "star.slash") {
                    favorites.toggle(app)
                })
        } else {
            items.append(
                PopoverMenuItem(title: "Add to Favorites", systemImage: "star") {
                    favorites.toggle(app)
                })
        }
        // Every kind can carry one, including commands: the alias is the user's own name for the row.
        items.append(
            PopoverMenuItem(
                title: alias == nil ? "Set Alias" : "Change Alias", systemImage: "tag"
            ) {
                onSetAlias()
            })
        if core.launcherRanking.hasRanking(for: app.preferenceKey) {
            items.append(
                PopoverMenuItem(title: "Reset Ranking", systemImage: "arrow.counterclockwise") {
                    onResetRanking()
                })
        }
        if app.canRevealInFinder {
            items.append(
                PopoverMenuItem(
                    title: "Show in Finder", systemImage: "folder", shortcut: "⌘↵"
                ) {
                    core.showInFinder(app)
                })
        }
        if running, app.kind == .application {
            items.append(
                PopoverMenuItem(
                    title: "Quit Application", systemImage: "power", shortcut: "⌃⇧Q",
                    isDestructive: true
                ) {
                    core.quit(app)
                })
        }
        if core.canUninstallWithMole(app) {
            items.append(
                PopoverMenuItem(
                    title: "Uninstall with Mole", systemImage: "trash", isDestructive: true
                ) {
                    core.uninstallWithMole(app)
                })
        }
        return PopoverMenuContent(header: app.name, items: items)
    }

    private static func openTitle(_ app: AppEntry) -> String {
        switch app.kind {
        case .application: return "Open Application"
        case .systemSettings: return "Open System Setting"
        case .command: return "Run Command"
        }
    }
}
