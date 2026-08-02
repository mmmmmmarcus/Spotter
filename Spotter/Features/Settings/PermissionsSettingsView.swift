import Combine
import SwiftUI

struct PermissionsSettingsView: View {
    @EnvironmentObject private var plugins: PluginRegistry
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
        }
        .onAppear { accessibilityTrusted = Permissions.isAccessibilityTrusted() }
        .onReceive(refreshTimer) { _ in
            let trusted = Permissions.isAccessibilityTrusted()
            if trusted != accessibilityTrusted { accessibilityTrusted = trusted }
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
        let names = plugins.plugins(requiring: .accessibility).map(\.name).joined(separator: ", ")
        return names.isEmpty
            ? "No installed plugin currently declares this permission."
            : "Used by \(names) to observe configured triggers, read selected text, or type into "
                + "the app you were using."
    }

    private var automationSubtitle: String {
        let names = plugins.plugins(requiring: .automation).map(\.name).joined(separator: ", ")
        return names.isEmpty
            ? "No installed plugin currently declares this permission."
            : "Used by \(names) to control another application after you run a command."
    }
}
