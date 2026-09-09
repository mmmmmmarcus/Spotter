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
            placeholder: "Search",
            snapshot: { [weak core] _ in
                SelectionToolsResults.snapshot(state: core?.selectionTools.state ?? .idle)
            },
            performPrimaryAction: { _ in },
            actions: { _ in nil },
            observeChanges: { [weak core] invalidate in
                core?.selectionTools.objectWillChange.sink { invalidate() } ?? AnyCancellable {}
            })

        return PluginRegistration(
            metadata: PluginMetadata(
                // Display-renamed from Selection Tools (Sep 2026) when translation left for its own
                // plugin; the id stays `selection-tools` so enable state and bindings survive.
                id: .selectionTools,
                name: "Search",
                summary: "Search the text you have selected, in your default browser.",
                systemImage: "magnifyingglass",
                tint: .teal),
            permissions: [.accessibility],
            shortcutActions: [
                PluginActionRegistration(key: .searchSelectedText, perform: runAction)
            ],
            launcherCommands: [
                PluginCommandRegistration(
                    id: "command:selection-tools:search",
                    name: "Search Selected Text",
                    systemImage: "magnifyingglass",
                    actionKey: .searchSelectedText,
                    perform: runCommand)
            ],
            paletteScreen: screen)
    }
}

extension AppCore {
    func searchSelectedText() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            performSelectionSearch(await selectedTextCapture.capture())
        }
    }

    func searchSelectedTextFromLauncher() {
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
