import SwiftUI

struct FileSearchSettingsView: View {

    var body: some View {
        SettingsPane(title: "File Search") {
            // The three lines are the plugin's privacy boundary, not a description of a control:
            // what Spotter reads, what it never reaches, and that contents are never opened.
            SettingsCard(header: "What Is Searched") {
                SettingsRow(
                    title: "Your Home Folder",
                    subtitle:
                        "Visible top-level folders and items, iCloud Drive, and any cloud providers you have installed."
                ) { EmptyView() }
                SettingsDivider()
                SettingsRow(
                    title: "Never Searched",
                    subtitle:
                        "~/Library, hidden files, the inside of app bundles, and build folders such as node_modules, DerivedData, build, dist, target and Pods."
                ) { EmptyView() }
                SettingsDivider()
                SettingsRow(
                    title: "Filenames Only",
                    subtitle:
                        "File contents are never read. Results inherit whatever Spotlight has already indexed."
                ) { EmptyView() }
            }
        }
    }
}
