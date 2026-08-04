import SwiftUI

struct SystemCommandsSettingsView: View {
    @EnvironmentObject private var plugins: PluginRegistry

    var body: some View {
        SettingsPane(
            title: "System Commands",
            subtitle: "Run everyday macOS actions from the launcher."
        ) {
            SettingsCard(header: "Plugin") {
                SettingsRow(
                    title: "System Commands",
                    subtitle: "Lock, sleep, media keys, volume, appearance, trash, Bluetooth and more.",
                    systemImage: "switch.2", tint: .teal
                ) {
                    Toggle("", isOn: enabledBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }

            SettingsCallout(
                title: "Destructive commands always confirm",
                message: "Restart, Shut Down, Log Out, Empty Trash and Quit All Applications show a dialog first, with Return bound to Cancel so a reflexive second press can't trigger them.",
                systemImage: "exclamationmark.shield")

            SettingsCard(header: "Shortcuts") {
                ForEach(Array(SystemCommandCatalog.all.enumerated()), id: \.element.id.rawValue) {
                    index, command in
                    if index > 0 { SettingsDivider() }
                    SettingsRow(
                        title: command.name,
                        subtitle: command.confirmation == .required ? "Asks before running" : nil,
                        systemImage: command.sfSymbol, tint: .teal
                    ) {
                        ShortcutRecorder(action: .plugin(.systemCommand(command.id)))
                    }
                }
            }
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { plugins.isEnabled(.systemCommands) },
            set: { plugins.setEnabled($0, for: .systemCommands) })
    }
}
