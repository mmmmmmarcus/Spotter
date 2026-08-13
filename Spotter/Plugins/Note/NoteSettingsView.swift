import SwiftUI

struct NoteSettingsView: View {
    @EnvironmentObject private var plugins: PluginRegistry
    @ObservedObject var store: NoteStore
    @ObservedObject var sync: NoteSyncManager

    var body: some View {
        SettingsPane(
            title: "Notes",
            subtitle: "Capture local Markdown notes in a lightweight floating window."
        ) {
            SettingsCard(header: "Plugin") {
                SettingsRow(
                    title: "Notes",
                    subtitle: "Includes unlimited local notes, Markdown formatting, and todos.",
                    systemImage: "note.text", tint: .yellow
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { plugins.isEnabled(.note) },
                            set: { plugins.setEnabled($0, for: .note) })
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }

            SettingsCard(header: "Shortcuts") {
                SettingsRow(
                    title: "Open Notes", subtitle: "Focus the last active note.",
                    systemImage: "keyboard", tint: .yellow
                ) {
                    ShortcutRecorder(action: .plugin(.openNotes))
                }
                SettingsDivider()
                SettingsRow(
                    title: "New Note", subtitle: "Create and immediately focus an empty note.",
                    systemImage: "keyboard.badge.ellipsis", tint: .yellow
                ) {
                    ShortcutRecorder(action: .plugin(.newNote))
                }
            }

            SettingsCard(header: "Storage") {
                SettingsRow(
                    title: "Stored Locally",
                    subtitle: "Notes stay on this Mac inside Spotter’s bundle-specific Application Support folder.",
                    systemImage: "internaldrive", tint: .yellow
                ) {
                    Text("\(store.notes.count) \(store.notes.count == 1 ? "note" : "notes")")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            SettingsCard(header: "Sync") {
                SettingsRow(
                    title: "Notes File",
                    subtitle: sync.fileURL.map(displayPath)
                        ?? "Choose an existing Notes file or create one in iCloud Drive.",
                    systemImage: sync.isICloudLocation ? "icloud" : "doc.text",
                    tint: .blue
                ) {
                    HStack(spacing: Theme.Spacing.md) {
                        Button("Choose…") { NoteSyncActions.connectExisting() }
                            .controlSize(.small)
                        Button("Create…") { NoteSyncActions.create() }
                            .controlSize(.small)
                    }
                }
                SettingsDivider()
                SettingsRow(
                    title: "Automatic Sync",
                    subtitle: sync.statusText,
                    systemImage: sync.errorMessage == nil
                        ? "arrow.triangle.2.circlepath" : "exclamationmark.triangle.fill",
                    tint: sync.errorMessage == nil ? .teal : .orange
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { sync.isEnabled },
                            set: { sync.setEnabled($0) }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .disabled(sync.fileURL == nil || sync.isWorking)
                }
                if sync.fileURL != nil {
                    SettingsDivider()
                    SettingsRow(
                        title: "Disconnect",
                        subtitle: "Stops Notes sync without deleting the JSON file.",
                        systemImage: "link.badge.minus",
                        tint: .secondary
                    ) {
                        Button("Disconnect") { sync.disconnect() }
                            .controlSize(.small)
                    }
                }
            }
            SettingsCallout(
                title: "Notes sync separately",
                message:
                    "Automatic Settings Sync never reads or writes this file. Keep it private; "
                    + "placing it in iCloud Drive lets macOS carry Notes between your Macs.",
                systemImage: "lock.doc",
                tint: .blue)
        }
    }

    private func displayPath(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }
}
