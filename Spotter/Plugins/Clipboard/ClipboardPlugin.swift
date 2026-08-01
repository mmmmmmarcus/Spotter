import SwiftUI

@MainActor
enum ClipboardPlugin {
    static func registration(core: AppCore) -> PluginRegistration {
        PluginRegistration(
            metadata: PluginMetadata(
                id: .clipboard,
                name: "Clipboard",
                summary: "Keep searchable text and image clipboard history.",
                systemImage: "doc.on.clipboard",
                tint: .orange),
            defaultEnabled: true,
            permissions: [.accessibility],
            shortcutActions: [
                PluginActionRegistration(key: .openClipboard) { [weak core] in
                    core?.toggleClipboard()
                }
            ],
            launcherCommands: [
                PluginCommandRegistration(
                    id: "command:clipboard-history",
                    name: "Clipboard History",
                    systemImage: "doc.on.clipboard",
                    actionKey: .openClipboard
                ) { [weak core] in
                    core?.toggleClipboard()
                }
            ],
            onEnable: { [weak core] in
                guard let core else { return }
                Task { core.clipboardStore.load() }
                core.clipboardManager.start()
            },
            onDisable: { [weak core] in
                guard let core else { return }
                core.clipboardManager.stop()
                if core.palette.mode == .clipboard { core.palette.prepare(mode: .launcher) }
            },
            settingsView: { AnyView(ClipboardSettingsView()) })
    }
}
