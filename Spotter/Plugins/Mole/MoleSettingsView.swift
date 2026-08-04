import SwiftUI

struct MoleSettingsView: View {
    @EnvironmentObject private var plugins: PluginRegistry
    @ObservedObject private var mole = AppCore.shared.mole
    @State private var pathDraft = AppCore.shared.mole.binaryPathOverride

    var body: some View {
        SettingsPane(
            title: "Mole",
            subtitle: "Drive the Mole CLI from the launcher."
        ) {
            SettingsCard(header: "Plugin") {
                SettingsRow(
                    title: "Mole",
                    subtitle: "System health and cleanup history render in the palette; cleaning, uninstalling and analyzing open in Terminal.",
                    systemImage: "chart.pie", tint: .green,
                    statusDot: mole.isInstalled ? .green : .orange
                ) {
                    Toggle("", isOn: enabledBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }

            if !mole.isInstalled {
                SettingsCallout(
                    title: "Mole not found",
                    message: "Install it with `brew install mole`, or point Spotter at the binary below.",
                    systemImage: "exclamationmark.triangle",
                    tint: .orange)
            }

            SettingsCard(header: "Command Line Tool") {
                SettingsRow(
                    title: "Binary Path",
                    subtitle: mole.binaryPath.map { "Using \($0)" }
                        ?? "Searched Homebrew's usual locations and found nothing.",
                    systemImage: "terminal", tint: .green
                ) {
                    TextField("/opt/homebrew/bin/mole", text: $pathDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                        .onSubmit { mole.setBinaryPathOverride(pathDraft) }
                        .onChange(of: pathDraft) { mole.setBinaryPathOverride(pathDraft) }
                }
            }

            SettingsCard(header: "Shortcuts") {
                SettingsRow(
                    title: "System Status", subtitle: "Open Mole's health readout in the palette.",
                    systemImage: "waveform.path.ecg", tint: .green
                ) {
                    ShortcutRecorder(action: .plugin(.openMoleStatus))
                }
                SettingsDivider()
                SettingsRow(
                    title: "Cleanup History", subtitle: "Open recent Mole sessions in the palette.",
                    systemImage: "clock.arrow.circlepath", tint: .green
                ) {
                    ShortcutRecorder(action: .plugin(.openMoleHistory))
                }
            }

            SettingsCallout(
                title: "Destructive commands stay in Terminal",
                message: "Clean, Uninstall, Optimize, Purge and Installer delete files and need Mole's own confirmations, so Spotter hands them to Terminal rather than running them silently.",
                systemImage: "hand.raised")
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { plugins.isEnabled(.mole) },
            set: { plugins.setEnabled($0, for: .mole) })
    }
}
