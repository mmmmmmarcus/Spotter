import SwiftUI

struct MoleSettingsView: View {
    @ObservedObject private var mole = AppCore.shared.mole
    @State private var pathDraft = AppCore.shared.mole.binaryPathOverride

    var body: some View {
        SettingsPane(title: "Mole") {
            if !mole.isInstalled {
                SettingsCallout(
                    title: "Mole not found",
                    message: "Install it with `brew install mole`, or point Spotter at the binary below.",
                    tint: .orange)
            }

            Section("Command Line Tool") {
                SettingsRow(
                    title: "Binary Path",
                    subtitle: mole.binaryPath.map { "Using \($0)" }
                        ?? "Searched Homebrew's usual locations and found nothing."
                ) {
                    TextField("/opt/homebrew/bin/mole", text: $pathDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                        .onSubmit { mole.setBinaryPathOverride(pathDraft) }
                        .onChange(of: pathDraft) { mole.setBinaryPathOverride(pathDraft) }
                }
            }
        }
    }
}
