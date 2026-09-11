import SwiftUI

struct BackupSettingsView: View {
    @EnvironmentObject private var settingsSync: SettingsSyncManager

    var body: some View {
        SettingsPane(title: "Backup") {
            Section("Sync") {
                SettingsRow(
                    title: "Export & Import",
                    subtitle: "Manual backups include Notes, settings, shortcuts, API keys and private content such as clipboard history and AI chats.",
                    containsMultipleControls: true
                ) {
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
            Section("Backup & Sync Contents") {
                SettingsCallout(
                    title: "Keep backup and sync files private",
                    message: "Both contain API keys, network-service consent and private content in readable JSON. Importing a trusted file can replace existing settings and content.")
                SettingsRow(
                    title: "Notes Sync",
                    subtitle: "Automatic Settings Sync excludes Note content. Notes sync separately through your chosen Markdown folder. Manual backups include Notes for recovery."
                ) {
                    Button("Open Notes Settings") { AppCore.shared.showSettings(plugin: .note) }
                        .controlSize(.small)
                }
                SettingsCallout(
                    title: "Stays on this Mac",
                    message: "System privacy grants, sync-folder paths, current location and daily activity counts are not included.")
            }
        }
    }

    /// The whole path, not just the folder: the folder is the user's choice but the file inside it is
    /// Spotter's, and a row that named only the folder would hide which file is actually in use.
    private func displayPath(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }
}
