import Combine
import SwiftUI

struct PermissionsSettingsView: View {
    @EnvironmentObject private var plugins: PluginRegistry
    @ObservedObject private var dashboard = AppCore.shared.dashboardWidgets
    @State private var accessibilityTrusted = Permissions.isAccessibilityTrusted()
    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        SettingsPane(
            title: "Permissions",
            subtitle: "Access Spotter needs to work with other apps."
        ) {
            SettingsCard(header: "Accessibility") {
                SettingsRow(
                    title: "Accessibility",
                    subtitle: accessibilitySubtitle,
                    systemImage: "accessibility",
                    tint: .blue
                ) {
                    statusBadge
                }
                SettingsDivider()
                SettingsRow(
                    title: accessibilityTrusted ? "Manage in System Settings" : "Grant access",
                    subtitle: "Opens Privacy & Security › Accessibility.",
                    systemImage: "arrow.up.forward.app",
                    tint: .secondary
                ) {
                    Button(accessibilityTrusted ? "Open…" : "Open Settings…") {
                        Permissions.openAccessibilitySettings()
                    }
                }
            }

            SettingsCard(header: "Automation") {
                SettingsRow(
                    title: "App Automation",
                    subtitle: automationSubtitle,
                    systemImage: "gearshape.2",
                    tint: .purple
                ) {
                    Button("Open Settings…") {
                        Permissions.openAutomationSettings()
                    }
                }
            }

            SettingsCard(header: "Calendar") {
                SettingsRow(
                    title: "Calendar Events",
                    subtitle: calendarSubtitle,
                    systemImage: "calendar",
                    tint: .blue
                ) {
                    calendarStatusBadge
                }
                SettingsDivider()
                SettingsRow(
                    title: calendarActionTitle,
                    subtitle: calendarActionSubtitle,
                    systemImage: "arrow.up.forward.app",
                    tint: .secondary
                ) {
                    calendarAction
                }
            }
        }
        .onAppear {
            accessibilityTrusted = Permissions.isAccessibilityTrusted()
            dashboard.refreshCalendarAuthorization()
        }
        .onReceive(refreshTimer) { _ in
            let trusted = Permissions.isAccessibilityTrusted()
            if trusted != accessibilityTrusted { accessibilityTrusted = trusted }
            dashboard.refreshCalendarAuthorization()
        }
    }

    private var statusBadge: some View {
        HStack(spacing: Theme.Spacing.xs + 1) {
            Image(
                systemName: accessibilityTrusted
                    ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
            Text(accessibilityTrusted ? "Granted" : "Not granted")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(accessibilityTrusted ? Color.green : Color.orange)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .background(
            Capsule().fill((accessibilityTrusted ? Color.green : Color.orange).opacity(0.14))
        )
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

    private var calendarStatusBadge: some View {
        let status = calendarStatus
        return HStack(spacing: Theme.Spacing.xs + 1) {
            Image(systemName: status.symbol)
            Text(status.label)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(status.color)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Capsule().fill(status.color.opacity(0.14)))
    }

    private var calendarSubtitle: String {
        let names = plugins.features(requiring: .calendar).map(\.name).joined(separator: ", ")
        return names.isEmpty
            ? "No feature currently declares this permission."
            : "Used by \(names) to show upcoming events."
    }

    private var calendarStatus: (label: String, symbol: String, color: Color) {
        switch dashboard.calendarAccess {
        case .notDetermined:
            return ("Not requested", "calendar.badge.exclamationmark", .orange)
        case .denied:
            return ("Denied", "xmark.circle.fill", .red)
        case .restricted:
            return ("Restricted", "lock.circle.fill", .orange)
        case .writeOnly:
            return ("Write only", "pencil.circle.fill", .orange)
        case .fullAccess:
            return ("Granted", "checkmark.circle.fill", .green)
        }
    }

    private var calendarActionTitle: String {
        switch dashboard.calendarAccess {
        case .notDetermined, .writeOnly: "Grant full access"
        case .denied, .fullAccess: "Manage in System Settings"
        case .restricted: "Calendar access is restricted"
        }
    }

    private var calendarActionSubtitle: String {
        switch dashboard.calendarAccess {
        case .notDetermined: "Shows the macOS calendar permission prompt."
        case .writeOnly: "Upgrade the existing write-only grant to full access."
        case .denied, .fullAccess: "Opens Privacy & Security › Calendars."
        case .restricted: "This Mac's policy does not allow Calendar access."
        }
    }

    @ViewBuilder
    private var calendarAction: some View {
        switch dashboard.calendarAccess {
        case .notDetermined, .writeOnly:
            if dashboard.isRequestingCalendarAccess {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button("Allow…") { dashboard.requestCalendarAccess() }
            }
        case .denied, .fullAccess:
            Button("Open Settings…") { Permissions.openCalendarSettings() }
        case .restricted:
            Text("Unavailable")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }
}
