import AppKit
import UniformTypeIdentifiers

/// User-facing entry points for the backup flows, shared between the Settings pane and the palette commands.
@MainActor
enum BackupActions {
    // MARK: - Spotter native (self-contained: own file panels + alerts)

    static func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Spotter-Settings-\(dateStamp()).json"
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                let data = try await SettingsBackup.gather().encodedOffMain()
                try await Task.detached(priority: .utility) {
                    try data.write(to: url, options: .atomic)
                }.value
            } catch {
                present(title: "Export Failed", message: error.localizedDescription, style: .warning)
            }
        }
    }

    static func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                let data = try await Task.detached(priority: .utility) { try Data(contentsOf: url) }
                    .value
                let backup = try await SettingsBackup.decodedOffMain(data)
                guard confirmSettingsImport(backup) else { return }
                present(
                    title: "Settings Imported",
                    message: summaryText(await backup.apply()), style: .informational)
            } catch {
                present(title: "Import Failed", message: error.localizedDescription, style: .warning)
            }
        }
    }

    /// The user picks the folder; Spotter owns the file name inside it. One control covers both
    /// directions because the folder's contents decide: an existing settings file there is joined,
    /// and only a folder that definitively has none gets a new one.
    static func chooseSettingsSyncFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message =
            "Choose a folder for \(SettingsSyncManager.fileName). Put it in iCloud Drive to keep "
            + "Spotter settings synchronized across Macs."
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url,
            confirmAutomaticSync()
        else { return }
        AppCore.shared.settingsSync.connect(toFolder: url)
    }

    /// Choosing the folder is the consent act, exactly as choosing one is for Settings Sync:
    /// nothing is written anywhere until the user names the place it should be written.
    static func chooseNotesFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message =
            "Choose a folder for your Notes. Put it in iCloud Drive to share them between Macs."
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        AppCore.shared.noteFolderSync.connect(to: url)
    }

    // MARK: - Helpers

    static func summaryText(_ s: SettingsBackup.ApplySummary) -> String {
        var parts: [String] = []
        if s.settingsFields > 0 { parts.append("\(s.settingsFields) settings") }
        if s.hotkeys > 0 { parts.append("\(s.hotkeys) shortcuts") }
        if s.favorites > 0 { parts.append("\(s.favorites) favorites") }
        if s.hiddenItems > 0 { parts.append("\(s.hiddenItems) hidden items") }
        if s.launcherAliases > 0 { parts.append("\(s.launcherAliases) aliases") }
        if s.customCommands > 0 { parts.append("\(s.customCommands) custom commands") }
        if s.contentCollections > 0 {
            parts.append("\(s.contentCollections) content collections")
        }
        return parts.isEmpty
            ? "Nothing to import from this file." : "Applied " + parts.joined(separator: ", ") + "."
    }

    private static func confirmSettingsImport(_ backup: SettingsBackup) -> Bool {
        let commands = backup.customCommands?.count ?? 0
        let shortcuts = backup.hotkeys?.customCommands?.count ?? 0
        let commandText = commands == 1 ? "1 custom command" : "\(commands) custom commands"
        let shortcutText =
            shortcuts == 1 ? "1 global shortcut" : "\(shortcuts) global shortcuts"
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Trust this Spotter backup?"
        alert.informativeText =
            "A backup may contain API keys, private content, and network-service consent. This one "
            + "contains \(commandText) and \(shortcutText); custom commands can run arbitrary shell "
            + "code. Only import files you trust."
        alert.alertStyle = .warning
        let importButton = alert.addButton(withTitle: "Import")
        importButton.keyEquivalent = ""
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\r"
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func confirmAutomaticSync() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Trust this settings file?"
        alert.informativeText =
            "Spotter will automatically apply future changes from this file. It may contain custom "
            + "shell commands, global shortcuts, API keys, clipboard history, AI chats and "
            + "other private data, so choose a file that only you control."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Enable Sync")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private static func present(title: String, message: String, style: NSAlert.Style) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.runModal()
    }
}
