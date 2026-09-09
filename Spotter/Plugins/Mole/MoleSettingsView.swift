import SwiftUI

struct MoleSettingsView: View {
    @ObservedObject private var mole = AppCore.shared.mole
    @State private var pathDraft = AppCore.shared.mole.binaryPathOverride

    var body: some View {
        SettingsPane(
            title: "Mole",
            subtitle: "Drive the Mole CLI from the launcher."
        ) {
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
                title: "Everything runs in the launcher.",
                message:
                    "Installer files are found by Spotter's own scan of the same folders Mole checks, "
                    + "and deleting one moves it to the Trash — no Terminal, ever.",
                systemImage: "macwindow")
        }
    }
}
