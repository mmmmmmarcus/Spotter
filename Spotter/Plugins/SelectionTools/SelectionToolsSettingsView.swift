import SwiftUI

struct SelectionToolsSettingsView: View {
    @EnvironmentObject private var plugins: PluginRegistry

    var body: some View {
        SettingsPane(
            title: "Search",
            subtitle: "Search the text you have selected, in your default browser."
        ) {
            SettingsCard(header: "Plugin") {
                SettingsRow(
                    title: "Search",
                    subtitle: "Capture selected text without keeping a clipboard copy.",
                    systemImage: "magnifyingglass", tint: .teal
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { plugins.isEnabled(.selectionTools) },
                            set: { plugins.setEnabled($0, for: .selectionTools) })
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }

            SettingsCard(header: "Shortcuts") {
                SettingsRow(
                    title: "Search Selected Text",
                    subtitle: "Recommended: Hyper + S",
                    systemImage: "magnifyingglass", tint: .teal
                ) {
                    ShortcutRecorder(action: .plugin(.searchSelectedText))
                }
            }
        }
    }
}
