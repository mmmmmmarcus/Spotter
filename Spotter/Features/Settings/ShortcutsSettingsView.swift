import SwiftUI

/// Settings → Shortcuts: the single home for every shortcut Spotter can bind, as **one table**. The
/// two app-level summon shortcuts are its first section, then everything the launcher can open —
/// Applications, System Settings, then Commands split by whoever publishes them. One search field
/// sits above the table and filters all of it, summon shortcuts included. Each launcher row carries
/// an alias field, a hotkey recorder and a visibility checkbox. The table never applies the
/// visibility filter itself, so a hidden row stays re-checkable here.
struct ShortcutsSettingsView: View {
    @EnvironmentObject private var appIndex: AppIndex
    @EnvironmentObject private var plugins: PluginRegistry
    @State private var query = ""
    @State private var collapsed: Set<String>

    /// Which headings are folded shut. Device-local window state, like a scroll position — it is
    /// deliberately not in the settings backup, since a synced Mac inheriting someone else's folded
    /// list would be restoring a view, not a setting.
    private static let collapsedKey = "shortcuts.collapsedGroups"
    /// Fold state is keyed by heading title, and the summon section's is its own heading.
    private static let globalSectionID = "Global Shortcuts"

    init() {
        _collapsed = State(
            initialValue: Set(UserDefaults.standard.stringArray(forKey: Self.collapsedKey) ?? []))
    }

    var body: some View {
        // The one pane that is not a `SettingsPane`: its table is every app on the Mac, which needs
        // a lazy container, and a grouped `Form` is not lazy. A `List` is — and it takes sections,
        // so the summon shortcuts can be the table's first section instead of a second surface
        // above it.
        VStack(alignment: .leading, spacing: 0) {
            SettingsHeader(title: "Shortcuts")
                .padding(.horizontal, Theme.Spacing.xxl)
                .padding(.top, Theme.Spacing.xxl)

            // Above the table rather than inside it: one search covers the whole table, so it has to
            // stay put while the table scrolls under it.
            searchField
                .padding(.horizontal, Theme.Spacing.xxl)
                .padding(.top, Theme.Spacing.xxl)
                .padding(.bottom, Theme.Spacing.lg)

            table
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea(edges: .top)
    }

    /// The summon shortcuts, matched with the same scorer the launcher rows use so one query means
    /// one thing across the whole table.
    private var globalShortcuts: [GlobalShortcut] {
        let all = [
            GlobalShortcut(title: "App Launcher", action: .togglePalette),
            GlobalShortcut(title: "Backup Shortcut", action: .togglePaletteBackup),
        ]
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return all }
        return all.filter { FuzzyMatch.score(query: trimmed, candidate: $0.title) != nil }
    }

    /// Applications and System Settings are one group each; Commands is grouped by owner, so a
    /// plugin's commands sit together under the plugin's own name.
    private var sections: [ShortcutSection] {
        // Run the matcher once per render; `AppIndex` already sorts, so every group stays in order.
        let matched = query.isEmpty ? appIndex.apps : appIndex.matches(query)
        var commandGroups: [ShortcutGroupKey: [AppEntry]] = [:]
        var applications: [AppEntry] = []
        var panes: [AppEntry] = []
        for entry in matched {
            switch entry.kind {
            case .application: applications.append(entry)
            case .systemSettings: panes.append(entry)
            case .command: commandGroups[commandGroup(entry), default: []].append(entry)
            }
        }
        return [
            ShortcutSection(
                title: "Applications",
                groups: applications.isEmpty ? [] : [ShortcutGroup(title: nil, entries: applications)]),
            ShortcutSection(
                title: "System Settings",
                groups: panes.isEmpty ? [] : [ShortcutGroup(title: nil, entries: panes)]),
            ShortcutSection(
                title: "Commands",
                groups: commandGroups.keys.sorted().map { key in
                    ShortcutGroup(title: key.title, entries: commandGroups[key] ?? [])
                }),
        ]
        .filter { !$0.groups.isEmpty }
    }

    /// Where a command row belongs. Ownership comes from the registry rather than from a second
    /// hand-kept table of id prefixes, so a new plugin's commands group themselves.
    private func commandGroup(_ entry: AppEntry) -> ShortcutGroupKey {
        // Spotter's own built-ins (`CommandRegistry`) belong to no plugin, and lead the list.
        guard let owner = plugins.commandOwner(ofCommandID: entry.id) else {
            return ShortcutGroupKey(rank: 0, subrank: 0, title: "Spotter")
        }
        let rank = plugins.catalogIndex(of: owner) + 1
        guard owner == .commands else {
            return ShortcutGroupKey(
                rank: rank, subrank: 0, title: plugins.metadata(for: owner)?.name ?? "Commands")
        }
        // The Commands plugin publishes two unrelated things: the fixed macOS actions, and whatever
        // shell commands the user wrote. One heading over both would read as one feature.
        return SystemCommandCatalog.command(forEntryID: entry.id) != nil
            ? ShortcutGroupKey(rank: rank, subrank: 0, title: "System")
            : ShortcutGroupKey(rank: rank, subrank: 1, title: "Custom Commands")
    }

    /// A typed query overrides every fold: a heading that hid its own matches would read as no match
    /// at all.
    private func isCollapsed(_ id: String) -> Bool { query.isEmpty && collapsed.contains(id) }

    private func toggleCollapsed(_ id: String) {
        if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
        UserDefaults.standard.set(Array(collapsed).sorted(), forKey: Self.collapsedKey)
    }

    /// One table for the whole pane. `List` stays lazy — only the visible rows are realized, which
    /// is what lets every application on the Mac sit in the same container as the two summon
    /// shortcuts — and its own background is hidden so the table reads as part of the pane rather
    /// than as a box drawn inside it.
    private var table: some View {
        List {
            if !globalShortcuts.isEmpty {
                let sectionCollapsed = isCollapsed(Self.globalSectionID)
                Section {
                    if !sectionCollapsed {
                        ForEach(globalShortcuts) { shortcut in
                            GlobalShortcutRow(title: shortcut.title, action: shortcut.action)
                                .plainTableRow()
                        }
                    }
                } header: {
                    DisclosureHeader(
                        title: Self.globalSectionID, count: globalShortcuts.count,
                        isCollapsed: sectionCollapsed, font: .headline, indent: 0, topPadding: 0
                    ) {
                        toggleCollapsed(Self.globalSectionID)
                    }
                }
            }

            ForEach(sections) { section in
                let sectionCollapsed = isCollapsed(section.id)
                Section {
                    if !sectionCollapsed {
                        ForEach(section.groups) { group in
                            let groupID = section.id + "/" + group.id
                            let groupCollapsed = group.title != nil && isCollapsed(groupID)
                            if let title = group.title {
                                DisclosureHeader(
                                    title: title, count: group.entries.count,
                                    isCollapsed: groupCollapsed,
                                    font: Theme.Typography.sectionHeader,
                                    indent: Theme.Spacing.lg, topPadding: Theme.Spacing.sm
                                ) {
                                    toggleCollapsed(groupID)
                                }
                                .plainTableRow()
                            }
                            if !groupCollapsed {
                                ForEach(group.entries) { entry in
                                    ShortcutRow(entry: entry)
                                        .plainTableRow()
                                }
                            }
                        }
                    }
                } header: {
                    DisclosureHeader(
                        title: section.title, count: section.entryCount,
                        isCollapsed: sectionCollapsed, font: .headline, indent: 0, topPadding: 0
                    ) {
                        toggleCollapsed(section.id)
                    }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        // Force the thin, auto-hiding overlay scroller so a system-wide "always show scroll bars" setting can't draw a wide legacy one.
        .containerOverlayScroller()
        .overlay {
            if sections.isEmpty && globalShortcuts.isEmpty {
                Text(query.isEmpty ? "Nothing here yet." : "No matches for “\(query)”.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search shortcuts, apps, settings and commands…", text: $query)
                .textFieldStyle(.plain)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.body)
        .padding(Theme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(Theme.Colors.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
        )
    }
}

/// Sorts groups into catalog order: Spotter's own commands, then each plugin in the order the
/// registry lists it, with the title breaking ties only for groups that share an owner.
private struct ShortcutGroupKey: Hashable, Comparable {
    let rank: Int
    let subrank: Int
    let title: String

    static func < (lhs: ShortcutGroupKey, rhs: ShortcutGroupKey) -> Bool {
        if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
        if lhs.subrank != rhs.subrank { return lhs.subrank < rhs.subrank }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
}

/// One foldable heading, at either level: the chevron, the name and how many rows sit under it. The
/// count is what keeps a folded heading informative — otherwise collapsing a section hides both the
/// rows and the fact that there were any.
private struct DisclosureHeader: View {
    let title: String
    let count: Int
    let isCollapsed: Bool
    let font: Font
    let indent: CGFloat
    let topPadding: CGFloat
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                Text(title)
                    .font(font)
                    .foregroundStyle(font == Theme.Typography.sectionHeader ? .secondary : .primary)
                Text("\(count)")
                    .font(Theme.Typography.keyCap.monospacedDigit())
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }
            .padding(.leading, indent)
            .padding(.trailing, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(hovered ? Theme.Colors.rowHover : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, topPadding)
        .padding(.bottom, Theme.Spacing.xxs)
        .onHover { hovered = $0 }
        // The chevron turns; the rows themselves appear and disappear without animation, since a
        // lazy container animating hundreds of application rows in and out stutters.
        .animation(.easeOut(duration: 0.15), value: isCollapsed)
        .accessibilityLabel("\(title), \(count) items")
        .accessibilityHint(isCollapsed ? "Expand" : "Collapse")
    }
}

private struct ShortcutGroup: Identifiable {
    /// Nil for a section that is one group — Applications needs no heading under "Applications".
    let title: String?
    let entries: [AppEntry]
    var id: String { title ?? "" }
}

private struct ShortcutSection: Identifiable {
    let title: String
    let groups: [ShortcutGroup]
    var id: String { title }
    var entryCount: Int { groups.reduce(0) { $0 + $1.entries.count } }
}

/// One of the two app-level summon shortcuts. They are not launcher entries, so they carry a title
/// and an action and nothing else.
private struct GlobalShortcut: Identifiable {
    let title: String
    let action: HotKeyAction
    var id: String { title }
}

extension View {
    /// Strips a `List` row back to the table's own grammar: the row draws its own insets, hover fill
    /// and separators-by-absence, exactly as it did in the hand-rolled list this replaced.
    fileprivate func plainTableRow() -> some View {
        listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
    }
}

/// A summon shortcut's row. It has no icon, alias or visibility box, but reserves the icon and
/// visibility columns so its name and its recorder land at the same x as every launcher row's.
private struct GlobalShortcutRow: View {
    let title: String
    let action: HotKeyAction
    @State private var hovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Color.clear
                .frame(width: Theme.Size.shortcutRowIcon, height: Theme.Size.shortcutRowIcon)
            Text(title).lineLimit(1)
            Spacer(minLength: Theme.Spacing.xl)
            ShortcutRecorder(action: action)
            Color.clear.frame(width: Theme.Size.shortcutVisibilityControl, height: 1)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(hovered ? Theme.Colors.rowHover : .clear)
        )
        .onHover { hovered = $0 }
    }
}

/// The per-row alias field, dressed like `ShortcutRecorder` beside it. One persistent `TextField`
/// rather than a view swapped in on focus — swapping tears down the field editor and breaks repeat
/// focus.
private struct AliasField: View {
    let entry: AppEntry
    @EnvironmentObject private var aliases: AliasStore
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
        TextField(
            "", text: $draft,
            prompt: Text("Add alias").foregroundStyle(Theme.Colors.textSecondary)
        )
        .textFieldStyle(.plain)
        .labelsHidden()
        .font(Theme.Typography.rowTrailing)
        .focused($focused)
        // The system focus ring insets the field editor, hopping the placeholder left.
        .focusEffectDisabled()
        .onSubmit(commit)
        // Focus landing elsewhere is the other commit point, so an edit is never left unsaved.
        .onChange(of: focused) { _, now in
            if !now { commit() }
        }
        .onAppear { draft = aliases.alias(for: entry) ?? "" }
        // A backup import replaces the whole table out from under an unfocused row.
        .onChange(of: aliases.revision) {
            if !focused { draft = aliases.alias(for: entry) ?? "" }
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .frame(width: Theme.Size.shortcutRowControl, height: 24)
        .background(shape.fill(Theme.Colors.cardFill))
        .overlay(
            shape.strokeBorder(
                focused ? Color.accentColor : Theme.Colors.cardStroke, lineWidth: 1)
        )
        .clipShape(shape)
        .accessibilityLabel("Alias for \(entry.name)")
    }

    /// Both commit points trim; the store keeps text as typed, so a blank-when-trimmed draft removes.
    private func commit() {
        aliases.setAlias(draft, for: entry.preferenceKey)
        draft = aliases.alias(for: entry) ?? ""
    }
}

private struct ShortcutRow: View {
    let entry: AppEntry
    @EnvironmentObject private var visibility: VisibilityStore
    // Hover lives on the row itself so a mouse sweep repaints only the rows entering/leaving.
    @State private var hovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Image(nsImage: entry.icon)
                .resizable()
                .frame(width: Theme.Size.shortcutRowIcon, height: Theme.Size.shortcutRowIcon)
            Text(entry.name).lineLimit(1)
            Spacer(minLength: Theme.Spacing.xl)
            AliasField(entry: entry)
            if let action = entry.hotKeyAction {
                ShortcutRecorder(action: action)
            } else {
                // A row with nothing to bind still holds the recorder's column open.
                Color.clear.frame(width: Theme.Size.shortcutRowControl, height: 1)
            }
            Toggle("", isOn: itemBinding)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .frame(width: Theme.Size.shortcutVisibilityControl)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(hovered ? Theme.Colors.rowHover : .clear)
        )
        .onHover { hovered = $0 }
    }

    private var itemBinding: Binding<Bool> {
        Binding(
            get: { visibility.isItemVisible(entry) },
            set: { visibility.setItemVisible($0, for: entry) }
        )
    }
}
