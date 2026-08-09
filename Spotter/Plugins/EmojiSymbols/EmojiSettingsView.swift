import SwiftUI

struct EmojiSettingsView: View {
    @EnvironmentObject private var plugins: PluginRegistry
    @ObservedObject private var settings = AppCore.shared.settings

    var body: some View {
        SettingsPane(
            title: "Emoji & Symbols",
            subtitle: "Search emoji and symbols, and paste them into any app."
        ) {
            SettingsCard(header: "Plugin") {
                SettingsRow(
                    title: "Emoji & Symbols",
                    subtitle: "Search and paste emoji and symbols into any app.",
                    systemImage: "face.smiling",
                    tint: .yellow
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { plugins.isEnabled(.emoji) },
                            set: { plugins.setEnabled($0, for: .emoji) })
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }

            SettingsCard(header: "Global Shortcuts") {
                SettingsRow(
                    title: "Emoji & Symbols",
                    subtitle: "Summon the emoji and symbols palette.",
                    systemImage: "face.smiling",
                    tint: .yellow
                ) {
                    ShortcutRecorder(action: .plugin(.openEmoji))
                }
            }

            SettingsCard(header: "Appearance") {
                SettingsRow(
                    title: "Emoji Skin Tone",
                    subtitle: "Applied when an emoji supports skin tones; pastes use it too.",
                    systemImage: "hand.wave",
                    tint: .orange
                ) {
                    // A hand per tone, Raycast style — quicker to scan than a dropdown of tone names.
                    Picker("", selection: $settings.emojiSkinTone) {
                        ForEach(EmojiSkinTone.allCases) { tone in
                            Text(tone.sample).tag(tone)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
    }
}
