import AppKit
import UniformTypeIdentifiers

@MainActor
enum NoteSyncActions {
    static func connectExisting() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a Spotter Notes JSON file to keep in sync."
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url,
            validateDistinct(url), confirmAutomaticSync()
        else { return }
        AppCore.shared.noteSync.connectExisting(url)
    }

    static func create() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Spotter Notes.json"
        panel.canCreateDirectories = true
        panel.message = "Save in iCloud Drive to synchronize Notes across Macs."
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url,
            validateDistinct(url), confirmAutomaticSync()
        else { return }
        AppCore.shared.noteSync.create(at: url)
    }

    private static func validateDistinct(_ url: URL) -> Bool {
        guard url.standardizedFileURL != AppCore.shared.settingsSync.fileURL?.standardizedFileURL
        else {
            present(
                title: "Choose a Different File",
                message: "Notes Sync and Settings Sync must use separate JSON files.")
            return false
        }
        return true
    }

    private static func confirmAutomaticSync() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Trust this Notes file?"
        alert.informativeText =
            "Spotter will automatically apply future changes from this file. It contains your "
            + "private note content, so choose a file that only you control."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Enable Sync")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func present(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
