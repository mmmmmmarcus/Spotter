import SwiftUI

struct SelectionToolsSettingsView: View {

    var body: some View {
        // Search has nothing to configure: its one binding lives in Settings ▸ Shortcuts with every
        // other launcher command.
        SettingsPane(title: "Search") {}
    }
}
