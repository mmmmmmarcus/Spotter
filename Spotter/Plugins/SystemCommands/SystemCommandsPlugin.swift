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
            defaultEnabled: true,
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

    static func explanation(for id: SystemCommand.ID) -> String {
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
        if command.confirmation == .required {
            confirmInPalette(
                PaletteConfirmation(
                    title: "\(command.name)?",
                    message: SystemCommandPresenter.explanation(for: command.id),
                    actionTitle: command.name
                ) { [weak self] in
                    guard let self else { return }
                    // Captured at confirm time: the app the user came from, recorded when the palette showed.
                    let target = self.previousApplication
                    self.hidePalette(restoreFocus: true)
                    self.executeSystemCommand(command, target: target)
                })
            return
        }
        // Captured before hiding: several commands act on the app the user came from.
        let target = previousApplication
        hidePalette(restoreFocus: true)
        executeSystemCommand(command, target: target)
    }

    private func executeSystemCommand(_ command: SystemCommand, target: NSRunningApplication?) {
        Task { @MainActor in
            do {
                // Only commands whose effect is invisible report back; the rest return nil.
                if let feedback = try await SystemCommandRunner.run(command.id, previousApp: target) {
                    hud.show(feedback)
                }
            } catch let failure as SystemCommandFailure {
                SystemCommandPresenter.presentFailure(name: command.name, failure: failure)
            } catch {
                SystemCommandPresenter.presentFailure(
                    name: command.name, failure: SystemCommandFailure(error.localizedDescription))
            }
        }
    }
}
