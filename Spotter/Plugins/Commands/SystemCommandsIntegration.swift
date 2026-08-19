import AppKit
import SwiftUI

/// Confirmation and failure UI for built-ins. Kept inside Commands rather than `AppCore`, so the destructive-command gate lives with the commands it guards.
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
        guard plugins.isEnabled(.commands),
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
                    if self.isPaletteShowing { self.hidePalette(restoreFocus: true) }
                    self.executeSystemCommand(command, target: target)
                })
            return
        }
        // Captured before hiding: several commands act on the app the user came from.
        let target = previousApplication
        if isPaletteShowing { hidePalette(restoreFocus: true) }
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
                AppLog.error("system-commands", "\(command.name) failed: \(failure.message)")
                SystemCommandPresenter.presentFailure(name: command.name, failure: failure)
            } catch {
                AppLog.error(
                    "system-commands", "\(command.name) failed: \(error.localizedDescription)")
                SystemCommandPresenter.presentFailure(
                    name: command.name, failure: SystemCommandFailure(error.localizedDescription))
            }
        }
    }
}
