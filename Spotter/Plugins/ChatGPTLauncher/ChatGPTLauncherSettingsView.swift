import SwiftUI

struct ChatGPTLauncherSettingsView: View {
    @EnvironmentObject private var plugins: PluginRegistry

    var body: some View {
        SettingsPane(
            title: "Send to ChatGPT",
            subtitle: "Hand a prompt from Spotter to a new Chat session in the ChatGPT desktop app."
        ) {
            SettingsCard(header: "Plugin") {
                SettingsRow(
                    title: "Send to ChatGPT",
                    subtitle: "Show the launcher command and prompt screen.",
                    systemImage: "bubble.left.and.bubble.right",
                    tint: .green
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { plugins.isEnabled(.chatGPTLauncher) },
                            set: { plugins.setEnabled($0, for: .chatGPTLauncher) })
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }

            SettingsCallout(
                title: "Requires the current ChatGPT app for macOS.",
                message:
                    "Spotter first switches the app to Chat, verifies the Chat composer, then opens "
                    + "ChatGPT's official codex:// new-chat link. Return is pressed only when Chat "
                    + "mode and the complete prefilled prompt are both verified.",
                systemImage: "checkmark.shield",
                tint: .green)

            SettingsCard(header: "Access") {
                SettingsRow(
                    title: "Accessibility",
                    subtitle:
                        "Used only to switch modes, inspect the focused Chat composer, and send the verified Return key.",
                    systemImage: "hand.raised",
                    tint: .blue
                ) {
                    Button("Open Settings…") { Permissions.openAccessibilitySettings() }
                        .controlSize(.small)
                }
                SettingsDivider()
                SettingsRow(
                    title: "Open Prompt Screen",
                    subtitle: "Assign an optional global shortcut.",
                    systemImage: "keyboard",
                    tint: .purple
                ) {
                    ShortcutRecorder(action: .plugin(.openChatGPTLauncher))
                }
            }

            SettingsCard(header: "Privacy") {
                SettingsRow(
                    title: "No Spotter History",
                    subtitle:
                        "Spotter does not save or copy the prompt. ChatGPT sends it through your signed-in account.",
                    systemImage: "lock.shield",
                    tint: .green
                ) { EmptyView() }
            }
        }
    }
}
