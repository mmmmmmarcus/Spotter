import SwiftUI
import UniformTypeIdentifiers

extension View {
    /// The system folder picker. Choosing a folder is the consent to sync through it, exactly as on the Mac.
    func notesFolderPicker(isPresented: Binding<Bool>, sync: NoteFolderSyncManager) -> some View {
        fileImporter(isPresented: isPresented, allowedContentTypes: [.folder]) { result in
            if case .success(let folder) = result { sync.connect(to: folder) }
        }
    }
}

private enum SyncCopy {
    static let explanation =
        "Notes sync through a folder of Markdown files. Choose the same folder Spotter uses on your Mac — for example iCloud Drive ▸ Spotter ▸ Note."
    static let chooseFolder = "Choose Notes Folder"

    static func lostFolder(device: String) -> String {
        "The Notes folder can’t be found, so Notes are staying on \(device). Choose it again to keep syncing."
    }

    static func retained(_ count: Int) -> String {
        let files = count == 1 ? "1 deleted Note’s file is" : "\(count) deleted Notes’ files are"
        return "\(files) still in this folder, because it has no Recently Deleted to move them to. Spotter on your Mac removes them when it next syncs."
    }
}

/// What the list says about sync when there is something to say: not connected, folder lost, or an error.
struct SyncNotice: View {
    @ObservedObject var sync: NoteFolderSyncManager
    let chooseFolder: () -> Void

    var body: some View {
        if sync.isFolderUnavailable {
            notice(SyncCopy.lostFolder(device: NotesModel.device), symbol: "exclamationmark.triangle", offersFolder: true)
        } else if !sync.isEnabled {
            notice(SyncCopy.explanation, symbol: "folder.badge.plus", offersFolder: true)
        } else if let error = sync.errorMessage {
            notice(error, symbol: "exclamationmark.triangle", offersFolder: false)
        }
    }

    private func notice(_ text: String, symbol: String, offersFolder: Bool) -> some View {
        Section {
            VStack(alignment: .leading, spacing: NotesTheme.Spacing.lg) {
                Label(text, systemImage: symbol)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if offersFolder {
                    Button(SyncCopy.chooseFolder, action: chooseFolder)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(.vertical, NotesTheme.Spacing.xs)
        }
        .selectionDisabled()
    }
}

/// The connected folder, its status as the shared manager reports it, and the three things to do about it.
struct SyncSettingsView: View {
    @ObservedObject var sync: NoteFolderSyncManager

    @Environment(\.dismiss) private var dismiss
    @State private var isChoosingFolder = false
    @State private var isConfirmingDisconnect = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let folder = sync.folderURL {
                        LabeledContent("Folder") {
                            Label(folder.lastPathComponent, systemImage: sync.isICloudLocation ? "icloud" : "folder")
                        }
                    }
                    LabeledContent("Status", value: sync.statusText)
                    if sync.pendingDownloads > 0 {
                        LabeledContent("Not Downloaded Yet", value: sync.pendingDownloads.formatted())
                    }
                } footer: {
                    Text(footer)
                }
                Section {
                    if sync.isEnabled {
                        Button("Sync Now", systemImage: "arrow.triangle.2.circlepath") {
                            Task { await sync.syncNow() }
                        }
                        .disabled(sync.isWorking)
                    }
                    Button(
                        sync.isEnabled ? "Choose a Different Folder" : SyncCopy.chooseFolder,
                        systemImage: "folder"
                    ) { isChoosingFolder = true }
                    if sync.isFolderUnavailable {
                        Button("Look for the Folder Again", systemImage: "arrow.clockwise") {
                            Task { await sync.syncNow() }
                        }
                    }
                }
                if sync.isEnabled || sync.isFolderUnavailable {
                    Section {
                        Button("Disconnect", systemImage: "xmark.circle", role: .destructive) {
                            isConfirmingDisconnect = true
                        }
                    } footer: {
                        Text("Disconnecting leaves every Note on \(NotesModel.device) and every file in the folder where it is.")
                    }
                }
            }
            .navigationTitle("Sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .notesFolderPicker(isPresented: $isChoosingFolder, sync: sync)
            .alert("Disconnect the Notes Folder?", isPresented: $isConfirmingDisconnect) {
                Button("Cancel", role: .cancel) {}
                Button("Disconnect", role: .destructive) { sync.disconnect() }
            } message: {
                Text("Notes stop syncing with your other devices until you choose a folder again.")
            }
        }
    }

    private var footer: String {
        if sync.retainedDeletions > 0 { return SyncCopy.retained(sync.retainedDeletions) }
        return sync.isEnabled || sync.isFolderUnavailable ? "" : SyncCopy.explanation
    }
}
