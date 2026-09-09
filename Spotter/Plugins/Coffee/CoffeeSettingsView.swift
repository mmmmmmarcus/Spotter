import SwiftUI

struct CoffeeSettingsView: View {
    @EnvironmentObject private var plugins: PluginRegistry
    @ObservedObject private var coffee = AppCore.shared.coffee

    var body: some View {
        SettingsPane(
            title: "Caffeinate",
            subtitle: "Keep your Mac awake without changing Energy Saver."
        ) {
            SettingsCard(header: "Plugin") {
                SettingsRow(
                    title: "Caffeinate",
                    subtitle: coffee.state.summary,
                    systemImage: "cup.and.saucer", tint: .orange
                ) {
                    Toggle("", isOn: enabledBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }

            SettingsCard(header: "What Stays Awake") {
                SettingsRow(
                    title: "Keep the Display On",
                    subtitle: "Off, the screen may still sleep while the system stays awake.",
                    systemImage: "display", tint: .orange
                ) {
                    Toggle("", isOn: $coffee.options.keepsDisplayAwake)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                SettingsDivider()
                SettingsRow(
                    title: "Keep Disks Spinning",
                    subtitle: "Prevents idle disk sleep — useful during long transfers.",
                    systemImage: "internaldrive", tint: .orange
                ) {
                    Toggle("", isOn: $coffee.options.keepsDiskAwake)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { plugins.isEnabled(.coffee) },
            set: { plugins.setEnabled($0, for: .coffee) })
    }
}
