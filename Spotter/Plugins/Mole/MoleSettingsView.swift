import SwiftUI

struct MoleSettingsView: View {
    @EnvironmentObject private var plugins: PluginRegistry
    @ObservedObject private var mole = AppCore.shared.mole
    @State private var pathDraft = AppCore.shared.mole.binaryPathOverride

    private static let shortcuts: [(String, String, String, PluginActionKey)] = [
        ("All Commands", "Open the Mole hub listing every screen.", "circle.grid.2x2", .openMoleMenu),
        (
            "System Status", "Open Mole's health readout in the palette.", "waveform.path.ecg",
            .openMoleStatus
        ),
        ("Clean", "Preview reclaimable caches, then clean.", "sparkles", .openMoleClean),
        ("Optimize", "Preview system maintenance, then apply.", "wand.and.stars", .openMoleOptimize),
        ("Purge", "Preview old build artifacts, then delete.", "hammer", .openMolePurge),
        ("Uninstall App", "Search installed apps and remove one.", "trash", .openMoleUninstall),
        ("Analyze Disk", "Browse folders by size.", "chart.pie", .openMoleAnalyze),
        (
            "Cleanup History", "Open recent Mole sessions in the palette.", "clock.arrow.circlepath",
            .openMoleHistory
        ),
        (
            "Remove Installers", "List installer files and move them to the Trash.", "shippingbox",
            .openMoleInstaller
        ),
    ]

    var body: some View {
        SettingsPane(
            title: "Mole",
            subtitle: "Drive the Mole CLI from the launcher."
        ) {
            SettingsCard(header: "Plugin") {
                SettingsRow(
                    title: "Mole",
                    subtitle: "Health, cleanup, optimize, purge, uninstall and disk analysis, all rendered in the palette.",
                    systemImage: "chart.pie", tint: .green
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

            SettingsCallout(
                title: "Spotter asks before anything is deleted.",
                message:
                    "Clean, Optimize, Purge and Uninstall open as previews first; running one needs an "
                    + "explicit confirmation naming what it removes. Uninstall moves apps to the Trash "
                    + "unless you pick Delete Permanently. Homebrew casks and indistinguishable copies "
                    + "stay reveal-only so Spotter never removes the wrong app or breaks Homebrew state. "
                    + "Admin-only system caches are always skipped.",
                systemImage: "hand.raised",
                tint: .green)

            SettingsCard(header: "Shortcuts") {
                ForEach(Array(Self.shortcuts.enumerated()), id: \.offset) { index, entry in
                    if index > 0 { SettingsDivider() }
                    SettingsRow(
                        title: entry.0, subtitle: entry.1, systemImage: entry.2, tint: .green
                    ) {
                        ShortcutRecorder(action: .plugin(entry.3))
                    }
                }
            }

            SettingsCallout(
                title: "Everything runs in the launcher.",
                message:
                    "Installer files are found by Spotter's own scan of the same folders Mole checks, "
                    + "and deleting one moves it to the Trash — no Terminal, ever.",
                systemImage: "macwindow")
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { plugins.isEnabled(.mole) },
            set: { plugins.setEnabled($0, for: .mole) })
    }
}
