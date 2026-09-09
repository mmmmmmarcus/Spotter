import SwiftUI

struct EmojiSettingsView: View {
    @ObservedObject private var settings = AppCore.shared.settings

    var body: some View {
        SettingsPane(title: "Emoji & Symbols") {
            SettingsCard(header: "Appearance") {
                SettingsRow(title: "Emoji Skin Tone") {
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
