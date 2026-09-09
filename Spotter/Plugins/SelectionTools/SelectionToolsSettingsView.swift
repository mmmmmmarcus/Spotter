import SwiftUI

struct SelectionToolsSettingsView: View {

    var body: some View {
        SettingsPane(
            title: "Search",
            subtitle: "Search the text you have selected, in your default browser."
        ) {
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
