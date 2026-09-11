import Combine
import SwiftUI

/// One row per permission: the permission's name, and a trailing control that is either the way to
/// grant it or the word Granted. The one-second poll is what keeps a grant revoked in System
/// Settings from still reading as granted here. The rows name no features — a list of which
/// features declare a permission reads the same on every install, and macOS's own pane is where the
/// grant actually lives.
struct PermissionsSettingsView: View {
    @ObservedObject private var dashboard = AppCore.shared.dashboardWidgets
    @ObservedObject private var weather = AppCore.shared.dashboardWeather
    @State private var accessibilityTrusted = Permissions.isAccessibilityTrusted()
    @State private var screenRecordingAllowed = Permissions.isScreenRecordingAllowed()
    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        SettingsPane(title: "Permissions") {
            Section {
                SettingsRow(title: "Accessibility") {
                    if accessibilityTrusted {
                        grantedBadge
                    } else {
                        Button("Grant Access…") { Permissions.openAccessibilitySettings() }
                            .controlSize(.small)
                    }
                }

                // Automation has no queryable per-app state: macOS asks the first time Spotter drives
                // another app, so the row can only ever offer the pane it is managed in.
                SettingsRow(title: "App Automation") {
                    Button("Open Settings…") { Permissions.openAutomationSettings() }
                        .controlSize(.small)
                }

                SettingsRow(title: "Calendar Events") {
                    calendarControl
                }

                SettingsRow(title: "Location", containsMultipleControls: true) {
                    locationControl
                    Button("Open Settings…") { Permissions.openLocationSettings() }
                        .controlSize(.small)
                        .accessibilityLabel("Open Location Services Settings")
                }

                SettingsRow(title: "Screen Recording") {
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

    @ViewBuilder
    private var locationControl: some View {
        if !weather.isEnabled {
            Text("Not in use")
                .foregroundStyle(.secondary)
        } else {
            switch weather.authorization {
            case .authorized:
                grantedBadge
            case .denied:
                statusBadge("Denied", symbol: "xmark.circle.fill", color: .orange)
            case .restricted:
                statusBadge("Restricted", symbol: "lock.circle.fill", color: .orange)
            case .notDetermined:
                Text("Not requested")
                    .foregroundStyle(.secondary)
            }
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
