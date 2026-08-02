import SwiftUI

@MainActor
enum TextReplacementPlugin {
    static func registration(core: AppCore) -> PluginRegistration {
        PluginRegistration(
            metadata: PluginMetadata(
                id: .textReplacement,
                name: "Text Replacement",
                summary: "Expand short triggers into reusable text in any app.",
                systemImage: "text.badge.plus",
                tint: .teal),
            defaultEnabled: false,
            permissions: [.accessibility],
            onEnable: { [weak core] in core?.textReplacementManager.start() },
            onDisable: { [weak core] in core?.textReplacementManager.stop() },
            settingsView: {
                AnyView(
                    TextReplacementSettingsView(
                        store: core.textReplacements, manager: core.textReplacementManager))
            })
    }
}
