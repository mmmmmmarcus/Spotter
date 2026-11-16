import Combine
import EventKit
import SwiftUI

/// One row per permission: the permission's name, and a trailing control that is either the way to
/// grant it or the word Granted. `PermissionsMonitor` supplies the states that cost a system call,
/// polling off the main actor only while this pane is on screen, so a grant revoked in System
/// Settings stops reading as granted here. The rows name no features — a list of which features
/// declare a permission reads the same on every install, and macOS's own pane is where the grant
/// actually lives.
struct PermissionsSettingsView: View {
    @ObservedObject private var dashboard = AppCore.shared.dashboardWidgets
    @ObservedObject private var weather = AppCore.shared.dashboardWeather
    @ObservedObject private var monitor = AppCore.shared.permissions
    /// Set once the user has taken the system's Screen Recording prompt, which is the point at
    /// which the relaunch requirement becomes something the row has to say out loud.
    @State private var didRequestScreenRecording = false

    var body: some View {
        SettingsPane(title: "Permissions") {
            Section {
                SettingsRow(title: "Accessibility", systemImage: "accessibility") {
                    if monitor.reading.accessibilityTrusted {
                        grantedBadge
                    } else {
                        Button("Grant Access…") { Permissions.openAccessibilitySettings() }
                            .controlSize(.small)
                    }
                }

                SettingsRow(title: "Calendar Events", systemImage: "calendar") {
                    calendarControl
                }

                SettingsRow(title: "Location", systemImage: "location", containsMultipleControls: true) {
                    locationControl
                    if weather.authorization != .authorized {
                        Button("Open Settings…") { Permissions.openLocationSettings() }
                            .controlSize(.small)
                            .accessibilityLabel("Open Location Services Settings")
                    }
                }

                SettingsRow(
                    title: "Screen Recording", subtitle: screenRecordingSubtitle,
                    systemImage: "record.circle"
                ) {
                    screenRecordingControl
                }
            }

            // Automation is granted per target, so one row per app Spotter drives. Only the ones
            // installed here are listed.
            Section("App Automation") {
                ForEach(monitor.reading.automation) { row in
                    // Only the denied row carries two controls; the rest are a single word, which
                    // reads better as a `LabeledContent` pair.
                    SettingsRow(
                        title: row.target.name,
                        systemImage: row.target.symbolName,
                        containsMultipleControls: row.permission == .denied
                    ) {
                        automationControl(for: row)
                    }
                }
            }
        }
        .onAppear {
            monitor.startWatching()
            dashboard.refreshCalendarAuthorization()
        }
        .onDisappear { monitor.stopWatching() }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
            dashboard.refreshCalendarAuthorization()
        }
    }

    // MARK: - Automation

    @ViewBuilder
    private func automationControl(for row: AutomationReading) -> some View {
        switch row.permission {
        case .granted:
            grantedBadge
        case .denied:
            statusBadge("Denied", symbol: "xmark.circle.fill", color: .orange)
            Button("Open Settings…") { Permissions.openAutomationSettings() }
                .controlSize(.small)
                .accessibilityLabel("Open Automation Settings for \(row.target.name)")
        case .notDetermined:
            Text("Not yet asked")
                .foregroundStyle(.secondary)
        case .targetNotRunning:
            // Honest and nothing to fix: macOS reports no stored grant for an app that is not
            // running, and Spotter sends a stopped app nothing either.
            Text("Not running")
                .foregroundStyle(.secondary)
        case .unknown(let status):
            Text("Unknown (\(status))")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Screen Recording

    /// macOS applies a fresh Screen Recording grant to the next launch, not to this one, so a button
    /// that appears to do nothing is the expected outcome of taking the prompt.
    private var screenRecordingSubtitle: String? {
        guard didRequestScreenRecording, !monitor.reading.screenRecordingGranted else { return nil }
        return "macOS applies a new Screen Recording grant the next time Spotter launches."
    }

    @ViewBuilder
    private var screenRecordingControl: some View {
        if monitor.reading.screenRecordingGranted {
            grantedBadge
        } else if didRequestScreenRecording {
            Button("Open Settings…") { Permissions.openScreenRecordingSettings() }
                .controlSize(.small)
        } else {
            Button("Allow…") {
                _ = Permissions.requestScreenRecording()
                didRequestScreenRecording = true
                monitor.refresh()
            }
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private var locationControl: some View {
        if weather.authorization == .authorized {
            grantedBadge
        } else if !weather.isEnabled {
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
        Text("Granted")
            .foregroundStyle(.green)
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
