import SwiftUI

struct DashboardWidgetsSettingsView: View {
    @EnvironmentObject private var plugins: PluginRegistry
    @ObservedObject var store: DashboardWidgetsStore

    var body: some View {
        SettingsPane(
            title: "Dashboard Widgets",
            subtitle: "At-a-glance information above launcher results when the search is empty."
        ) {
            SettingsCard(header: "Plugin") {
                SettingsRow(
                    title: "Dashboard Widgets",
                    subtitle: "Shows time, month, next event, and AI usage in the launcher.",
                    systemImage: "rectangle.3.group", tint: .purple
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { plugins.isEnabled(.dashboardWidgets) },
                            set: { plugins.setEnabled($0, for: .dashboardWidgets) })
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }

            SettingsCard(header: "Calendar") {
                SettingsRow(
                    title: "Next Event",
                    subtitle: calendarSubtitle,
                    systemImage: "calendar.badge.clock", tint: .blue
                ) {
                    switch store.calendarAccess {
                    case .notDetermined, .writeOnly:
                        if store.isRequestingCalendarAccess {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Button("Allow…") { store.requestCalendarAccess() }
                                .controlSize(.small)
                        }
                    case .denied:
                        Button("Open Settings…") { Permissions.openCalendarSettings() }
                            .controlSize(.small)
                    case .restricted:
                        Text("Restricted")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    case .fullAccess:
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                }
            }

            SettingsCard(header: "AI Usage") {
                SettingsRow(
                    title: "Local Usage Metadata",
                    subtitle:
                        "Reads Codex rate-limit metadata and CodexBar's local widget/history cache. It does not start another app, access credentials, send network requests, or parse conversation content.",
                    systemImage: "chart.bar", tint: .purple
                ) {
                    Button("Refresh") { Task { await store.refresh() } }
                        .controlSize(.small)
                }
            }
        }
        .task { await store.refresh() }
    }

    private var calendarSubtitle: String {
        switch store.calendarAccess {
        case .notDetermined: return "Allow read access to show the next event and dots on event days."
        case .denied: return "Calendar access was denied. You can change it in System Settings."
        case .restricted: return "Calendar access is restricted on this Mac."
        case .writeOnly: return "Write-only access cannot show events; grant full access to continue."
        case .fullAccess: return "Spotter can read upcoming events from your macOS calendars."
        }
    }
}
