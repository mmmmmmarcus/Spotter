import SwiftUI

struct NoteSettingsView: View {
    @EnvironmentObject private var plugins: PluginRegistry
    @ObservedObject var store: NoteStore

    var body: some View {
        SettingsPane(
            title: "Notes",
            subtitle: "Capture local Markdown notes in a lightweight floating window."
        ) {
            SettingsCard(header: "Plugin") {
                SettingsRow(
                    title: "Notes",
                    subtitle: "Includes unlimited local notes, Markdown formatting, and todos.",
                    systemImage: "note.text", tint: .yellow,
                    statusDot: plugins.isEnabled(.note) ? .green : nil
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
        }
    }
}
