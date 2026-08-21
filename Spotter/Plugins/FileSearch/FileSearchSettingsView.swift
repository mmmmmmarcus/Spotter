import SwiftUI

struct FileSearchSettingsView: View {
    @EnvironmentObject private var plugins: PluginRegistry

    var body: some View {
        SettingsPane(
            title: "File Search",
            subtitle:
                "Find files and folders by name. Spotter reads the Spotlight index macOS already keeps — it builds, stores and watches no index of its own."
        ) {
            SettingsCard(header: "Plugin") {
                SettingsRow(
                    title: "File Search",
                    subtitle: "Search files and folders by name from the palette.",
                    systemImage: "doc.text.magnifyingglass", tint: .teal
                ) {
                    Toggle("", isOn: pluginEnabled)
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
            }
            SettingsCard(header: "What Is Searched") {
                SettingsRow(
                    title: "Your Home Folder",
                    subtitle:
                        "Visible top-level folders and items, iCloud Drive, and any cloud providers you have installed.",
                    systemImage: "house", tint: .teal
                ) { EmptyView() }
                SettingsDivider()
                SettingsRow(
                    title: "Never Searched",
                    subtitle:
                        "~/Library, hidden files, the inside of app bundles, and build folders such as node_modules, DerivedData, build, dist, target and Pods.",
                    systemImage: "eye.slash", tint: .teal
                ) { EmptyView() }
                SettingsDivider()
                SettingsRow(
                    title: "Filenames Only",
                    subtitle:
                        "File contents are never read. Results inherit whatever Spotlight has already indexed.",
                    systemImage: "textformat", tint: .teal
                ) { EmptyView() }
            }
            SettingsCard(header: "Shortcut") {
                SettingsRow(
                    title: "Search Files", subtitle: "Open file search in the Spotter palette.",
                    systemImage: "keyboard", tint: .teal
                ) {
                    ShortcutRecorder(action: .plugin(.openFileSearch))
                }
            }
        }
    }

    private var pluginEnabled: Binding<Bool> {
        Binding(
            get: { plugins.isEnabled(.fileSearch) },
            set: { plugins.setEnabled($0, for: .fileSearch) })
    }
}
