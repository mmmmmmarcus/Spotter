import SwiftUI

struct QuickTimeSettingsView: View {
    @EnvironmentObject private var plugins: PluginRegistry

    var body: some View {
        SettingsPane(title: "QuickTime Recording", subtitle: "Open native recording sessions directly in QuickTime Player.") {
            SettingsCard(header: "Plugin") {
                SettingsRow(title: "QuickTime Recording", subtitle: "Spotter sends an Apple Event only when you run a recording command.", systemImage: "record.circle", tint: .red, statusDot: plugins.isEnabled(.quickTimeRecording) ? .green : nil) {
                    Toggle("", isOn: Binding(get: { plugins.isEnabled(.quickTimeRecording) }, set: { plugins.setEnabled($0, for: .quickTimeRecording) })).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
            }
            SettingsCard(header: "Shortcuts") {
                ForEach(Array(QuickTimeRecordingKind.allCases.enumerated()), id: \.element.id) { index, kind in
                    if index > 0 { SettingsDivider() }
                    SettingsRow(title: kind.title, systemImage: kind.systemImage, tint: .red) {
                        ShortcutRecorder(action: .plugin(.quickTime(kind)))
                    }
                }
            }
            SettingsCallout(title: "QuickTime controls recording permissions", message: "The first run may ask Spotter for Automation access and QuickTime Player for screen, microphone, or camera access.", systemImage: "hand.raised", tint: .orange) {
                Button("Automation Settings…") { Permissions.openAutomationSettings() }
            }
        }
    }
}
