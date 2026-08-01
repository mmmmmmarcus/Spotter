import SwiftUI

struct WorldClockSettingsView: View {
    @EnvironmentObject private var plugins: PluginRegistry

    var body: some View {
        SettingsPane(
            title: "World Clock",
            subtitle: "See the current local time in cities around the world."
        ) {
            SettingsCard(header: "Plugin") {
                SettingsRow(
                    title: "World Clock",
                    subtitle: "Uses the time-zone data built into macOS. No network access.",
                    systemImage: "globe.americas",
                    tint: .blue,
                    statusDot: plugins.isEnabled(.worldClock) ? .green : nil
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { plugins.isEnabled(.worldClock) },
                            set: { plugins.setEnabled($0, for: .worldClock) })
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }

            SettingsCard(header: "Examples") {
                SettingsRow(
                    title: "SF time now",
                    subtitle: "You can also try “time in Tokyo”, “London time”, or “上海时间”.",
                    systemImage: "text.magnifyingglass",
                    tint: .blue
                ) {
                    EmptyView()
                }
            }
        }
    }
}
