import AppKit
import SwiftUI

extension PluginActionKey {
    static let openChangeCase = standard(pluginID: .changeCase, actionID: "open", title: "Change Case")
    static func changeCase(_ kind: ChangeCaseKind) -> PluginActionKey {
        standard(pluginID: .changeCase, actionID: kind.rawValue, title: kind.title)
    }
}

@MainActor
enum ChangeCasePlugin {
    static func registration(core: AppCore) -> PluginRegistration {
        let open: () -> Void = { [weak core] in core?.openChangeCase() }
        let actions = [PluginActionRegistration(key: .openChangeCase, perform: open)]
            + ChangeCaseKind.allCases.map { kind in
                PluginActionRegistration(key: .changeCase(kind)) { [weak core] in
                    core?.runChangeCase(kind)
                }
            }
        let commands = [
            PluginCommandRegistration(
                id: "command:change-case", name: "Change Case", systemImage: "textformat",
                actionKey: .openChangeCase, perform: open)
        ] + ChangeCaseKind.allCases.map { kind in
            PluginCommandRegistration(
                id: "command:change-case:\(kind.rawValue)", name: "Change Case: \(kind.title)",
                systemImage: kind.systemImage, actionKey: .changeCase(kind), defaultVisible: false
            ) { [weak core] in core?.runChangeCase(kind) }
        }
        return PluginRegistration(
            metadata: PluginMetadata(
                id: .changeCase, name: "Change Case",
                summary: "Convert selected or copied text between 21 common letter cases.",
                systemImage: "textformat", tint: .purple),
            defaultEnabled: true,
            permissions: [.accessibility],
            shortcutActions: actions,
            launcherCommands: commands,
            onDisable: { [weak core] in core?.closePluginWindow(id: "change-case") },
            settingsView: { AnyView(ChangeCaseSettingsView(store: core.changeCase)) })
    }
}

extension AppCore {
    func openChangeCase() {
        guard plugins.isEnabled(.changeCase) else { return }
        let sourceApp = previousApplication
        if palette.mode == .launcher { hidePalette(restoreFocus: false) }
        changeCase.loadInput(from: sourceApp)
        showPluginWindow(id: "change-case", title: "Change Case", size: CGSize(width: 720, height: 560)) {
            ChangeCaseView(store: changeCase, targetApp: sourceApp)
        }
    }

    func runChangeCase(_ kind: ChangeCaseKind) {
        guard plugins.isEnabled(.changeCase), changeCase.isEnabled(kind) else { return }
        let target = previousApplication
        changeCase.loadInput(from: target)
        let output = changeCase.output(for: kind)
        guard !output.isEmpty else { return }
        changeCase.record(kind)
        if palette.mode == .launcher { hidePalette(restoreFocus: false) }
        let primary = ChangeCasePrimaryAction(rawValue: UserDefaults.standard.string(forKey: "change-case.primary-action") ?? "paste") ?? .paste
        if primary == .paste { Paster.pasteString(output, previousApp: target) }
        else { Paster.copyPlainText(output) }
    }
}
