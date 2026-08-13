import SwiftUI

struct NoteSettingsView: View {
    @EnvironmentObject private var plugins: PluginRegistry
    @ObservedObject var store: NoteStore
    @ObservedObject var sync: NoteSyncManager
    @State private var askingConsent = false
    @State private var syncing = false
    @State private var syncFailed = false

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
                    title: "iCloud Sync",
                    subtitle: cloudStatus,
                    systemImage: sync.errorMessage == nil ? "icloud" : "exclamationmark.icloud",
                    tint: sync.errorMessage == nil ? .blue : .orange
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { sync.isEnabled },
                            set: { wantsOn in
                                if wantsOn {
                                    askingConsent = true
                                } else {
                                    sync.setEnabled(false)
                                }
                            }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .disabled(!sync.cloudKitAvailable)
                }
                if sync.isEnabled {
                    SettingsDivider()
                    SettingsRow(
                        title: "Sync Now",
                        subtitle: syncFailed
                            ? "Couldn’t reach iCloud. Check your account or connection."
                            : "Fetch and send pending Note changes immediately.",
                        systemImage: "arrow.triangle.2.circlepath", tint: .teal
                    ) {
                        Button(syncing ? "Syncing…" : "Sync Now") {
                            syncing = true
                            syncFailed = false
                            Task {
                                let succeeded = await sync.syncNow()
                                syncFailed = !succeeded
                                syncing = false
                            }
                        }
                        .controlSize(.small)
                        .disabled(syncing || sync.isWorking)
                    }
                }
            }

            SettingsCallout(
                title: "Private iCloud database",
                message:
                    "Each Note syncs independently through Apple CloudKit. Automatic Settings Sync "
                    + "still excludes Note content, and turning iCloud Sync off keeps every local Note.",
                systemImage: "lock.icloud",
                tint: .blue)
        }
        .sheet(isPresented: $askingConsent) {
            NoteCloudConsentSheet(
                onCancel: { askingConsent = false },
                onAccept: {
                    askingConsent = false
                    sync.setEnabled(true)
                })
        }
    }

    private var cloudStatus: String {
        guard sync.cloudKitAvailable else {
            return "Unavailable in this local self-signed build."
        }
        return sync.statusText
    }
}

private struct NoteCloudConsentSheet: View {
    let onCancel: () -> Void
    let onAccept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            HStack(spacing: Theme.Spacing.lg) {
                Image(systemName: "icloud")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.blue)
                Text("Turn on Notes iCloud Sync?")
                    .font(.headline)
            }

            Text(
                "Spotter sends each Note’s Markdown content, stable identifier, edit dates, and "
                    + "deletions to your private Apple CloudKit database. Changes are queued shortly "
                    + "after editing and synchronized at launch and when iCloud reports updates. "
                    + "Your Macs must use the same iCloud account. Turning sync off stops CloudKit "
                    + "access and deletes Spotter’s local CloudKit state, while keeping local Notes."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Theme.Spacing.lg) {
                Spacer()
                Button("Not Now", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Enable", action: onAccept)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: 440)
    }
}
