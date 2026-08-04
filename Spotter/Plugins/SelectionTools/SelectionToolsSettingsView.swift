import SwiftUI

struct SelectionToolsSettingsView: View {
    @EnvironmentObject private var plugins: PluginRegistry

    var body: some View {
        SettingsPane(
            title: "Selection Tools",
            subtitle: "Use text selected in the frontmost app without touching the clipboard."
        ) {
            SettingsCard(header: "Plugin") {
                SettingsRow(
                    title: "Selection Tools",
                    subtitle: "Search, translate, and check grammar from one native plugin.",
                    systemImage: "selection.pin.in.out", tint: .teal,
                    statusDot: plugins.isEnabled(.selectionTools) ? .green : nil
                ) {
                    Toggle("", isOn: enabledBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }

            SettingsCard(header: "System Services") {
                SettingsRow(
                    title: "Capture",
                    subtitle: "Reads the selection through Accessibility. When an app hides it (canvas tools, some web apps), Spotter briefly copies the selection and then restores your clipboard.",
                    systemImage: "text.cursor", tint: .teal
                ) {
                    Text("Automatic")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                SettingsDivider()
                SettingsRow(
                    title: "Translation",
                    subtitle: "Uses only macOS Translation languages already installed on this Mac; selected text stays on-device.",
                    systemImage: "translate", tint: .teal
                ) {
                    Text("System Preferred")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                SettingsDivider()
                SettingsRow(
                    title: "Grammar",
                    subtitle: "Uses the local macOS spelling and grammar service; selected text stays on-device.",
                    systemImage: "text.badge.checkmark", tint: .teal
                ) {
                    Text("On-device")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            SettingsCard(header: "Shortcuts") {
                shortcutRow(
                    title: "Search Selected Text",
                    subtitle: "Recommended: Hyper + S",
                    symbol: "magnifyingglass",
                    action: .searchSelectedText)
                SettingsDivider()
                shortcutRow(
                    title: "Translate Selected Text",
                    subtitle: "Recommended: Hyper + T",
                    symbol: "translate",
                    action: .translateSelectedText)
                SettingsDivider()
                shortcutRow(
                    title: "Check Selected Text Grammar",
                    subtitle: "Recommended: Hyper + G",
                    symbol: "text.badge.checkmark",
                    action: .checkSelectedTextGrammar)
            }
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { plugins.isEnabled(.selectionTools) },
            set: { plugins.setEnabled($0, for: .selectionTools) })
    }

    private func shortcutRow(
        title: String, subtitle: String, symbol: String, action: PluginActionKey
    ) -> some View {
        SettingsRow(
            title: title, subtitle: subtitle, systemImage: symbol, tint: .teal
        ) {
            ShortcutRecorder(action: .plugin(action))
        }
    }
}
