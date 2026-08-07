import AppKit
import SwiftUI

extension PluginActionKey {
    /// One bindable action per command, keyed by the command's stable raw value.
    static func windowCommand(_ id: WindowCommand.ID) -> PluginActionKey {
        standard(
            pluginID: .windowManagement, actionID: id.rawValue,
            title: WindowCommandCatalog.command(id: id)?.name ?? id.rawValue)
    }
}

@MainActor
enum WindowManagementPlugin {
    static func registration(core: AppCore) -> PluginRegistration {
        PluginRegistration(
            metadata: PluginMetadata(
                id: .windowManagement,
                name: "Window Management",
                summary: "Halves, quarters, thirds, sizing and display moves for the frontmost window.",
                systemImage: "macwindow.on.rectangle",
                tint: .blue),
            defaultEnabled: true,
            permissions: [.accessibility],
            shortcutActions: WindowCommandCatalog.all.map { command in
                PluginActionRegistration(key: .windowCommand(command.id)) {
                    core.runWindowCommand(command.id)
                }
            },
            launcherCommands: WindowCommandCatalog.all.map { command in
                PluginCommandRegistration(
                    id: "command:window:" + command.id.rawValue,
                    name: command.name,
                    systemImage: command.sfSymbol,
                    actionKey: .windowCommand(command.id),
                    // 30 commands would swamp the default list; halves and the core sizing verbs stay visible, the rest are revealable in System → Shortcuts.
                    defaultVisible: Self.defaultVisibleIDs.contains(command.id)
                ) { core.runWindowCommand(command.id) }
            },
            settingsView: { AnyView(WindowManagementSettingsView()) })
    }

    /// Everything else is one search away but doesn't earn a permanent row.
    private static let defaultVisibleIDs: Set<WindowCommand.ID> = [
        .leftHalf, .rightHalf, .topHalf, .bottomHalf, .maximize, .reasonableSize, .center,
        .restore, .toggleFullscreen, .nextDisplay,
    ]
}

extension AppCore {
    /// The one funnel both the palette row and the global shortcut reach.
    func runWindowCommand(_ id: WindowCommand.ID) {
        guard plugins.isEnabled(.windowManagement) else { return }
        // The palette owns key focus by the time a command dispatches from it, so the target is the app recorded before it opened — never Spotter itself.
        let paletteVisible = isPaletteShowing
        let target = paletteVisible ? previousApplication : NSWorkspace.shared.frontmostApplication
        if paletteVisible { hidePalette(restoreFocus: true) }
        let defaults = UserDefaults.standard
        windowMover.perform(
            id, target: target,
            gap: CGFloat(defaults.integer(forKey: WindowManagementDefaults.gapKey)),
            cycleOnRepeat: defaults.bool(forKey: WindowManagementDefaults.cycleKey))
    }
}

/// Plugin-owned preference keys — kept off `AppSettings`, which mirrors `SettingsBackup` field-for-field.
enum WindowManagementDefaults {
    static let gapKey = "window-management.gap"
    static let cycleKey = "window-management.cycle-on-repeat"
}
