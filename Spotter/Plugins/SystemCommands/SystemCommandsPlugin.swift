import AppKit
import SwiftUI

extension PluginActionKey {
    static func systemCommand(_ id: SystemCommand.ID) -> PluginActionKey {
        standard(
            pluginID: .systemCommands, actionID: id.rawValue,
            title: SystemCommandCatalog.all.first { $0.id == id }?.name ?? id.rawValue)
    }
}

@MainActor
enum SystemCommandsPlugin {
    static func registration(core: AppCore) -> PluginRegistration {
        PluginRegistration(
            metadata: PluginMetadata(
                id: .systemCommands,
                name: "System Commands",
                summary: "macOS actions in the launcher: lock, sleep, volume, Bluetooth, trash and more.",
                systemImage: "switch.2",
                tint: .teal),
            defaultEnabled: false,
            // Media keys and Dismiss Notifications drive the Accessibility API; the AppleScript commands prompt for Automation on first use.
            permissions: [.accessibility, .automation],
            shortcutActions: SystemCommandCatalog.all.map { command in
                PluginActionRegistration(key: .systemCommand(command.id)) {
                    core.runSystemCommand(command.id)
                }
            },
            launcherCommands: SystemCommandCatalog.all.map { command in
                PluginCommandRegistration(
                    id: command.entryID,
                    name: command.name,
                    systemImage: command.sfSymbol,
                    actionKey: .systemCommand(command.id)
                ) { core.runSystemCommand(command.id) }
            },
            settingsView: { AnyView(SystemCommandsSettingsView()) })
    }
}

/// Confirmation and failure UI for system commands. Kept beside the plugin rather than in `AppCore`, so the destructive-command gate lives with the commands it guards.
@MainActor
enum SystemCommandPresenter {
    /// Guards only the dialog, not execution — a held shortcut must not stack alerts.
    private static var isConfirming = false

    /// Return is bound to **Cancel**: a destructive command is one ↵ away in the palette, and a reflexive second ↵ must not restart the Mac.
    static func confirm(_ command: SystemCommand) -> Bool {
        guard !isConfirming else { return false }
        isConfirming = true
        defer { isConfirming = false }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "\(command.name)?"
        alert.informativeText = Self.explanation(for: command.id)
        alert.alertStyle = .warning
        let run = alert.addButton(withTitle: command.name)
        run.keyEquivalent = ""
        let cancel = alert.addButton(withTitle: "Cancel")
        cancel.keyEquivalent = "\r"
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func presentFailure(name: String, failure: SystemCommandFailure) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "\(name) failed"
        alert.informativeText = failure.message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        // An Automation denial is fixable, so offer the pane rather than just reporting it.
        switch failure.settings {
        case .automation:
            alert.addButton(withTitle: "Open Automation Settings…")
            if alert.runModal() == .alertSecondButtonReturn { Permissions.openAutomationSettings() }
        case .accessibility:
            alert.addButton(withTitle: "Open Accessibility Settings…")
            if alert.runModal() == .alertSecondButtonReturn { Permissions.openAccessibilitySettings() }
        case .bluetooth, .none:
            alert.runModal()
        }
    }

    private static func explanation(for id: SystemCommand.ID) -> String {
        switch id {
        case .restart: "Your Mac will restart. Apps will be asked to save first."
        case .shutDown: "Your Mac will shut down. Apps will be asked to save first."
        case .logOut: "You'll be logged out. Apps will be asked to save first."
        case .emptyTrash: "Everything in the Trash will be deleted permanently."
        case .quitAllApps: "Every open app will be asked to quit."
        default: "This action can't be undone."
        }
    }
}

extension AppCore {
    /// The one funnel both palette activation and the global shortcut reach, so no path can skip the confirmation.
    func runSystemCommand(_ id: SystemCommand.ID) {
        guard plugins.isEnabled(.systemCommands),
            let command = SystemCommandCatalog.all.first(where: { $0.id == id })
        else { return }
        // Captured before hiding: several commands act on the app the user came from.
        let target = previousApplication
        // The palette is a floating panel and would sit above the alert, so it goes first either way.
        hidePalette(restoreFocus: true)
        if command.confirmation == .required {
            guard SystemCommandPresenter.confirm(command) else { return }
        }
        Task { @MainActor in
            do {
                try await SystemCommandRunner.run(id, previousApp: target)
            } catch let failure as SystemCommandFailure {
                SystemCommandPresenter.presentFailure(name: command.name, failure: failure)
            } catch {
                SystemCommandPresenter.presentFailure(
                    name: command.name, failure: SystemCommandFailure(error.localizedDescription))
            }
        }
    }
}
