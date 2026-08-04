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

/// OpenRouter credential + consent card. The key/model sync through settings backups; the enable
/// flag lives on `OpenRouterStore` and never syncs, so an imported file cannot grant network access.
private struct OpenRouterSettingsCard: View {
    @ObservedObject private var store = AppCore.shared.openRouter
    @State private var keyDraft = AppCore.shared.openRouter.apiKey
    @State private var modelDraft = AppCore.shared.openRouter.model
    @State private var askingConsent = false

    var body: some View {
        SettingsCard(header: "AI (OpenRouter)") {
            SettingsRow(
                title: "AI Translate & Grammar",
                subtitle: aiStatus,
                systemImage: "sparkle",
                tint: .purple,
                statusDot: store.isReady ? .green : nil
            ) {
                Toggle("", isOn: enabledBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            SettingsDivider()
            SettingsRow(
                title: "API Key",
                subtitle: keySubtitle,
                systemImage: "key",
                tint: .purple
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
            SettingsDivider()
            SettingsRow(
                title: "Model",
                subtitle: "Any OpenRouter model id, e.g. \(OpenRouterStore.defaultModel).",
                systemImage: "cpu",
                tint: .purple
            ) {
                TextField(OpenRouterStore.defaultModel, text: $modelDraft)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                    .onSubmit { store.setModel(modelDraft) }
                    .onChange(of: modelDraft) { store.setModel(modelDraft) }
            }
        }
        .sheet(isPresented: $askingConsent) {
            OpenRouterConsentSheet(
                onCancel: { askingConsent = false },
                onAccept: {
                    askingConsent = false
                    store.setEnabled(true)
                })
        }
        // The key/model can change underneath this pane (settings sync applying a remote file).
        .onChange(of: store.apiKey) { if store.apiKey != keyDraft { keyDraft = store.apiKey } }
        .onChange(of: store.model) { if store.model != modelDraft { modelDraft = store.model } }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { store.isEnabled },
            set: { enabled in
                if enabled {
                    askingConsent = true
                } else {
                    store.setEnabled(false)
                }
            })
    }

    private var aiStatus: String {
        guard store.isEnabled else {
            return "Translate and fix grammar with an AI model. Off — no service is contacted."
        }
        guard !store.apiKey.isEmpty else {
            return "On, but no API key is set — Selection Tools falls back to on-device services."
        }
        return "Selection Tools translates and checks grammar through \(OpenRouterStore.provider)."
    }

    private var keySubtitle: String {
        switch store.validation {
        case .unknown: "Stored on this Mac and included in settings backups and sync."
        case .checking: "Checking key with \(OpenRouterStore.provider)…"
        case .valid(let detail): detail
        case .invalid(let message): message
        }
    }
}

private struct OpenRouterConsentSheet: View {
    let onCancel: () -> Void
    let onAccept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            HStack(spacing: Theme.Spacing.lg) {
                Image(systemName: "network")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.purple)
                Text("Turn on AI translate & grammar?")
                    .font(.headline)
            }

            Text(
                "When you run Translate or Check Grammar, Spotter sends the selected text and your "
                    + "instructions to \(OpenRouterStore.provider) using your API key, and your "
                    + "chosen model answers. Nothing is sent at any other time, and nothing is "
                    + "sent while this is off."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Theme.Spacing.lg) {
                Link(destination: OpenRouterStore.providerURL) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(OpenRouterStore.providerURL.host() ?? "Provider")
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
