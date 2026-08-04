import SwiftUI

struct KillProcessSettingsView: View {
    @EnvironmentObject private var plugins: PluginRegistry
    @AppStorage("kill-process.sort") private var sortRaw = ProcessSort.cpu.rawValue
    @AppStorage("kill-process.group-apps") private var groupApps = true
    @AppStorage("kill-process.search-paths") private var searchPaths = false
    @AppStorage("kill-process.search-pids") private var searchPIDs = true
    @AppStorage("kill-process.prioritize-apps") private var prioritizeApps = true
    @AppStorage("kill-process.show-path") private var showPath = false
    @AppStorage("kill-process.show-pid") private var showPID = true
    @AppStorage("kill-process.refresh-seconds") private var refreshSeconds = 2.0

    var body: some View {
        SettingsPane(
            title: "Kill Process",
            subtitle: "Inspect and terminate running processes; refreshes only while its palette is open."
        ) {
            SettingsCard(header: "Plugin") {
                toggleRow("Kill Process", "List processes by CPU or memory usage.", "xmark.octagon", pluginsEnabled)
            }
            SettingsCallout(
                title: "Administrator prompt",
                message: "Force-terminating a process Spotter may not signal asks for administrator credentials through the standard macOS prompt. Nothing runs elevated without that per-action approval.",
                systemImage: "lock.shield")
            SettingsCard(header: "Process List") {
                SettingsRow(
                    title: "Sort By", subtitle: "Order the process results in the palette.",
                    systemImage: "arrow.up.arrow.down", tint: .red
                ) {
                    Picker("", selection: $sortRaw) {
                        ForEach(ProcessSort.allCases, id: \.rawValue) { value in
                            Text(value.title).tag(value.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }
                SettingsDivider()
                toggleRow("Group Applications", "Combine app helpers with their parent application.", "rectangle.3.group", $groupApps)
                SettingsDivider()
                toggleRow("Search Paths", "Match the executable path as well as its name.", "folder", $searchPaths)
                SettingsDivider()
                toggleRow("Search PIDs", "Allow numeric process-ID searches.", "number", $searchPIDs)
                SettingsDivider()
                toggleRow("Prioritize Apps", "Move applications above binaries while filtering.", "app", $prioritizeApps)
                SettingsDivider()
                toggleRow("Show PID", "Display process identifiers in result rows.", "number.circle", $showPID)
                SettingsDivider()
                toggleRow("Show Path", "Display executable paths in result rows.", "point.bottomleft.forward.to.point.topright.scurvepath", $showPath)
                SettingsDivider()
                SettingsRow(title: "Refresh Interval", subtitle: "Only refreshes while the Kill Process palette is open.", systemImage: "arrow.clockwise", tint: .red) {
                    Picker("", selection: $refreshSeconds) {
                        Text("0.5 sec").tag(0.5)
                        Text("1 sec").tag(1.0)
                        Text("2 sec").tag(2.0)
                        Text("5 sec").tag(5.0)
                    }.labelsHidden()
                }
            }
            SettingsCard(header: "Shortcut") {
                SettingsRow(title: "Kill Process", subtitle: "Open running processes in the Spotter palette.", systemImage: "keyboard", tint: .red) {
                    ShortcutRecorder(action: .plugin(.openKillProcess))
                }
            }
        }
    }

    private var pluginsEnabled: Binding<Bool> {
        Binding(get: { plugins.isEnabled(.killProcess) }, set: { plugins.setEnabled($0, for: .killProcess) })
    }

    private func toggleRow(
        _ title: String, _ subtitle: String, _ symbol: String, _ binding: Binding<Bool>
    ) -> some View {
        SettingsRow(title: title, subtitle: subtitle, systemImage: symbol, tint: .red) {
            Toggle("", isOn: binding).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
    }
}
