import SwiftUI

struct SelectionToolsSettingsView: View {
    @EnvironmentObject private var plugins: PluginRegistry

    var body: some View {
        SettingsPane(
            title: "Selection Tools",
            subtitle: "Search text selected in the frontmost app without keeping a clipboard copy."
        ) {
            SettingsCard(header: "Plugin") {
                SettingsRow(
                    title: "Selection Tools",
                    subtitle: "Send selected text to Google Search in your default browser.",
                    systemImage: "selection.pin.in.out", tint: .teal
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

            SettingsCard(header: "Shortcut") {
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
