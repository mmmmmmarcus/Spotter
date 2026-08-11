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
        SettingsPane(
            title: "Backup",
            subtitle: "Sync or export your Spotter data, restore a backup, or import from Raycast."
        ) {
            SettingsCard(header: "Spotter") {
                SettingsRow(
                    title: "Export Settings",
                    subtitle:
                        "Save settings, shortcuts, API keys, notes, histories, and other content to JSON.",
                    systemImage: "square.and.arrow.up",
                    tint: .blue
                ) {
                    Button("Export…") { BackupActions.exportSettings() }
                        .controlSize(.small)
                }
                SettingsDivider()
                SettingsRow(
                    title: "Import Settings",
                    subtitle:
                        "Merge a Spotter backup into this Mac; only values present in the file change.",
                    systemImage: "square.and.arrow.down",
                    tint: .green
                ) {
                    Button("Import…") { BackupActions.importSettings() }
                        .controlSize(.small)
                }
            }

            SettingsCard(header: "Sync") {
                SettingsRow(
                    title: "Settings File",
                    subtitle: settingsSync.fileURL.map(displayPath)
                        ?? "Choose an existing JSON file or create one in iCloud Drive.",
                    systemImage: settingsSync.isICloudLocation ? "icloud" : "doc.text",
                    tint: .blue
                ) {
                    HStack(spacing: Theme.Spacing.md) {
                        Button("Choose…") { BackupActions.connectSettingsSyncFile() }
                            .controlSize(.small)
                        Button("Create…") { BackupActions.createSettingsSyncFile() }
                            .controlSize(.small)
                    }
                }
                SettingsDivider()
                SettingsRow(
                    title: "Automatic Sync",
                    subtitle: settingsSync.statusText,
                    systemImage: settingsSync.errorMessage == nil
                        ? "arrow.triangle.2.circlepath" : "exclamationmark.triangle.fill",
                    tint: settingsSync.errorMessage == nil ? .teal : .orange
                ) {
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
                    SettingsRow(
                        title: "Disconnect",
                        subtitle: "Stops syncing without deleting the JSON file.",
                        systemImage: "link.badge.minus",
                        tint: .secondary
                    ) {
                        Button("Disconnect") { settingsSync.disconnect() }
                            .controlSize(.small)
                    }
                }
            }
            SettingsCallout(
                title: "Keep this file private",
                message: "Spotter watches the selected file and mirrors settings, API keys, notes, clipboard images, histories, and other content. Put it in your private iCloud Drive to let macOS carry it between devices; shared folders are not recommended.",
                systemImage: "icloud.and.arrow.up",
                tint: .blue)

            SettingsCard(header: "Import from Raycast") {
                SettingsRow(
                    title: "Raycast Export",
                    subtitle: raycastFile?.lastPathComponent
                        ?? "Choose a .rayconfig file exported from Raycast.",
                    systemImage: "doc.badge.gearshape",
                    tint: .orange
                ) {
                    Button("Choose…") { chooseRaycastFile() }
                        .controlSize(.small)
                }
                SettingsDivider()
                SettingsRow(
                    title: "Passphrase",
                    subtitle: "The password you set when exporting from Raycast.",
                    systemImage: "key",
                    tint: .gray
                ) {
                    SecureField("Passphrase", text: $passphrase)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                        .onSubmit(runRaycastImport)
                }
                SettingsDivider()
                SettingsRow(
                    title: "Import",
                    subtitle: "Choose what to bring over, then import.",
                    systemImage: "arrow.down.circle",
                    tint: .indigo
                ) {
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
                title: "Raycast is running — quit it to avoid hotkey conflicts.",
                systemImage: "exclamationmark.triangle.fill",
                tint: .orange
            ) {
                Button("Quit Raycast") { BackupActions.quitRaycast() }
                    .controlSize(.small)
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.lg)
        } else {
            SettingsCallout(
                title: "Tip: unset the matching Raycast shortcuts to avoid conflicts.",
                systemImage: "info.circle",
                tint: .secondary
            )
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.lg)
        }
    }

    @ViewBuilder
    private func statusRow(_ status: Status) -> some View {
        switch status {
        case .success(let message):
            SettingsRow(title: message, systemImage: "checkmark.circle.fill", tint: .green) {
                EmptyView()
            }
        case .failure(let message):
            SettingsRow(title: message, systemImage: "exclamationmark.triangle.fill", tint: .orange)
            {
                EmptyView()
            }
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
