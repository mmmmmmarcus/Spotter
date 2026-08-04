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

    private var hyperStatusDot: Color? {
        switch hyperTap.status {
        case .off: return nil
        case .active: return .green
        case .needsAccessibility: return .orange
        }
    }

    private var hyperSubtitle: String {
        guard settings.hyperKey != .none else {
            return
                "Select a physical key to remap to the \(hyperGlyphs) modifier keys simultaneously."
        }
        var text =
            "Pressing \(settings.hyperKey.title) will trigger the left \(hyperGlyphs) modifier keys."
        if settings.hyperKeyReplacesGlyph {
            text += " Hyper Key shortcuts will be shown in Spotter with ✦."
        }
        if hyperTap.status == .needsAccessibility {
            text += " Spotter needs Accessibility access to remap keys."
        }
        return text
    }

    var body: some View {
        SettingsPane(
            title: "General",
            subtitle: "Global shortcuts and startup behaviour."
        ) {
            SettingsCard(header: "Global Shortcuts") {
                SettingsRow(
                    title: "App Launcher",
                    subtitle: "Summon the fuzzy app launcher.",
                    systemImage: "magnifyingglass",
                    tint: .blue
                ) {
                    ShortcutRecorder(action: .togglePalette)
                }
            }

            SettingsCard(header: "Search") {
                SettingsRow(
                    title: "Learned ranking",
                    subtitle:
                        "Spotter privately learns which results you choose for each query. Reset all learned choices to restore the default order.",
                    systemImage: "chart.line.uptrend.xyaxis",
                    tint: .blue
                ) {
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
                    title: "Hyper Key",
                    subtitle: hyperSubtitle,
                    systemImage: "sparkle",
                    tint: .purple,
                    statusDot: hyperStatusDot
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
                    SettingsRow(
                        title: "Quick Press",
                        subtitle:
                            "Select an action to perform when \(settings.hyperKey.title) is pressed without any other keys.",
                        systemImage: "hand.tap",
                        tint: .teal
                    ) {
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
                SettingsRow(
                    title: "Include Shift (⇧)",
                    subtitle: "Hyper Key will remap to the \(hyperGlyphs) modifier keys.",
                    systemImage: "shift",
                    tint: .indigo
                ) {
                    Toggle("", isOn: $settings.hyperKeyIncludesShift)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                SettingsDivider()
                SettingsRow(
                    title: "Replace occurrences of \(hyperGlyphs) with ✦",
                    subtitle: "Shortcuts containing the Hyper Key modifiers are shown with ✦.",
                    systemImage: "keyboard",
                    tint: .gray
                ) {
                    Toggle("", isOn: $settings.hyperKeyReplacesGlyph)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }

            SettingsCard(header: "Appearance") {
                SettingsRow(
                    title: "Compact mode",
                    subtitle:
                        "Open the launcher as a slim search bar that expands into the full list as you type.",
                    systemImage: "macwindow",
                    tint: .blue
                ) {
                    Toggle("", isOn: $settings.compactMode)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                SettingsDivider()
                SettingsRow(
                    title: "Show favorites in compact mode",
                    subtitle:
                        "Pin favorite app icons to the right of the compact bar (⌘1–⌘5 to launch).",
                    systemImage: "star",
                    tint: .yellow
                ) {
                    Toggle("", isOn: $settings.showFavoritesInCompactMode)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .disabled(!settings.compactMode)
                }
                .opacity(settings.compactMode ? 1 : 0.5)
                SettingsDivider()
                SettingsRow(
                    title: "Follow the cursor across displays",
                    subtitle:
                        "Open the launcher on whichever display the pointer is on, rather than the one with the menu bar.",
                    systemImage: "display.2",
                    tint: .teal
                ) {
                    Toggle("", isOn: $settings.openOnCursorScreen)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }

            SettingsCard(header: "General") {
                SettingsRow(
                    title: "Launch at login",
                    subtitle: "Start Spotter automatically when you log in.",
                    systemImage: "power",
                    tint: .green
                ) {
                    Toggle("", isOn: $settings.launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                SettingsDivider()
                SettingsRow(
                    title: "Show in menu bar",
                    subtitle:
                        "Keep the Spotter icon in the menu bar. Shortcuts still work when hidden.",
                    systemImage: "menubar.arrow.up.rectangle",
                    tint: .gray
                ) {
                    Toggle("", isOn: $showInMenuBar)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                SettingsDivider()
                SettingsRow(
                    title: "Remember Window Position",
                    subtitle:
                        "Drag the launcher by its background to move it. On, it reopens where you left it; off, it re-centers every time.",
                    systemImage: "macwindow.on.rectangle",
                    tint: .indigo
                ) {
                    Toggle("", isOn: $settings.remembersPalettePosition)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                SettingsDivider()
                SettingsRow(
                    title: "Lock Input Method to English",
                    subtitle:
                        "Switch the keyboard to an ASCII layout when the launcher opens. You can still switch to another input method while it's open.",
                    systemImage: "keyboard",
                    tint: .indigo
                ) {
                    Toggle("", isOn: $settings.lockInputToEnglish)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                SettingsDivider()
                SettingsRow(
                    title: "Pop to Root Search",
                    subtitle: "Reset to the launcher this long after the window closes.",
                    systemImage: "arrow.uturn.backward",
                    tint: .indigo
                ) {
                    Picker("", selection: $settings.popToRootTimeout) {
                        ForEach(PopToRootTimeout.allCases) { timeout in
                            Text(timeout.title).tag(timeout)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsDivider()
                SettingsRow(
                    title: "Welcome Guide",
                    subtitle:
                        "Re-run the first-launch setup: shortcut, permissions, and Raycast import.",
                    systemImage: "sparkles",
                    tint: .yellow
                ) {
                    Button("Show…") { AppCore.shared.showOnboarding() }
                        .controlSize(.small)
                }
            }

            OpenRouterSettingsCard()

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

/// OpenRouter credential card. The key is the gate: present means Selection Tools' AI path is
/// active, absent means fully on-device. Key and models sync through settings backups.
private struct OpenRouterSettingsCard: View {
    @ObservedObject private var store = AppCore.shared.openRouter
    @State private var keyDraft = AppCore.shared.openRouter.apiKey

    var body: some View {
        SettingsCard(header: "AI (OpenRouter)") {
            SettingsRow(
                title: "API Key",
                subtitle: keySubtitle,
                systemImage: "key",
                tint: .purple,
                statusDot: store.isReady ? .green : nil
            ) {
                HStack(spacing: Theme.Spacing.md) {
                    SecureField("sk-or-…", text: $keyDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                        .onSubmit { store.setAPIKey(keyDraft) }
                        .onChange(of: keyDraft) { store.setAPIKey(keyDraft) }
                    Button("Validate") {
                        Task { await store.validate() }
                    }
                    .controlSize(.small)
                    .disabled(keyDraft.isEmpty || store.validation == .checking)
                }
            }
        }
        // The key can change underneath this pane (settings sync applying a remote file).
        .onChange(of: store.apiKey) { if store.apiKey != keyDraft { keyDraft = store.apiKey } }
    }

    private var keySubtitle: String {
        switch store.validation {
        case .unknown:
            "Required for Selection Tools' AI translate and grammar. "
                + "Included in settings backups and sync."
        case .checking: "Checking key with \(OpenRouterStore.provider)…"
        case .valid(let detail): detail
        case .invalid(let message): message
        }
    }
}

/// In-app updater: manual check plus a consent-gated daily check (`CurrencyRateStore` shape).
private struct UpdatesSettingsCard: View {
    @ObservedObject private var store = AppCore.shared.updates
    @State private var askingConsent = false

    var body: some View {
        SettingsCard(header: "Updates") {
            SettingsRow(
                title: "Spotter \(store.currentVersion.map(String.init(describing:)) ?? "—")",
                subtitle: statusText,
                systemImage: "arrow.down.circle",
                tint: .blue
            ) {
                trailingControl
            }
            SettingsDivider()
            SettingsRow(
                title: "Check Automatically",
                subtitle: "Ask \(UpdateStore.provider) once a day whether a newer release exists. Only the request is sent.",
                systemImage: "clock.arrow.circlepath",
                tint: .blue
            ) {
                Toggle("", isOn: autoCheckBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
        }
        .sheet(isPresented: $askingConsent) {
            UpdateConsentSheet(
                onCancel: { askingConsent = false },
                onAccept: {
                    askingConsent = false
                    store.setAutoCheck(true)
                })
        }
    }

    @ViewBuilder
    private var trailingControl: some View {
        switch store.status {
        case .checking, .installing:
            ProgressView().controlSize(.small)
        case .available(let release):
            if release.zipAssetURL != nil {
                Button("Update to \(release.version.description)…") {
                    Task { await store.installAvailableUpdate() }
                }
                .controlSize(.small)
            } else {
                // Older releases ship only a DMG; hand off to the release page instead of failing.
                Button("View \(release.version.description)…") {
                    NSWorkspace.shared.open(release.pageURL)
                }
                .controlSize(.small)
            }
        case .idle, .upToDate, .failed:
            Button("Check for Updates") {
                Task { await store.checkNow() }
            }
            .controlSize(.small)
        }
    }

    private var statusText: String {
        switch store.status {
        case .idle: "Installed from GitHub Releases; updates keep your settings and permissions."
        case .checking: "Checking \(UpdateStore.provider)…"
        case .upToDate: "You're on the latest version."
        case .available(let release): "Version \(release.version.description) is available."
        case .installing: "Downloading and installing — Spotter will relaunch."
        case .failed(let message): message
        }
    }

    private var autoCheckBinding: Binding<Bool> {
        Binding(
            get: { store.autoCheckEnabled },
            set: { enabled in
                if enabled {
                    askingConsent = true
                } else {
                    store.setAutoCheck(false)
                }
            })
    }
}

private struct UpdateConsentSheet: View {
    let onCancel: () -> Void
    let onAccept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            HStack(spacing: Theme.Spacing.lg) {
                Image(systemName: "network")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.blue)
                Text("Check for updates automatically?")
                    .font(.headline)
            }

            Text(
                "Spotter asks \(UpdateStore.provider) once a day whether a newer release exists. "
                    + "The request carries no account, identifier, or content — only the check "
                    + "itself. Updates never install without your click."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Theme.Spacing.lg) {
                Link(destination: UpdateStore.providerURL) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text("Releases")
                        Image(systemName: "arrow.up.right.square")
                    }
                    .font(.callout)
                }
                Spacer()
                Button("Not Now", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Enable", action: onAccept)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: 420)
    }
}
