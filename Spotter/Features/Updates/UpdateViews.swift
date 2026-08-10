import SwiftUI

/// Settings entry point for the updater: a manual check plus the consent-gated daily check.
struct UpdatesSettingsCard: View {
    @ObservedObject private var store = AppCore.shared.updates
    @Environment(\.openURL) private var openURL
    @State private var askingConsent = false

    var body: some View {
        SettingsCard(header: "Updates") {
            SettingsRow(
                title: "Spotter \(currentVersion)",
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

/// Focused end-to-end update flow opened by the launcher command.
struct UpdateWindowView: View {
    @ObservedObject private var store = AppCore.shared.updates
    @Environment(\.openURL) private var openURL
    let close: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.xxl) {
            Spacer(minLength: 0)

            statusIcon

            VStack(spacing: Theme.Spacing.sm) {
                Text(title)
                    .font(.title2.weight(.bold))
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            HStack(spacing: Theme.Spacing.lg) {
                Spacer()
                Button("Close", action: close)
                    .keyboardShortcut(.cancelAction)
                primaryAction
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            VisualEffectView(material: .contentBackground, blending: .behindWindow)
                .ignoresSafeArea()
        )
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch store.status {
        case .checking, .installing:
            ProgressView()
                .controlSize(.large)
        case .upToDate:
            Image(systemName: "checkmark.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
        case .idle, .available:
            Image(systemName: "arrow.down.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(.blue)
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        switch store.status {
        case .checking, .installing:
            EmptyView()
        case .available(let release):
            if release.zipAssetURL != nil {
                Button("Install Update") {
                    Task { await store.installAvailableUpdate() }
                }
                .keyboardShortcut(.defaultAction)
            } else {
                Button("View Release") {
                    openURL(release.pageURL)
                }
                .keyboardShortcut(.defaultAction)
            }
        case .idle, .upToDate, .failed:
            Button("Check Again") {
                Task { await store.checkNow() }
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private var currentVersion: String {
        store.currentVersion.map(String.init(describing:)) ?? "this version"
    }

    private var title: String {
        switch store.status {
        case .idle: "Ready to Check"
        case .checking: "Checking for Updates…"
        case .upToDate: "Spotter is up to date"
        case .available(let release): "Spotter \(release.version.description) is available"
        case .installing: "Installing Update…"
        case .failed: "Unable to Update"
        }
    }

    private var message: String {
        switch store.status {
        case .idle:
            "Check \(UpdateStore.provider) Releases for a newer version of Spotter."
        case .checking:
            "Checking the \(channelName) channel from Spotter \(currentVersion)."
        case .upToDate:
            "You're running the latest \(channelName) version, Spotter \(currentVersion)."
        case .available(let release) where release.zipAssetURL != nil:
            "Spotter \(currentVersion) will be replaced after the download and signature are verified, then Spotter will relaunch."
        case .available:
            "This release does not include an in-app update archive. Open the release page to install it manually."
        case .installing:
            "Downloading and verifying the signed app. Spotter will relaunch when installation finishes."
        case .failed(let error):
            error
        }
    }

    private var channelName: String {
        switch store.channel {
        case .stable: "stable"
        case .beta: "beta"
        }
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
