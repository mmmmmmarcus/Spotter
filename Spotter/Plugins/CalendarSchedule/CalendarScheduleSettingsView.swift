import SwiftUI

/// One pane for the whole calendar feature: the schedule screen and the widget card share every
/// preference here, since both read the same store.
struct CalendarScheduleSettingsView: View {
    @ObservedObject var store: DashboardWidgetsStore

    var body: some View {
        SettingsPane(title: "Calendar") {
            Section("Calendars") {
                SettingsRow(title: "Calendar Access", subtitle: accessSubtitle) {
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
                    SettingsRow(title: "Account") {
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

                SettingsRow(title: "All-Day Events") {
                    Toggle("", isOn: includesAllDayEventsBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }
        }
        .task { store.refresh() }
    }

    /// Only the states the trailing control cannot show on its own: Allow… and Granted speak for
    /// themselves, a refusal or a partial grant does not.
    private var accessSubtitle: String? {
        switch store.calendarAccess {
        case .notDetermined, .fullAccess: return nil
        case .denied: return "Calendar access was denied. You can change it in System Settings."
        case .restricted: return "Calendar access is restricted on this Mac."
        case .writeOnly:
            return "Write-only access cannot show events; grant full access to continue."
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
