import SwiftUI

extension PluginActionKey {
    static let openKillProcess = standard(
        pluginID: .killProcess, actionID: "open", title: "Kill Process")
}

@MainActor
enum KillProcessPlugin {
    static func registration(core: AppCore) -> PluginRegistration {
        let open: () -> Void = { [weak core] in core?.openKillProcess() }
        return PluginRegistration(
            metadata: PluginMetadata(
                id: .killProcess,
                name: "Kill Process",
                summary: "Inspect, terminate, force-terminate, and restart running processes.",
                systemImage: "xmark.octagon",
                tint: .red),
            defaultEnabled: true,
            shortcutActions: [PluginActionRegistration(key: .openKillProcess, perform: open)],
            launcherCommands: [
                PluginCommandRegistration(
                    id: "command:kill-process", name: "Kill Process",
                    systemImage: "xmark.octagon", actionKey: .openKillProcess, perform: open)
            ],
            onDisable: { [weak core] in
                core?.killProcess.stop()
                core?.closePluginWindow(id: "kill-process")
            },
            settingsView: { AnyView(KillProcessSettingsView()) })
    }
}

extension AppCore {
    func openKillProcess() {
        guard plugins.isEnabled(.killProcess) else { return }
        if palette.mode == .launcher { hidePalette(restoreFocus: false) }
        showPluginWindow(
            id: "kill-process", title: "Kill Process", size: CGSize(width: 780, height: 560)
        ) {
            KillProcessView(manager: killProcess)
        }
        Task { await killProcess.refresh() }
    }
}
