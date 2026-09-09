import SwiftUI

struct KillProcessSettingsView: View {
    @AppStorage("kill-process.sort") private var sortRaw = ProcessSort.cpu.rawValue
    @AppStorage("kill-process.group-apps") private var groupApps = true
    @AppStorage("kill-process.search-paths") private var searchPaths = false
    @AppStorage("kill-process.search-pids") private var searchPIDs = true
    @AppStorage("kill-process.prioritize-apps") private var prioritizeApps = true
    @AppStorage("kill-process.show-path") private var showPath = false
    @AppStorage("kill-process.show-pid") private var showPID = true
    @AppStorage("kill-process.refresh-seconds") private var refreshSeconds = 2.0

    var body: some View {
        SettingsPane(title: "Kill Process") {
            SettingsCard(header: "Process List") {
                SettingsRow(title: "Sort By") {
                    Picker("", selection: $sortRaw) {
                        ForEach(ProcessSort.allCases, id: \.rawValue) { value in
                            Text(value.title).tag(value.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }
                SettingsDivider()
                toggleRow("Group Applications", $groupApps)
                SettingsDivider()
                toggleRow("Search Paths", $searchPaths)
                SettingsDivider()
                toggleRow("Search PIDs", $searchPIDs)
                SettingsDivider()
                toggleRow("Prioritize Apps", $prioritizeApps)
                SettingsDivider()
                toggleRow("Show PID", $showPID)
                SettingsDivider()
                toggleRow("Show Path", $showPath)
                SettingsDivider()
                SettingsRow(title: "Refresh Interval") {
                    Picker("", selection: $refreshSeconds) {
                        Text("0.5 sec").tag(0.5)
                        Text("1 sec").tag(1.0)
                        Text("2 sec").tag(2.0)
                        Text("5 sec").tag(5.0)
                    }.labelsHidden()
                }
            }
        }
    }

    private func toggleRow(_ title: String, _ binding: Binding<Bool>) -> some View {
        SettingsRow(title: title) {
            Toggle("", isOn: binding).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
    }
}
