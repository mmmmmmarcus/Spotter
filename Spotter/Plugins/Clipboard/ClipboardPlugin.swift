import SwiftUI
import Carbon.HIToolbox

extension PluginActionKey {
    static let quickClipboard = standard(pluginID: .clipboard, actionID: "quick-history",
        title: "Quick Clipboard History")
}

@MainActor
enum ClipboardPlugin {
    static let quickHistoryShortcut = KeyShortcut(carbonKeyCode: Int(kVK_ANSI_Z), carbonModifiers: controlKey | cmdKey)

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
                },
                PluginActionRegistration(key: .quickClipboard, defaultShortcut: quickHistoryShortcut) { [weak core] in
                    core?.toggleQuickClipboard()
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
                },
                PluginCommandRegistration(
                    id: "command:quick-clipboard-history",
                    name: "Quick Clipboard History",
                    systemImage: "doc.on.clipboard",
                    actionKey: .quickClipboard
                ) { [weak core] in
                    core?.toggleQuickClipboard()
                }
            ],
            onStart: { [weak core] in
                guard let core else { return }
                ClipboardShortcutMigration.apply(defaults: .standard,
                    legacyKey: PluginActionKey.openClipboard.defaultsKey,
                    quickKey: PluginActionKey.quickClipboard.defaultsKey,
                    legacyUsesDefault: core.hotKeys.shortcut(for: .plugin(.openClipboard)) == quickHistoryShortcut)
                Task { core.clipboardStore.load() }
                core.clipboardManager.start()
            },
            settingsView: { AnyView(ClipboardSettingsView()) })
    }
}
