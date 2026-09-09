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
            onStart: { [weak core] in
                guard let core else { return }
                Task { core.clipboardStore.load() }
                core.clipboardManager.start()
            },
            settingsView: { AnyView(ClipboardSettingsView()) })
    }
}
