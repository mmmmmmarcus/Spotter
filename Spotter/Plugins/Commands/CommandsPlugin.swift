import SwiftUI

@MainActor
enum CommandsPlugin {
    static func registration(core: AppCore) -> PluginRegistration {
        PluginRegistration(
            metadata: PluginMetadata(
                id: .commands,
                name: "Commands",
                summary: "Run built-in macOS actions and your own shell commands.",
                systemImage: "terminal",
                tint: .green),
            defaultEnabled: true,
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
            dynamicLauncherCommands: { [weak core] in
                (core?.customCommands.commands ?? []).map { command in
                    PluginCommandRegistration(
                        id: command.entryID,
                        name: command.name,
                        systemImage: "terminal"
                    ) { [weak core] in core?.runCustomCommand(id: command.id) }
                }
            },
            settingsView: { AnyView(CustomCommandsSettingsView()) })
    }
}
