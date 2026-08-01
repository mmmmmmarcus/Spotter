import SwiftUI

extension PluginActionKey {
    static func imageModification(_ operation: ImageOperation) -> PluginActionKey {
        standard(pluginID: .imageModification, actionID: operation.rawValue, title: operation.title)
    }
}

@MainActor
enum ImageModificationPlugin {
    static func registration(core: AppCore) -> PluginRegistration {
        let actions = ImageOperation.allCases.map { operation in
            PluginActionRegistration(key: .imageModification(operation)) { [weak core] in
                core?.openImageModification(operation)
            }
        }
        let commands = ImageOperation.allCases.map { operation in
            PluginCommandRegistration(
                id: "command:image-modification:\(operation.rawValue)", name: operation.title,
                systemImage: operation.systemImage, actionKey: .imageModification(operation)
            ) { [weak core] in core?.openImageModification(operation) }
        }
        return PluginRegistration(
            metadata: PluginMetadata(
                id: .imageModification, name: "Image Modification",
                summary: "Convert, resize, filter, optimize, and edit images with macOS frameworks.",
                systemImage: "photo.badge.arrow.down", tint: .teal),
            defaultEnabled: true,
            permissions: [.automation],
            shortcutActions: actions,
            launcherCommands: commands,
            onDisable: { [weak core] in core?.closePluginWindow(id: "image-modification") },
            settingsView: { AnyView(ImageModificationSettingsView()) })
    }
}

extension AppCore {
    func openImageModification(_ operation: ImageOperation) {
        guard plugins.isEnabled(.imageModification) else { return }
        let sourceApp = previousApplication
        if palette.mode == .launcher { hidePalette(restoreFocus: false) }
        imageModification.prepare(operation: operation, sourceApp: sourceApp)
        showPluginWindow(
            id: "image-modification", title: operation.title,
            size: CGSize(width: 760, height: 590)
        ) {
            ImageModificationView(manager: imageModification)
        }
    }
}
