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
                core?.runImageModification(operation)
            }
        }
        let commands = ImageOperation.allCases.map { operation in
            PluginCommandRegistration(
                id: "command:image-modification:\(operation.rawValue)", name: operation.title,
                systemImage: operation.systemImage, actionKey: .imageModification(operation)
            ) { [weak core] in core?.runImageModification(operation) }
        }
        let screen = PluginPaletteScreenRegistration(
            placeholder: "Choose a target image format…",
            snapshot: { query in conversionSnapshot(query: query) },
            performPrimaryAction: { [weak core] itemID in
                guard let format = ImageFormat(rawValue: itemID) else { return }
                core?.convertImage(to: format)
            },
            actions: { _ in nil })
        return PluginRegistration(
            metadata: PluginMetadata(
                id: .imageModification, name: "Image Modification",
                summary: "Convert, resize, filter, optimize, and edit images with macOS frameworks.",
                systemImage: "photo.badge.arrow.down", tint: .teal),
            defaultEnabled: true,
            permissions: [.automation],
            shortcutActions: actions,
            launcherCommands: commands,
            paletteScreen: screen,
            onDisable: { [weak core] in
                core?.imageModification.cancel()
                if core?.palette.mode == .plugin(.imageModification) {
                    core?.palette.prepare(mode: .launcher)
                }
            },
            settingsView: { AnyView(ImageModificationSettingsView()) })
    }

    private static func conversionSnapshot(query: String) -> PluginPaletteSnapshot {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let formats = ImageFormat.allCases.filter { format in
            trimmed.isEmpty
                || format.title.localizedCaseInsensitiveContains(trimmed)
                || format.fileExtension.localizedCaseInsensitiveContains(trimmed)
        }
        return PluginPaletteSnapshot(
            sectionTitle: "Convert To",
            items: formats.map { format in
                PluginPaletteItem(
                    id: format.rawValue,
                    title: format.title,
                    subtitle: "." + format.fileExtension,
                    icon: .symbol("photo"),
                    primaryActionTitle: "Convert to " + format.title)
            },
            emptyMessage: "No matching image formats")
    }
}

extension AppCore {
    func runImageModification(_ operation: ImageOperation) {
        guard plugins.isEnabled(.imageModification) else { return }
        if operation == .convert {
            showPalette(mode: .plugin(.imageModification))
            return
        }
        let sourceApp = previousApplication
        if palette.mode == .launcher { hidePalette() }
        imageModification.run(operation: operation, sourceApp: sourceApp)
    }

    func convertImage(to format: ImageFormat) {
        guard plugins.isEnabled(.imageModification) else { return }
        let sourceApp = previousApplication
        hidePalette()
        imageModification.convert(to: format, sourceApp: sourceApp)
    }
}
