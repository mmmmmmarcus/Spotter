import SwiftUI

struct DashboardWidgetsSettingsView: View {
    @ObservedObject var store: DashboardWidgetsStore
    private static let timeZoneIdentifiers = TimeZone.knownTimeZoneIdentifiers.sorted()

    var body: some View {
        SettingsPane(
            title: "Dashboard Widgets",
            subtitle: "At-a-glance information above launcher results when the search is empty."
        ) {
            SettingsCard(header: "Widgets") {
                SettingsRow(
                    title: "Clock",
                    subtitle: "Analog time in the selected time zone.",
                    systemImage: "clock", tint: .orange
                ) {
                    widgetToggle(.clock)
                }
                SettingsDivider()
                SettingsRow(
                    title: "Next Event",
                    subtitle: "The next event from the selected calendar account.",
                    systemImage: "calendar.badge.clock", tint: .blue
                ) {
                    widgetToggle(.nextEvent)
                }
            }

            SettingsCard(header: "Clock Details") {
                SettingsRow(
                    title: "Time Zone",
                    subtitle: "System Default follows changes made in macOS Settings.",
                    systemImage: "globe", tint: .orange
                ) {
                    Picker("", selection: clockTimeZoneBinding) {
                        Text("System Default (\(TimeZone.autoupdatingCurrent.identifier))")
                            .tag("")
                        ForEach(Self.timeZoneIdentifiers, id: \.self) { identifier in
                            Text(identifier.replacingOccurrences(of: "_", with: " "))
                                .tag(identifier)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 250)
                }
            }

            SettingsCard(header: "Calendar Details") {
                SettingsRow(
                    title: "Calendar Access",
                    subtitle: calendarSubtitle,
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
                    subtitle: "Include all-day entries when choosing the next event.",
                    systemImage: "sun.max", tint: .blue
                ) {
                    Toggle("", isOn: includesAllDayEventsBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }

        }
        .task { store.refresh() }
    }

    private var calendarSubtitle: String {
        switch store.calendarAccess {
        case .notDetermined: return "Allow read access to show the next event."
        case .denied: return "Calendar access was denied. You can change it in System Settings."
        case .restricted: return "Calendar access is restricted on this Mac."
        case .writeOnly: return "Write-only access cannot show events; grant full access to continue."
        case .fullAccess: return "Spotter can read upcoming events from your macOS calendars."
        }
    }

    private func widgetToggle(_ widget: DashboardWidgetKind) -> some View {
        Toggle("", isOn: widgetBinding(widget))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
    }

    private func widgetBinding(_ widget: DashboardWidgetKind) -> Binding<Bool> {
        Binding(
            get: { store.isWidgetEnabled(widget) },
            set: { store.setWidgetEnabled(widget, enabled: $0) })
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

    private var clockTimeZoneBinding: Binding<String> {
        Binding(
            get: { store.preferences.clockTimeZoneIdentifier ?? "" },
            set: { store.setClockTimeZoneIdentifier($0) })
    }
}
