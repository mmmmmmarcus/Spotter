import SwiftUI

/// Settings entry point for the updater: a manual check plus the consent-gated daily check.
struct UpdatesSettingsSection: View {
    @ObservedObject private var store = AppCore.shared.updates
    @Environment(\.openURL) private var openURL
    @State private var askingConsent = false

    var body: some View {
        Section("Updates") {
            SettingsRow(title: "Spotter \(currentVersion)", subtitle: statusText) {
                trailingControl
            }
            SettingsRow(title: "Check Automatically") {
                Toggle("", isOn: autoCheckBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            if let release = store.latestRelease {
                ScrollView {
                    UpdateReleaseNotesView(release: release)
                }
                .frame(maxHeight: 240)
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
        case .checking:
            RingLoader(progress: nil, size: Theme.Size.ringLoaderSmall)
        case .installing:
            RingLoader(progress: store.installProgress?.fraction, size: Theme.Size.ringLoaderSmall)
        case .available(let release):
            if release.zipAssetURL != nil {
                Button("Update to \(release.version.description)…") {
                    Task { await store.installAvailableUpdate() }
                }
                .controlSize(.small)
            } else {
                Button("View \(release.version.description)…") {
                    openURL(release.pageURL)
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

    private var currentVersion: String {
        store.currentVersion.map(String.init(describing:)) ?? "—"
    }

    /// Nil until something has actually happened — the row reports state, it does not describe the updater.
    private var statusText: String? {
        switch store.status {
        case .idle: nil
        case .checking: "Checking \(UpdateStore.provider)…"
        case .upToDate: "You're on the latest version."
        case .available(let release): "Version \(release.version.description) is available."
        case .installing: store.installProgress?.title
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

struct UpdatePaletteView: View {
    @ObservedObject private var store = AppCore.shared.updates
    let selection: Int
    let onActivate: (Int) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(store.presentation.actions.enumerated()), id: \.element) { index, action in
                    let busy = action == .upgrade ? store.status == .installing : store.status == .checking
                    PluginPaletteRow(item: item(for: action), selected: selection == index,
                        isInteractive: !store.status.isBusy, isBusy: busy,
                        progress: action == .upgrade ? store.installProgress?.fraction : nil)
                        .contentShape(Rectangle())
                        .onTapGesture { onActivate(index) }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { onActivate(index) }
                }
                PluginPaletteRow(item: PluginPaletteItem(id: "version",
                    title: "Current Version · " + (store.currentVersion?.description ?? "—"),
                    subtitle: nil, icon: .symbol("info.circle"), primaryActionTitle: ""),
                    selected: false, isInteractive: false)
                if let release = store.latestRelease {
                    Divider()
                        .padding(.vertical, Theme.Spacing.md)
                    UpdateReleaseNotesView(release: release)
                        .padding(.horizontal, Theme.Spacing.md)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.md)
            .hideNativeScrollers()
        }
        .edgeDissolve()
        .thinScrollbar()
    }

    private func item(for action: UpdatePaletteAction) -> PluginPaletteItem {
        if action == .check {
            return PluginPaletteItem(id: action.rawValue, title: "Check for Updates",
                subtitle: store.presentation.checkDetail, icon: .symbol("arrow.clockwise"),
                subtitleLineLimit: 3, primaryActionTitle: "Check for Updates")
        }
        let version = store.availableRelease?.version.description ?? ""
        let installing = store.status == .installing
        let manual = store.availableRelease?.zipAssetURL == nil
        let detail = installing ? store.installProgress?.title
            : (manual ? "Open the release page to install this version." : "Download, install, and relaunch Spotter.")
        let percentage = store.installProgress?.fraction.map { "\(Int($0 * 100))%" }
        return PluginPaletteItem(id: action.rawValue, title: "Update to " + version,
            subtitle: [detail, percentage].compactMap { $0 }.joined(separator: " · "),
            icon: .symbol("arrow.down.circle"), primaryActionTitle: manual ? "View Release" : "Install Update")
    }
}

private struct UpdateReleaseNotesView: View {
    let release: UpdateRelease

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Release Notes · \(release.version.description)")
                .font(Theme.Typography.rowTitle)
                .foregroundStyle(Theme.Colors.textSecondary)
            if release.releaseNotes.isEmpty {
                Text("No release notes were provided for this version.")
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                AIChatMarkdownText(text: release.releaseNotes)
                    .foregroundStyle(.primary)
            }
            Link("View on GitHub", destination: release.pageURL)
                .font(Theme.Typography.rowTrailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct UpdateConsentSheet: View {
    let onCancel: () -> Void
    let onAccept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            Text("Check for updates automatically?")
                .font(.headline)

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
