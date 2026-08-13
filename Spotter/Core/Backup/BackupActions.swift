import AppKit
import UniformTypeIdentifiers

/// User-facing entry points for the backup flows, shared between the Settings pane and the palette commands. The Raycast decrypt runs off the main actor (scrypt is CPU-heavy); everything else is quick.
@MainActor
enum BackupActions {
    struct RaycastOutcome {
        var summary: SettingsBackup.ApplySummary
        var clipboardImported: Int
        var missingImages: Int
    }

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

    static func connectSettingsSyncFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a Spotter settings JSON file to keep in sync."
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url, validateDistinctFromNotes(url),
            confirmAutomaticSync()
        else { return }
        AppCore.shared.settingsSync.connectExisting(url)
    }

    static func createSettingsSyncFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Spotter Settings.json"
        panel.canCreateDirectories = true
        panel.message = "Save in iCloud Drive to keep Spotter settings synchronized across Macs."
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url, validateDistinctFromNotes(url),
            confirmAutomaticSync()
        else { return }
        AppCore.shared.settingsSync.create(at: url)
    }

    // MARK: - Raycast (the pane owns the passphrase field + inline status)

    static func importRaycast(file: URL, passphrase: String, options: RaycastImportOptions = .all)
        async throws -> RaycastOutcome
    {
        // Decrypt (scrypt/AES/gunzip) AND parse off the main actor, inside an autoreleasepool so the large JSON tree drains at once instead of spiking the main-thread footprint. Only the value-type Result crosses back.
        let result = try await Task.detached(priority: .userInitiated) {
            try autoreleasepool {
                let decrypted = try RaycastImport.decrypt(file: file, passphrase: passphrase)
                return try RaycastImport.parse(decrypted).selecting(options)
            }
        }.value
        let summary = await result.backup.apply()
        let imported =
            result.clipboard.isEmpty
            ? 0 : AppCore.shared.clipboardStore.importEntries(result.clipboard)
        return RaycastOutcome(
            summary: summary, clipboardImported: imported, missingImages: result.missingImages)
    }

    /// Every Raycast channel (stable, beta, alpha, internal) shares this bundle-id prefix.
    static let raycastBundleIDPrefix = "com.raycast"

    static func isRaycastBundleID(_ id: String) -> Bool { id.hasPrefix(raycastBundleIDPrefix) }

    /// Quit any running Raycast app so its hotkeys stop clashing; skip `.prohibited` (pure background helpers/XPC).
    static func quitRaycast() {
        for app in NSWorkspace.shared.runningApplications
        where app.bundleIdentifier.map(isRaycastBundleID) == true
            && app.activationPolicy != .prohibited
        {
            app.terminate()
        }
    }

    /// Shared `.rayconfig` file picker used by the Backup pane and onboarding.
    static func pickRaycastFile() -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }

    // MARK: - Helpers

    static func summaryText(_ s: SettingsBackup.ApplySummary) -> String {
        var parts: [String] = []
        if s.settingsFields > 0 { parts.append("\(s.settingsFields) settings") }
        if s.hotkeys > 0 { parts.append("\(s.hotkeys) shortcuts") }
        if s.favorites > 0 { parts.append("\(s.favorites) favorites") }
        if s.hiddenItems > 0 { parts.append("\(s.hiddenItems) hidden items") }
        if s.customCommands > 0 { parts.append("\(s.customCommands) custom commands") }
        if s.plugins > 0 { parts.append("\(s.plugins) plugins") }
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

    private static func validateDistinctFromNotes(_ url: URL) -> Bool {
        guard url.standardizedFileURL != AppCore.shared.noteSync.fileURL?.standardizedFileURL else {
            present(
                title: "Choose a Different File",
                message: "Settings Sync and Notes Sync must use separate JSON files.",
                style: .warning)
            return false
        }
        return true
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
