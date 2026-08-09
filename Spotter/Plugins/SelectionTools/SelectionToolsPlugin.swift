import AppKit
import Combine
import SwiftUI

extension PluginActionKey {
    static let searchSelectedText = standard(
        pluginID: .selectionTools, actionID: "search", title: "Search Selected Text")
}

@MainActor
enum SelectionToolsPlugin {
    static func registration(core: AppCore) -> PluginRegistration {
        let runAction: () -> Void = { [weak core] in core?.searchSelectedText() }
        let runCommand: () -> Void = { [weak core] in core?.searchSelectedTextFromLauncher() }
        let screen = PluginPaletteScreenRegistration(
            placeholder: "Selection Tools",
            snapshot: { [weak core] _ in
                SelectionToolsResults.snapshot(state: core?.selectionTools.state ?? .idle)
            },
            performPrimaryAction: { _ in },
            actions: { _ in nil },
            observeChanges: { [weak core] invalidate in
                core?.selectionTools.objectWillChange.sink { invalidate() }
                    ?? AnyCancellable {}
            })

        return PluginRegistration(
            metadata: PluginMetadata(
                id: .selectionTools,
                name: "Selection Tools",
                summary: "Search selected text in your default browser.",
                systemImage: "selection.pin.in.out",
                tint: .teal),
            defaultEnabled: true,
            permissions: [.accessibility],
            shortcutActions: [PluginActionRegistration(key: .searchSelectedText, perform: runAction)],
            launcherCommands: [
                PluginCommandRegistration(
                    id: "command:selection-tools:search",
                    name: "Search Selected Text",
                    systemImage: "magnifyingglass",
                    actionKey: .searchSelectedText,
                    perform: runCommand)
            ],
            paletteScreen: screen,
            onDisable: { [weak core] in
                core?.selectionTools.reset()
                if core?.palette.mode == .plugin(.selectionTools) {
                    core?.palette.prepare(mode: .launcher)
                }
            },
            settingsView: { AnyView(SelectionToolsSettingsView()) })
    }
}

extension AppCore {
    func searchSelectedText() {
        guard plugins.isEnabled(.selectionTools) else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            performSelectionSearch(await selectedTextCapture.capture())
        }
    }

    func searchSelectedTextFromLauncher() {
        guard plugins.isEnabled(.selectionTools) else { return }
        guard palette.mode == .launcher else {
            searchSelectedText()
            return
        }
        hidePalette()
        Task { @MainActor [weak self] in
            guard let self else { return }
            performSelectionSearch(await selectedTextCapture.captureAfterRestoringFocus())
        }
    }

    private func performSelectionSearch(
        _ capture: Result<SelectedTextSnapshot, SelectedTextCaptureFailure>
    ) {
        guard plugins.isEnabled(.selectionTools) else { return }
        switch capture {
        case .failure(let error):
            showSelectionSearchFailure(error.message)
        case .success(let snapshot):
            selectionTools.reset()
            guard let url = SearchURLBuilder.googleSearchURL(for: snapshot.text) else {
                showSelectionSearchFailure(
                    "Spotter could not build a Google Search URL for the selected text.")
                return
            }
            guard NSWorkspace.shared.open(url) else {
                showSelectionSearchFailure(
                    "The default browser could not open the Google Search URL.")
                return
            }
        }
    }

    private func showSelectionSearchFailure(_ message: String) {
        selectionTools.showFailure(message)
        palette.prepare(mode: .plugin(.selectionTools))
        showPalette(mode: .plugin(.selectionTools))
    }
}
