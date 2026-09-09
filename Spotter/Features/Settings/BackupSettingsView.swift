import SwiftUI

struct BackupSettingsView: View {
    @EnvironmentObject private var settingsSync: SettingsSyncManager

    var body: some View {
        SettingsPane(title: "Backup") {
            Section("Sync") {
                SettingsRow(title: "Export & Import") {
                    HStack(spacing: Theme.Spacing.md) {
                        Button("Export…") { BackupActions.exportSettings() }
                            .controlSize(.small)
                        Button("Import…") { BackupActions.importSettings() }
                            .controlSize(.small)
                    }
                }
                SettingsRow(
                    title: "Settings File", subtitle: settingsSync.fileURL.map(displayPath)
                ) {
                    Button("Choose Folder…") { BackupActions.chooseSettingsSyncFolder() }
                        .controlSize(.small)
                }
                SettingsRow(title: "Automatic Sync", subtitle: settingsSync.statusText) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { settingsSync.isEnabled },
                            set: { settingsSync.setEnabled($0) }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .disabled(settingsSync.fileURL == nil || settingsSync.isWorking)
                }
            }
        }
    }

    /// The whole path, not just the folder: the folder is the user's choice but the file inside it is
    /// Spotter's, and a row that named only the folder would hide which file is actually in use.
    private func displayPath(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }
}
