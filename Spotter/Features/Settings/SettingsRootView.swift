import SwiftUI

extension Notification.Name {
    /// Switch an already-open Settings window to a system pane or plugin pane.
    static let spotterSelectSettingsDestination = Notification.Name(
        "SpotterSelectSettingsDestination")
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, permissions, shortcuts, backup, diagnostics, about
    var id: String { rawValue }

    /// The System group: what Spotter itself is configured with.
    static let systemTabs: [SettingsTab] = [.general, .permissions, .shortcuts, .backup]
    /// Diagnostics and About are about the app rather than its behaviour, so they close the sidebar
    /// in their own group below the plugins.
    static let spotterTabs: [SettingsTab] = [.diagnostics, .about]

    var title: String {
        switch self {
        case .general: return "General"
        case .permissions: return "Permissions"
        case .shortcuts: return "Shortcuts"
        case .backup: return "Backup"
        case .diagnostics: return "Diagnostics"
        case .about: return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "switch.2"
        case .permissions: return "lock.shield"
        case .shortcuts: return "keyboard"
        case .backup: return "arrow.up.arrow.down.circle"
        case .diagnostics: return "stethoscope"
        case .about: return "info.circle"
        }
    }

    var tint: Color {
        switch self {
        case .general: return .gray
        case .permissions: return .blue
        case .shortcuts: return .indigo
        case .backup: return .teal
        case .diagnostics: return .orange
        case .about: return .pink
        }
    }
}

enum SettingsDestination: Hashable {
    case system(SettingsTab)
    case plugin(PluginID)
}

struct SettingsRootView: View {
    @EnvironmentObject private var plugins: PluginRegistry
    @State private var destination: SettingsDestination
    @State private var searchQuery = ""
    @FocusState private var searchFocused: Bool

    init(initialDestination: SettingsDestination = .system(.general)) {
        _destination = State(initialValue: initialDestination)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Group {
                switch destination {
                case .system(.general): GeneralSettingsView()
                case .system(.permissions): PermissionsSettingsView()
                case .system(.shortcuts): ShortcutsSettingsView()
                case .system(.backup): BackupSettingsView()
                case .system(.diagnostics): DiagnosticsSettingsView()
                case .system(.about): AboutView()
                case .plugin(let id): plugins.settingsView(for: id)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                VisualEffectView(material: .contentBackground, blending: .behindWindow)
                    .ignoresSafeArea()
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(
            NotificationCenter.default.publisher(for: .spotterSelectSettingsDestination)
        ) { note in
            if let target = note.object as? SettingsDestination {
                searchQuery = ""
                destination = target
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.xs) {
                TextField("Search Settings", text: $searchQuery, prompt: Text("Search Settings"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Search Settings")
                    .focused($searchFocused)
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                        searchFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear settings search")
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs / 2) {
                    if !hasSearchResults {
                        Text("No settings found")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(Theme.Spacing.md)
                    }
                    if SettingsTab.systemTabs.contains(where: matches)
                        || plugins.systemFeatures.contains(where: matches)
                    {
                        sidebarHeader("System")
                        ForEach(SettingsTab.systemTabs.filter(matches)) { item in
                            sidebarRow(
                                title: item.title, systemImage: item.systemImage, tint: item.tint,
                                destination: .system(item))
                        }
                        ForEach(plugins.systemFeatures.filter(matches)) { feature in
                            sidebarRow(
                                title: feature.name, systemImage: feature.systemImage,
                                tint: feature.tint.color, destination: .plugin(feature.id))
                        }
                    }
                    if sortedPlugins.contains(where: matches) {
                        sidebarHeader("Plugins")
                            .padding(.top, Theme.Spacing.md)
                        ForEach(sortedPlugins.filter(matches)) { plugin in
                            sidebarRow(
                                title: plugin.name, systemImage: plugin.systemImage,
                                tint: plugin.tint.color, destination: .plugin(plugin.id))
                        }
                    }
                    if SettingsTab.spotterTabs.contains(where: matches) {
                        sidebarHeader("Spotter")
                            .padding(.top, Theme.Spacing.md)
                        ForEach(SettingsTab.spotterTabs.filter(matches)) { item in
                            sidebarRow(
                                title: item.title, systemImage: item.systemImage, tint: item.tint,
                                destination: .system(item))
                        }
                    }
                }
            }
            .overlayScroller()
        }
        .padding(.top, Theme.Spacing.md)
        .padding(.horizontal, Theme.Spacing.md)
        .frame(width: Theme.Size.settingsSidebar)
        .frame(maxHeight: .infinity)
        .background(
            ZStack(alignment: .trailing) {
                VisualEffectView(material: .sidebar, blending: .behindWindow)
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 1)
            }
            .ignoresSafeArea()
        )
    }

    private func matches(_ tab: SettingsTab) -> Bool {
        SettingsSearch.matches(searchQuery, title: tab.title, key: tab.rawValue)
    }

    private func matches(_ plugin: PluginMetadata) -> Bool {
        SettingsSearch.matches(searchQuery, title: plugin.name, summary: plugin.summary, key: plugin.id.rawValue)
    }

    private var hasSearchResults: Bool {
        SettingsTab.allCases.contains(where: matches)
            || (plugins.systemFeatures + sortedPlugins).contains(where: matches)
    }

    private var sortedPlugins: [PluginMetadata] {
        plugins.plugins.sorted { lhs, rhs in
            let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            return order == .orderedSame
                ? lhs.id.rawValue < rhs.id.rawValue
                : order == .orderedAscending
        }
    }

    private func sidebarHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.xs)
    }

    private func sidebarRow(
        title: String, systemImage: String, tint: Color, destination target: SettingsDestination
    ) -> some View {
        SidebarRow(
            title: title,
            systemImage: systemImage,
            tint: tint,
            isSelected: destination == target
        ) {
            destination = target
            searchQuery = ""
            searchFocused = false
        }
    }
}

private extension PluginTint {
    var color: Color {
        switch self {
        case .blue: return .blue
        case .cyan: return .cyan
        case .green: return .green
        case .orange: return .orange
        case .purple: return .purple
        case .red: return .red
        case .teal: return .teal
        case .yellow: return .yellow
        }
    }
}

private struct SidebarRow: View {
    let title: String
    let systemImage: String
    let tint: Color
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.lg) {
                RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
                    .fill(tint.gradient)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Image(systemName: systemImage)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                    )
                    .shadow(color: .black.opacity(0.2), radius: 0.5, y: 0.5)
                Text(title)
                    .font(Theme.Typography.rowTitle)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(background)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
    }

    private var background: Color {
        if isSelected { return Theme.Colors.selection }
        if hovering { return Theme.Colors.rowHover }
        return .clear
    }
}
