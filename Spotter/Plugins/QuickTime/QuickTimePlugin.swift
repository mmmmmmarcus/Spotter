import AppKit
import SwiftUI

extension PluginActionKey {
    static func quickTime(_ kind: QuickTimeRecordingKind) -> PluginActionKey {
        standard(pluginID: .quickTimeRecording, actionID: kind.rawValue, title: kind.title)
    }
}

@MainActor
enum QuickTimePlugin {
    static func registration(core: AppCore) -> PluginRegistration {
        let actions = QuickTimeRecordingKind.allCases.map { kind in
            PluginActionRegistration(key: .quickTime(kind)) { [weak core] in
                core?.startQuickTimeRecording(kind)
            }
        }
        let commands = QuickTimeRecordingKind.allCases.map { kind in
            PluginCommandRegistration(
                id: "command:quicktime:\(kind.rawValue)", name: kind.title,
                systemImage: kind.systemImage, actionKey: .quickTime(kind)
            ) { [weak core] in core?.startQuickTimeRecording(kind) }
        }
        return PluginRegistration(
            metadata: PluginMetadata(
                id: .quickTimeRecording, name: "QuickTime Recording",
                summary: "Start screen, audio, or camera recording in QuickTime Player.",
                systemImage: "record.circle", tint: .red),
            defaultEnabled: true,
            permissions: [.automation],
            shortcutActions: actions,
            launcherCommands: commands,
            settingsView: { AnyView(QuickTimeSettingsView()) })
    }
}

extension AppCore {
    func startQuickTimeRecording(_ kind: QuickTimeRecordingKind) {
        guard plugins.isEnabled(.quickTimeRecording) else { return }
        if palette.mode == .launcher { hidePalette(restoreFocus: false) }
        Task {
            do { try await QuickTimeRunner.run(kind) }
            catch {
                NSApp.activate(ignoringOtherApps: true)
                let alert = NSAlert()
                alert.messageText = "Couldn’t Start \(kind.title)"
                alert.informativeText = (error as? QuickTimeRunError)?.message ?? error.localizedDescription
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.addButton(withTitle: "Automation Settings…")
                if alert.runModal() == .alertSecondButtonReturn { Permissions.openAutomationSettings() }
            }
        }
    }
}
