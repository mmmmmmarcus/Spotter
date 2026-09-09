import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject private var settings = AppCore.shared.settings
    @ObservedObject private var hyperTap = AppCore.shared.hyperKeyTap
    @ObservedObject private var launcherRanking = AppCore.shared.launcherRanking
    // Same UserDefaults key the `App` binds its `MenuBarExtra(isInserted:)` to — toggling here updates the menu-bar icon live, with no shared observable between them.
    @AppStorage(SettingsKey.showInMenuBar) private var showInMenuBar = true
    @State private var confirmingRankingReset = false

    /// The Hyper modifier chord as prose glyphs, tracking the Include Shift toggle.
    private var hyperGlyphs: String { settings.hyperKeyIncludesShift ? "⌃⌥⇧⌘" : "⌃⌥⌘" }

    /// Only terminals actually on this Mac, plus the current choice so a synced-but-missing app still shows what is selected. Terminal always qualifies.
    private var installedTerminals: [PreferredTerminal] {
        PreferredTerminal.allCases.filter { terminal in
            terminal == .terminal || terminal == settings.preferredTerminal
                || NSWorkspace.shared.urlForApplication(
                    withBundleIdentifier: terminal.bundleIdentifier) != nil
        }
    }

    private var hyperStatusDot: Color? {
        switch hyperTap.status {
        case .off: return nil
        case .active: return .green
        case .needsAccessibility: return .orange
        }
    }

    /// What the Hyper Key is currently doing, or why it isn't — never what a Hyper Key is.
    private var hyperSubtitle: String? {
        guard settings.hyperKey != .none else { return nil }
        if hyperTap.status == .needsAccessibility {
            return "Spotter needs Accessibility access to remap keys."
        }
        return "\(settings.hyperKey.title) triggers the left \(hyperGlyphs) modifier keys."
    }

    var body: some View {
        SettingsPane(title: "General") {
            SettingsCard(header: "Search") {
                SettingsRow(title: "Learned ranking") {
                    Button("Reset…", role: .destructive) {
                        confirmingRankingReset = true
                    }
                    .controlSize(.small)
                    .disabled(launcherRanking.isEmpty)
                }
            }

            SearchScopesCard()

            SettingsCard(header: "Hyper Key") {
                SettingsRow(
                    title: "Hyper Key", subtitle: hyperSubtitle, statusDot: hyperStatusDot
                ) {
                    if hyperTap.status == .needsAccessibility {
                        Button("Grant Access…") { Permissions.openAccessibilitySettings() }
                            .controlSize(.small)
                    }
                    Picker("", selection: $settings.hyperKey) {
                        ForEach(HyperKeyPhysicalKey.allCases) { key in
                            Text(key.title).tag(key)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .onChange(of: settings.hyperKey) { _, newKey in
                        // A Quick Press choice is meaningless for a different key.
                        settings.hyperKeyQuickPress = .none
                        if newKey != .none { Permissions.ensureAccessibility() }
                    }
                }
                if settings.hyperKey.hasOriginalFunction {
                    SettingsDivider()
                    SettingsRow(title: "Quick Press") {
                        Picker("", selection: $settings.hyperKeyQuickPress) {
                            Text("Does Nothing").tag(HyperKeyQuickPress.none)
                            if let original = settings.hyperKey.quickPressOriginalTitle {
                                Text(original).tag(HyperKeyQuickPress.originalKey)
                            }
                            Text("Trigger Escape").tag(HyperKeyQuickPress.escape)
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                SettingsDivider()
                SettingsRow(title: "Include Shift (⇧)") {
                    Toggle("", isOn: $settings.hyperKeyIncludesShift)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                SettingsDivider()
                SettingsRow(title: "Replace occurrences of \(hyperGlyphs) with ✦") {
                    Toggle("", isOn: $settings.hyperKeyReplacesGlyph)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }

            SettingsCard(header: "Appearance") {
                SettingsRow(title: "Compact mode") {
                    Toggle("", isOn: $settings.compactMode)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                SettingsDivider()
                SettingsRow(title: "Show favorites in compact mode") {
                    Toggle("", isOn: $settings.showFavoritesInCompactMode)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .disabled(!settings.compactMode)
                }
                .opacity(settings.compactMode ? 1 : 0.5)
                SettingsDivider()
                SettingsRow(title: "Follow the cursor across displays") {
                    Toggle("", isOn: $settings.openOnCursorScreen)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }

            SettingsCard(header: "Launcher Sections") {
                ForEach(
                    Array(settings.launcherSectionOrder.enumerated()), id: \.element
                ) { index, section in
                    if index > 0 { SettingsDivider() }
                    SettingsRow(title: section.title) {
                        HStack(spacing: Theme.Spacing.md) {
                            Button {
                                settings.moveLauncherSection(section, delta: -1)
                            } label: {
                                Image(systemName: "chevron.up")
                            }
                            .buttonStyle(.borderless)
                            .disabled(index == 0)
                            .help("Move Up")
                            Button {
                                settings.moveLauncherSection(section, delta: 1)
                            } label: {
                                Image(systemName: "chevron.down")
                            }
                            .buttonStyle(.borderless)
                            .disabled(index == settings.launcherSectionOrder.count - 1)
                            .help("Move Down")
                            Toggle(
                                "",
                                isOn: Binding(
                                    get: { !settings.launcherHiddenSections.contains(section) },
                                    set: { shown in
                                        if shown {
                                            settings.launcherHiddenSections.remove(section)
                                        } else {
                                            settings.launcherHiddenSections.insert(section)
                                        }
                                    })
                            )
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        }
                    }
                }
            }

            SettingsCard(header: "General") {
                SettingsRow(title: "Run in Terminal uses") {
                    Picker("", selection: $settings.preferredTerminal) {
                        ForEach(installedTerminals, id: \.self) { terminal in
                            Text(terminal.displayName).tag(terminal)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsDivider()
                SettingsRow(title: "Launch at login") {
                    Toggle("", isOn: $settings.launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                SettingsDivider()
                SettingsRow(title: "Show in menu bar") {
                    Toggle("", isOn: $showInMenuBar)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                SettingsDivider()
                SettingsRow(title: "Show in Dock") {
                    Toggle("", isOn: $settings.showInDock)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                SettingsDivider()
                SettingsRow(title: "Remember Window Position") {
                    Toggle("", isOn: $settings.remembersPalettePosition)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                SettingsDivider()
                SettingsRow(title: "Lock Input Method to English") {
                    Toggle("", isOn: $settings.lockInputToEnglish)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                SettingsDivider()
                SettingsRow(title: "Pop to Root Search") {
                    Picker("", selection: $settings.popToRootTimeout) {
                        ForEach(PopToRootTimeout.allCases) { timeout in
                            Text(timeout.title).tag(timeout)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsDivider()
                SettingsRow(title: "Welcome Guide") {
                    Button("Show…") { AppCore.shared.showOnboarding() }
                        .controlSize(.small)
                }
            }

            UpdatesSettingsCard()
        }
        .confirmationDialog(
            "Reset learned launcher ranking?",
            isPresented: $confirmingRankingReset,
            titleVisibility: .visible
        ) {
            Button("Reset Ranking", role: .destructive) {
                launcherRanking.resetAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Spotter will relearn your preferred results as you use the launcher.")
        }
    }
}
