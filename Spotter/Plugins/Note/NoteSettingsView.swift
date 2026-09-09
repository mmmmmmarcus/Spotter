import SwiftUI

struct NoteSettingsView: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var sync: NoteFolderSyncManager
    @State private var syncing = false

    var body: some View {
        SettingsPane(title: "Notes") {
            Section("Storage") {
                SettingsRow(title: "Stored Locally") {
                    Text("\(store.notes.count) \(store.notes.count == 1 ? "note" : "notes")")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Section("Sync") {
                SettingsRow(title: "Notes Folder", subtitle: folderSubtitle) {
                    HStack(spacing: Theme.Spacing.md) {
                        if sync.isEnabled {
                            Button("Stop Syncing") { sync.disconnect() }
                                .controlSize(.small)
                        }
                        Button(sync.isEnabled ? "Change…" : "Choose…") {
                            BackupActions.chooseNotesFolder()
                        }
                        .controlSize(.small)
                    }
                }
                if sync.isEnabled {
                    SettingsRow(title: "Sync Now") {
                        Button(syncing ? "Syncing…" : "Sync Now") {
                            syncing = true
                            Task {
                                await sync.syncNow()
                                syncing = false
                            }
                        }
                        .controlSize(.small)
                        .disabled(syncing || sync.isWorking)
                    }
                }
            }

            // Kept deliberately: this is what a Note file is and what a missing one is not — the
            // difference between syncing and losing work.
            SettingsCallout(
                title: "One Markdown file per note",
                message:
                    "Each Note is written as a Markdown file named after its title, with a small "
                    + "front-matter header carrying its identifier, dates and color. Put the folder "
                    + "in iCloud Drive and your Macs share it. Deleting a note is recorded "
                    + "explicitly, so a file that hasn’t downloaded yet is never mistaken for one "
                    + "you deleted, and disconnecting leaves every note and every file in place.",
                tint: .blue)
        }
    }

    private var folderSubtitle: String {
        guard let url = sync.folderURL else { return sync.statusText }
        return url.path(percentEncoded: false) + " · " + sync.statusText
    }
}
