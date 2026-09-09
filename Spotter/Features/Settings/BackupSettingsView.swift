import AppKit
import SwiftUI

struct BackupSettingsView: View {
    @EnvironmentObject private var settingsSync: SettingsSyncManager
    @ObservedObject private var runningApps = AppCore.shared.runningApps
    @State private var raycastFile: URL?
    @State private var passphrase = ""
    @State private var importing = false
    @State private var status: Status?
    @State private var selection: RaycastImportOptions = .all

    private enum Status {
        case success(String)
        case failure(String)
    }

    private var raycastRunning: Bool {
        runningApps.runningBundleIDs.contains(where: BackupActions.isRaycastBundleID)
    }

    var body: some View {
        SettingsPane(title: "Backup") {
            SettingsCard(header: "Sync") {
                SettingsRow(title: "Export & Import") {
                    HStack(spacing: Theme.Spacing.md) {
                        Button("Export…") { BackupActions.exportSettings() }
                            .controlSize(.small)
                        Button("Import…") { BackupActions.importSettings() }
                            .controlSize(.small)
                    }
                }
                SettingsDivider()
                SettingsRow(
                    title: "Settings File", subtitle: settingsSync.fileURL.map(displayPath)
                ) {
                    HStack(spacing: Theme.Spacing.md) {
                        Button("Choose…") { BackupActions.connectSettingsSyncFile() }
                            .controlSize(.small)
                        Button("Create…") { BackupActions.createSettingsSyncFile() }
                            .controlSize(.small)
                    }
                }
                SettingsDivider()
                SettingsRow(title: "Automatic Sync", subtitle: settingsSync.statusText) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { settingsSync.isEnabled },
                            set: { settingsSync.setEnabled($0) }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .disabled(settingsSync.fileURL == nil || settingsSync.isWorking)
                }
                if settingsSync.fileURL != nil {
                    SettingsDivider()
                    SettingsRow(title: "Disconnect") {
                        Button("Disconnect") { settingsSync.disconnect() }
                            .controlSize(.small)
                    }
                }
            }
            SettingsCard(header: "Import from Raycast") {
                SettingsRow(title: "Raycast Export", subtitle: raycastFile?.lastPathComponent) {
                    Button("Choose…") { chooseRaycastFile() }
                        .controlSize(.small)
                }
                SettingsDivider()
                SettingsRow(title: "Passphrase") {
                    SecureField("Passphrase", text: $passphrase)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                        .onSubmit(runRaycastImport)
                }
                SettingsDivider()
                SettingsRow(title: "Import") {
                    if importing {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Import") { runRaycastImport() }
                            .controlSize(.small)
                            .disabled(raycastFile == nil || passphrase.isEmpty || selection.isEmpty)
                    }
                }
                RaycastImportSelection(selection: $selection)
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.bottom, Theme.Spacing.lg)
                conflictCallout
                if let status {
                    SettingsDivider()
                    statusRow(status)
                }
            }
        }
    }

    @ViewBuilder
    private var conflictCallout: some View {
        if raycastRunning {
            SettingsCallout(
                title: "Raycast is running — quit it to avoid hotkey conflicts.", tint: .orange
            ) {
                Button("Quit Raycast") { BackupActions.quitRaycast() }
                    .controlSize(.small)
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.lg)
        }
    }

    /// A failure keeps the callout's tinted box now that no leading glyph is left to carry severity.
    @ViewBuilder
    private func statusRow(_ status: Status) -> some View {
        switch status {
        case .success(let message):
            SettingsRow(title: message) { EmptyView() }
        case .failure(let message):
            SettingsCallout(title: message, tint: .orange)
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.vertical, Theme.Spacing.lg)
        }
    }

    private func chooseRaycastFile() {
        guard let url = BackupActions.pickRaycastFile() else { return }
        raycastFile = url
        status = nil
    }

    private func displayPath(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }

    private func runRaycastImport() {
        guard let file = raycastFile, !passphrase.isEmpty, !selection.isEmpty, !importing else {
            return
        }
        importing = true
        status = nil
        Task {
            defer { importing = false }
            do {
                let outcome = try await BackupActions.importRaycast(
                    file: file, passphrase: passphrase, options: selection)
                var message = BackupActions.summaryText(outcome.summary)
                if outcome.clipboardImported > 0 {
                    message += " Imported \(outcome.clipboardImported) clipboard entries."
                }
                if outcome.missingImages > 0 {
                    message += " \(outcome.missingImages) images were unavailable and skipped."
                }
                status = .success(message)
                passphrase = ""
            } catch {
                status = .failure(error.localizedDescription)
            }
        }
    }
}
