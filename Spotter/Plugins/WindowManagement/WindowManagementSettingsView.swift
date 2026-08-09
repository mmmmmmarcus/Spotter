import SwiftUI

struct WindowManagementSettingsView: View {
    @EnvironmentObject private var plugins: PluginRegistry
    @AppStorage(WindowManagementDefaults.gapKey) private var gap = 0
    @AppStorage(WindowManagementDefaults.cycleKey) private var cycleOnRepeat = false

    var body: some View {
        SettingsPane(
            title: "Window Management",
            subtitle: "Position the frontmost window from the launcher or a shortcut."
        ) {
            SettingsCard(header: "Plugin") {
                SettingsRow(
                    title: "Window Management",
                    subtitle: "Halves, quarters, thirds, sizing, display moves and fullscreen.",
                    systemImage: "macwindow.on.rectangle", tint: .blue
                ) {
                    Toggle("", isOn: enabledBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }

            SettingsCard(header: "Layout") {
                SettingsRow(
                    title: "Gap",
                    subtitle: "Padding left around a positioned window, in points.",
                    systemImage: "square.dashed", tint: .blue
                ) {
                    Picker("", selection: $gap) {
                        Text("None").tag(0)
                        Text("4 pt").tag(4)
                        Text("8 pt").tag(8)
                        Text("12 pt").tag(12)
                        Text("16 pt").tag(16)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsDivider()
                SettingsRow(
                    title: "Cycle on Repeat",
                    subtitle: "Repeating the same command steps through its variants (e.g. half → two-thirds → third).",
                    systemImage: "arrow.triangle.2.circlepath", tint: .blue
                ) {
                    Toggle("", isOn: $cycleOnRepeat)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }

            ForEach(WindowCommand.Group.allCases, id: \.rawValue) { group in
                SettingsCard(header: group.title) {
                    let commands = WindowCommandCatalog.all.filter { $0.group == group }
                    ForEach(Array(commands.enumerated()), id: \.element.id.rawValue) { index, command in
                        if index > 0 { SettingsDivider() }
                        SettingsRow(
                            title: command.name, subtitle: nil,
                            systemImage: command.sfSymbol, tint: .blue
                        ) {
                            ShortcutRecorder(action: .plugin(.windowCommand(command.id)))
                        }
                    }
                }
            }
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { plugins.isEnabled(.windowManagement) },
            set: { plugins.setEnabled($0, for: .windowManagement) })
    }
}
