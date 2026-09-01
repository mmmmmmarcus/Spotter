import SwiftUI

/// One pane for the whole calendar feature: the schedule screen and the widget card share every
/// preference here, since both read the same store.
struct CalendarScheduleSettingsView: View {
    @EnvironmentObject private var plugins: PluginRegistry
    @ObservedObject var store: DashboardWidgetsStore

    var body: some View {
        SettingsPane(
            title: "Calendar",
            subtitle: "Your upcoming events in the launcher, one keystroke from a meeting's call."
        ) {
            SettingsCard(header: "Plugin") {
                SettingsRow(
                    title: "Calendar",
                    subtitle:
                        "Browse the days ahead with My Schedule and join meetings directly. The widget card keeps showing either way.",
                    systemImage: "calendar", tint: .red
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { plugins.isEnabled(.calendarSchedule) },
                            set: { plugins.setEnabled($0, for: .calendarSchedule) })
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }

            SettingsCard(header: "Calendars") {
                SettingsRow(
                    title: "Calendar Access",
                    subtitle: accessSubtitle,
                    systemImage: "lock.open", tint: .blue
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

                if store.calendarAccess == .fullAccess {
                    SettingsDivider()
                    SettingsRow(
                        title: "Account",
                        subtitle: "All Accounts includes every event calendar available to macOS.",
                        systemImage: "person.crop.circle", tint: .blue
                    ) {
                        Picker("", selection: calendarSourceBinding) {
                            Text("All Accounts").tag("")
                            ForEach(store.calendarAccounts) { account in
                                Text(account.title).tag(account.id)
                            }
                            if let selected = store.preferences.calendarSourceIdentifier,
                                !store.calendarAccounts.contains(where: { $0.id == selected })
                            {
                                Text("Unavailable Account").tag(selected)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 220)
                    }
                }

                SettingsDivider()
                SettingsRow(
                    title: "All-Day Events",
                    subtitle: "Include all-day entries in the schedule and the widget card.",
                    systemImage: "sun.max", tint: .blue
                ) {
                    Toggle("", isOn: includesAllDayEventsBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }

            SettingsCard(header: "Shortcuts") {
                SettingsRow(
                    title: "My Schedule",
                    subtitle: "Open the upcoming events screen from anywhere.",
                    systemImage: "calendar.day.timeline.left", tint: .red
                ) {
                    ShortcutRecorder(action: .plugin(.openCalendarSchedule))
                }
            }
        }
        .task { store.refresh() }
    }

    private var accessSubtitle: String {
        switch store.calendarAccess {
        case .notDetermined: return "Allow read access to show your events."
        case .denied: return "Calendar access was denied. You can change it in System Settings."
        case .restricted: return "Calendar access is restricted on this Mac."
        case .writeOnly:
            return "Write-only access cannot show events; grant full access to continue."
        case .fullAccess: return "Spotter can read upcoming events from your macOS calendars."
        }
    }

    private var calendarSourceBinding: Binding<String> {
        Binding(
            get: { store.preferences.calendarSourceIdentifier ?? "" },
            set: { store.setCalendarSourceIdentifier($0) })
    }

    private var includesAllDayEventsBinding: Binding<Bool> {
        Binding(
            get: { store.preferences.includesAllDayEvents },
            set: { store.setIncludesAllDayEvents($0) })
    }
}
