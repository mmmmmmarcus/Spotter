import Combine
import SwiftUI

/// One row per permission: the row explains who needs it and its trailing control is either the way
/// to grant it or the word Granted. The one-second poll is what keeps a grant revoked in System
/// Settings from still reading as granted here.
struct PermissionsSettingsView: View {
    @EnvironmentObject private var plugins: PluginRegistry
    @ObservedObject private var dashboard = AppCore.shared.dashboardWidgets
    @State private var accessibilityTrusted = Permissions.isAccessibilityTrusted()
    @State private var screenRecordingAllowed = Permissions.isScreenRecordingAllowed()
    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        SettingsPane(title: "Permissions") {
            SettingsCard {
                SettingsRow(title: "Accessibility", subtitle: accessibilitySubtitle) {
                    if accessibilityTrusted {
                        grantedBadge
                    } else {
                        Button("Grant Access…") { Permissions.openAccessibilitySettings() }
                            .controlSize(.small)
                    }
                }

                SettingsDivider()
                // Automation has no queryable per-app state: macOS asks the first time Spotter drives
                // another app, so the row can only ever offer the pane it is managed in.
                SettingsRow(title: "App Automation", subtitle: automationSubtitle) {
                    Button("Open Settings…") { Permissions.openAutomationSettings() }
                        .controlSize(.small)
                }

                SettingsDivider()
                SettingsRow(title: "Calendar Events", subtitle: calendarSubtitle) {
                    calendarControl
                }

                SettingsDivider()
                SettingsRow(title: "Screen Recording", subtitle: screenRecordingSubtitle) {
                    if screenRecordingAllowed {
                        grantedBadge
                    } else {
                        Button("Allow…") {
                            _ = Permissions.requestScreenRecording()
                            screenRecordingAllowed = Permissions.isScreenRecordingAllowed()
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
        .onAppear {
            accessibilityTrusted = Permissions.isAccessibilityTrusted()
            screenRecordingAllowed = Permissions.isScreenRecordingAllowed()
            dashboard.refreshCalendarAuthorization()
        }
        .onReceive(refreshTimer) { _ in
            let trusted = Permissions.isAccessibilityTrusted()
            if trusted != accessibilityTrusted { accessibilityTrusted = trusted }
            let recordingAllowed = Permissions.isScreenRecordingAllowed()
            if recordingAllowed != screenRecordingAllowed {
                screenRecordingAllowed = recordingAllowed
            }
            dashboard.refreshCalendarAuthorization()
        }
    }

    private var grantedBadge: some View {
        statusBadge("Granted", symbol: "checkmark.circle.fill", color: .green)
    }

    private func statusBadge(_ label: String, symbol: String, color: Color) -> some View {
        HStack(spacing: Theme.Spacing.xs + 1) {
            Image(systemName: symbol)
            Text(label)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Capsule().fill(color.opacity(0.14)))
    }

    private var accessibilitySubtitle: String {
        let names = plugins.features(requiring: .accessibility).map(\.name).joined(separator: ", ")
        return names.isEmpty
            ? "No feature currently declares this permission."
            : "Used by \(names) to observe configured triggers, read selected text, or type into "
                + "the app you were using."
    }

    private var automationSubtitle: String {
        let names = plugins.features(requiring: .automation).map(\.name).joined(separator: ", ")
        let featureText = names.isEmpty ? "launcher actions" : "launcher actions and \(names)"
        return "Used by \(featureText) to control another application only after you choose an action."
    }

    private var screenRecordingSubtitle: String {
        let names = plugins.features(requiring: .screenRecording).map(\.name).joined(separator: ", ")
        return names.isEmpty
            ? "No feature currently declares this permission."
            : "Used by \(names) to read only the screen region you select."
    }

    private var calendarSubtitle: String {
        let names = plugins.features(requiring: .calendar).map(\.name).joined(separator: ", ")
        return names.isEmpty
            ? "No feature currently declares this permission."
            : "Used by \(names) to show upcoming events."
    }

    /// Calendar is the one permission with more than two states, so its single control carries them:
    /// granted reads Granted, a partial or unasked grant offers the prompt, a refusal offers the pane
    /// and a managed Mac says the choice isn't the user's to make.
    @ViewBuilder
    private var calendarControl: some View {
        switch dashboard.calendarAccess {
        case .fullAccess:
            grantedBadge
        case .notDetermined, .writeOnly:
            if dashboard.isRequestingCalendarAccess {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button("Allow…") { dashboard.requestCalendarAccess() }
                    .controlSize(.small)
            }
        case .denied:
            Button("Open Settings…") { Permissions.openCalendarSettings() }
                .controlSize(.small)
        case .restricted:
            statusBadge("Restricted", symbol: "lock.circle.fill", color: .orange)
        }
    }
}
