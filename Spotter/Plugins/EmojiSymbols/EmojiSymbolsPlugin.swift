import SwiftUI

@MainActor
enum EmojiSymbolsPlugin {
    static func registration(core: AppCore) -> PluginRegistration {
        PluginRegistration(
            metadata: PluginMetadata(
                id: .emoji,
                name: "Emoji & Symbols",
                summary: "Search and paste emoji and symbols into any app.",
                systemImage: "face.smiling",
                tint: .yellow),
            defaultEnabled: true,
            permissions: [.accessibility],
            shortcutActions: [
                PluginActionRegistration(key: .openEmoji) { [weak core] in
                    core?.toggleEmoji()
                }
            ],
            launcherCommands: [
                PluginCommandRegistration(
                    id: "command:search-emoji",
                    name: "Search Emoji & Symbols",
                    systemImage: "face.smiling",
                    actionKey: .openEmoji
                ) { [weak core] in
                    core?.toggleEmoji()
                }
            ],
            onEnable: { [weak core] in
                guard let core else { return }
                Task { await core.emojiIndex.load() }
            },
            onDisable: { [weak core] in
                guard let core else { return }
                if core.palette.mode == .emoji { core.palette.prepare(mode: .launcher) }
            },
            settingsView: { AnyView(EmojiSettingsView()) })
    }
}
