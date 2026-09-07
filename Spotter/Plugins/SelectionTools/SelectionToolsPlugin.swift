import AppKit
import Combine
import SwiftUI

extension PluginActionKey {
    static let searchSelectedText = standard(
        pluginID: .selectionTools, actionID: "search", title: "Search Selected Text")
    static let translateSelectedText = PluginActionKey(
        pluginID: .selectionTools, actionID: "translate", title: "Translate Selected Text",
        defaultsKey: "KeyboardShortcuts_plugin.selection-tools.translate")
    static let translateText = standard(
        pluginID: .selectionTools, actionID: "translate-text", title: "Translate Text")
}

@MainActor
enum SelectionToolsPlugin {
    static func registration(core: AppCore) -> PluginRegistration {
        let runAction: () -> Void = { [weak core] in core?.searchSelectedText() }
        let runCommand: () -> Void = { [weak core] in core?.searchSelectedTextFromLauncher() }
        let translateAction: () -> Void = { [weak core] in core?.translateSelectedText() }
        let translateCommand: () -> Void = { [weak core] in
            core?.translateSelectedTextFromLauncher()
        }
        let openTranslate: () -> Void = { [weak core] in core?.openTranslateText() }
        let screen = PluginPaletteScreenRegistration(
            placeholder: "Selection Tools",
            livePlaceholder: { [weak core] in
                guard let manager = core?.selectionTools else { return nil }
                switch (manager.screen, manager.state) {
                case (.compose, .loading): return "Translating…"
                // The page's search field is the text itself, so its prompt has to say so.
                case (.compose, _): return "Type text to translate, then press ↵…"
                case (.selection, .loading): return "Translating selected text…"
                case (.selection, .translated): return "Filter translation rows…"
                default: return nil
                }
            },
            snapshot: { [weak core] query in
                guard let manager = core?.selectionTools else {
                    return SelectionToolsResults.snapshot(screen: .selection, state: .idle)
                }
                return SelectionToolsResults.snapshot(
                    screen: manager.screen, state: manager.state, query: query,
                    targets: manager.targets, hasAPIKey: manager.isTranslationReady)
            },
            performPrimaryAction: { [weak core] itemID in
                if itemID == SelectionTranslationRowID.translate {
                    core?.translateTypedText()
                } else {
                    core?.copySelectionToolsResult(itemID: itemID)
                }
            },
            actions: { _ in nil },
            observeChanges: { [weak core] invalidate in
                core?.selectionTools.objectWillChange.sink { invalidate() }
                    ?? AnyCancellable {}
            })

        return PluginRegistration(
            metadata: PluginMetadata(
                id: .selectionTools,
                name: "Selection Tools",
                summary: "Search selected text or translate it into the languages you choose.",
                systemImage: "selection.pin.in.out",
                tint: .teal),
            defaultEnabled: true,
            permissions: [.accessibility],
            shortcutActions: [
                PluginActionRegistration(key: .searchSelectedText, perform: runAction),
                PluginActionRegistration(key: .translateSelectedText, perform: translateAction),
                PluginActionRegistration(key: .translateText, perform: openTranslate),
            ],
            launcherCommands: [
                PluginCommandRegistration(
                    id: "command:selection-tools:search",
                    name: "Search Selected Text",
                    systemImage: "magnifyingglass",
                    actionKey: .searchSelectedText,
                    perform: runCommand),
                PluginCommandRegistration(
                    id: "command:selection-tools:translate",
                    name: "Translate Selected Text",
                    systemImage: "translate",
                    actionKey: .translateSelectedText,
                    perform: translateCommand),
                PluginCommandRegistration(
                    id: "command:selection-tools:translate-text",
                    name: "Translate Text",
                    systemImage: "character.bubble",
                    actionKey: .translateText,
                    perform: openTranslate),
            ],
            paletteScreen: screen,
            onDisable: { [weak core] in
                core?.selectionTools.prepare(screen: .selection)
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
            selectionTools.prepare(screen: .selection)
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
        selectionTools.prepare(screen: .selection)
        selectionTools.showFailure(message)
        palette.prepare(mode: .plugin(.selectionTools))
        showPalette(mode: .plugin(.selectionTools))
    }

    func translateSelectedText() {
        guard plugins.isEnabled(.selectionTools) else { return }
        guard selectionTools.isTranslationReady else {
            showSelectionTranslationFailure(
                GoogleTranslationError.missingAPIKey.localizedDescription)
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            performSelectionTranslation(await selectedTextCapture.capture())
        }
    }

    func translateSelectedTextFromLauncher() {
        guard plugins.isEnabled(.selectionTools) else { return }
        guard selectionTools.isTranslationReady else {
            showSelectionTranslationFailure(
                GoogleTranslationError.missingAPIKey.localizedDescription)
            return
        }
        guard palette.mode == .launcher else {
            translateSelectedText()
            return
        }
        hidePalette()
        Task { @MainActor [weak self] in
            guard let self else { return }
            performSelectionTranslation(await selectedTextCapture.captureAfterRestoringFocus())
        }
    }

    private func performSelectionTranslation(
        _ capture: Result<SelectedTextSnapshot, SelectedTextCaptureFailure>
    ) {
        guard plugins.isEnabled(.selectionTools), selectionTools.isTranslationReady else { return }
        selectionTools.prepare(screen: .selection)
        switch capture {
        case .failure(let error):
            selectionTools.showFailure(error.message)
        case .success(let snapshot):
            selectionTools.translate(snapshot.text)
        }
        palette.prepare(mode: .plugin(.selectionTools))
        showPalette(mode: .plugin(.selectionTools))
    }

    private func showSelectionTranslationFailure(_ message: String) {
        selectionTools.prepare(screen: .selection)
        selectionTools.showFailure(message)
        palette.prepare(mode: .plugin(.selectionTools))
        showPalette(mode: .plugin(.selectionTools))
    }

    /// Opens the Translate page. It is enterable with no key and no text: the page says what is
    /// missing rather than refusing to open, exactly as the selection screen does.
    func openTranslateText() {
        guard plugins.isEnabled(.selectionTools) else { return }
        selectionTools.prepare(screen: .compose)
        palette.prepare(mode: .plugin(.selectionTools))
        showPalette(mode: .plugin(.selectionTools))
    }

    /// The Translate page's one trigger: ↵ on its action row. Nothing typed ever reaches Google on
    /// its own, so no keystroke can spend a billable request.
    func translateTypedText() {
        guard plugins.isEnabled(.selectionTools), selectionTools.screen == .compose else { return }
        selectionTools.translate(palette.query.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func copySelectionToolsResult(itemID: String) {
        guard let text = selectionTools.text(for: itemID) else { return }
        hidePalette(restoreFocus: false)
        Paster.copyPlainText(text)
    }
}
