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
            placeholder: "Choose image parameters…",
            livePlaceholder: { [weak core] in
                prompt(for: core?.imageModification.parameterOperation ?? .convert)
            },
            snapshot: { [weak core] query in
                parameterSnapshot(operation: core?.imageModification.parameterOperation ?? .convert, query: query)
            },
            performPrimaryAction: { [weak core] itemID in
                guard let command = ImageCommandParser.parse(itemID), isSupported(command) else { return }
                core?.runImageCommand(command)
            },
            actions: { _ in nil })
        return PluginRegistration(
            metadata: PluginMetadata(
                id: .imageModification, name: "Image Modification",
                summary: "Convert, resize, filter, optimize, and edit images with macOS frameworks.",
                systemImage: "photo.badge.arrow.down", tint: .teal),
            permissions: [.automation],
            shortcutActions: actions,
            launcherCommands: commands,
            parameterizedCommand: { [weak core] query in
                guard let command = ImageCommandParser.parse(query), isSupported(command) else { return nil }
                return PluginCommandRegistration(
                    id: "command:image-modification:\(command.operation.rawValue)", name: command.title,
                    systemImage: command.operation.systemImage, actionKey: .imageModification(command.operation),
                    parameterIdentity: command.id
                ) { [weak core] in core?.runImageCommand(command) }
            },
            paletteScreen: screen,
            settingsView: { AnyView(ImageModificationSettingsView()) })
    }

    private static func isSupported(_ command: ImageCommand) -> Bool {
        if case .convert(let format) = command {
            return ImageModificationEngine.writableFormats.contains(format)
        }
        return true
    }

    private static func prompt(for operation: ImageOperation) -> String {
        switch operation {
        case .convert: "Convert to… e.g. JPG, PNG, TIFF"
        case .resize: "Resize to fit… e.g. 1920x1080"
        case .scale: "Scale by… e.g. 1.5 or 150%"
        case .optimize: "Quality… e.g. 80% (5–100%)"
        default: "Choose image parameters…"
        }
    }

    private static func parameterSnapshot(operation: ImageOperation, query: String) -> PluginPaletteSnapshot {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let options: [ImageCommand]
        if let command = ImageCommandParser.parseArgument(trimmed, operation: operation) {
            options = [command]
        } else if let command = ImageCommandParser.parse(trimmed), command.operation == operation {
            options = [command]
        } else {
            options = ImageCommandParser.presets(for: operation).filter {
                trimmed.isEmpty || $0.title.localizedCaseInsensitiveContains(trimmed)
                    || $0.argument.localizedCaseInsensitiveContains(trimmed)
            }
        }
        return PluginPaletteSnapshot(
            sectionTitle: operation == .convert ? "Convert To" : operation.title,
            items: options.filter(isSupported).map { command in
                PluginPaletteItem(
                    id: command.id, title: command.title,
                    subtitle: operation == .resize ? "Preserve aspect ratio" : operation == .optimize
                        ? "Lossy quality where supported; PNG is re-encoded losslessly" : nil,
                    icon: .symbol(operation.systemImage), primaryActionTitle: command.title)
            },
            emptyMessage: prompt(for: operation))
    }
}

extension AppCore {
    func runImageModification(_ operation: ImageOperation) {
        if ImageCommandParser.operations.contains(operation) {
            imageModification.parameterOperation = operation
            showPalette(mode: .plugin(.imageModification))
            return
        }
        let sourceApp = previousApplication
        if palette.mode == .launcher { hidePalette() }
        imageModification.run(operation: operation, sourceApp: sourceApp)
    }

    func runImageCommand(_ command: ImageCommand) {
        let sourceApp = previousApplication
        hidePalette()
        imageModification.run(operation: command.operation, parameter: command, sourceApp: sourceApp)
    }
}
