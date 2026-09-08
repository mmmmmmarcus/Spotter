import SwiftUI

struct NoteSettingsView: View {
    @EnvironmentObject private var plugins: PluginRegistry
    @ObservedObject var store: NoteStore
    @ObservedObject var sync: NoteFolderSyncManager
    @State private var syncing = false

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

            SettingsCard(header: "Appearance") {
                SettingsRow(
                    title: "Auto Window Sizing",
                    subtitle: "Grows and shrinks the window to fit the note. Off keeps the size you drag it to.",
                    systemImage: "arrow.up.and.down.and.arrow.left.and.right", tint: .yellow
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { store.autoWindowSizing },
                            set: { store.setAutoWindowSizing($0) })
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
                SettingsDivider()
                SettingsRow(
                    title: "Window Transparency",
                    subtitle: "Fades the Note background through to the desktop, leaving text and controls untouched.",
                    systemImage: "circle.lefthalf.filled", tint: .yellow
                ) {
                    HStack(spacing: Theme.Spacing.md) {
                        Slider(
                            value: Binding(
                                get: { store.windowTransparency },
                                set: { store.setWindowTransparency($0) }),
                            in: 0...NoteStore.maximumWindowTransparency,
                            step: 0.05)
                            .frame(width: 140)
                        Text(store.windowTransparency.formatted(.percent.precision(.fractionLength(0))))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .trailing)
                    }
                }
            }

            SettingsCard(header: "Sync") {
                SettingsRow(
                    title: "Notes Folder",
                    subtitle: folderSubtitle,
                    systemImage: sync.errorMessage == nil ? "folder" : "exclamationmark.triangle",
                    tint: sync.errorMessage == nil ? .blue : .orange
                ) {
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
                    SettingsDivider()
                    SettingsRow(
                        title: "Sync Now",
                        subtitle: "Read the folder and write out any pending changes immediately.",
                        systemImage: "arrow.triangle.2.circlepath", tint: .teal
                    ) {
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

            SettingsCallout(
                title: "One Markdown file per note",
                message:
                    "Each Note is written as a Markdown file named after its title, with a small "
                    + "front-matter header carrying its identifier, dates and color. Put the folder "
                    + "in iCloud Drive and your Macs share it. Deleting a note is recorded "
                    + "explicitly, so a file that hasn’t downloaded yet is never mistaken for one "
                    + "you deleted, and disconnecting leaves every note and every file in place.",
                systemImage: "doc.text",
                tint: .blue)
        }
    }

    private var folderSubtitle: String {
        guard let url = sync.folderURL else {
            return "Choose a folder — in iCloud Drive to share Notes between Macs. "
                + sync.statusText
        }
        return url.path(percentEncoded: false) + " · " + sync.statusText
    }
}
