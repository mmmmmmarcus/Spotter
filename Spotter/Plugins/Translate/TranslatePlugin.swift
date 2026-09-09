import Combine
import SwiftUI

extension PluginActionKey {
    // The legacy defaults keys are kept verbatim: the plugin ID changed, an existing binding must not.
    static let translateSelectedText = PluginActionKey(
        pluginID: .translate, actionID: "translate", title: "Translate Selected Text",
        defaultsKey: "KeyboardShortcuts_plugin.selection-tools.translate")
    static let translateText = PluginActionKey(
        pluginID: .translate, actionID: "translate-text", title: "Translate",
        defaultsKey: "KeyboardShortcuts_plugin.selection-tools.translate-text")
}

@MainActor
enum TranslatePlugin {
    static func registration(core: AppCore) -> PluginRegistration {
        let translateAction: () -> Void = { [weak core] in core?.translateSelectedText() }
        let translateCommand: () -> Void = { [weak core] in
            core?.translateSelectedTextFromLauncher()
        }
        let openTranslate: () -> Void = { [weak core] in core?.openTranslate() }
        let screen = PluginPaletteScreenRegistration(
            placeholder: "Translate",
            livePlaceholder: { [weak core] in
                guard let manager = core?.translate else { return nil }
                switch (manager.screen, manager.state) {
                case (.compose, .loading): return "Translating…"
                // The page's search field is the text itself, so its prompt has to say so.
                case (.compose, _): return "Type text to translate…"
                case (.selection, .loading): return "Translating selected text…"
                case (.selection, .translated): return "Filter translation rows…"
                default: return nil
                }
            },
            snapshot: { [weak core] query in
                guard let manager = core?.translate else {
                    return TranslateResults.snapshot(screen: .selection, state: .idle)
                }
                return TranslateResults.snapshot(
                    screen: manager.screen, state: manager.state, query: query,
                    targets: manager.targets, hasAPIKey: manager.isTranslationReady)
            },
            performPrimaryAction: { [weak core] itemID in
                if itemID == TranslateRowID.retry {
                    core?.retryTypedTranslation()
                } else {
                    core?.copyTranslationResult(itemID: itemID)
                }
            },
            actions: { _ in nil },
            // Live translation listens only while the screen is on stage; closing it stops the
            // pause timer and abandons whatever was in flight.
            onOpen: { [weak core] in
                guard let core else { return }
                core.translate.startObservingQuery(core.palette.$query)
            },
            onClose: { [weak core] in core?.translate.stopObservingQuery() },
            observeChanges: { [weak core] invalidate in
                core?.translate.objectWillChange.sink { invalidate() } ?? AnyCancellable {}
            })

        return PluginRegistration(
            metadata: PluginMetadata(
                id: .translate,
                name: "Translate",
                summary: "Translate typed or selected text into the languages you choose.",
                systemImage: "translate",
                tint: .teal),
            permissions: [.accessibility],
            shortcutActions: [
                PluginActionRegistration(key: .translateSelectedText, perform: translateAction),
                PluginActionRegistration(key: .translateText, perform: openTranslate),
            ],
            launcherCommands: [
                // The command IDs predate the split; they key ranking, favorites and visibility.
                PluginCommandRegistration(
                    id: "command:selection-tools:translate-text",
                    name: "Translate",
                    systemImage: "translate",
                    actionKey: .translateText,
                    perform: openTranslate),
                PluginCommandRegistration(
                    id: "command:selection-tools:translate",
                    name: "Translate Selected Text",
                    systemImage: "character.bubble",
                    actionKey: .translateSelectedText,
                    perform: translateCommand),
            ],
            paletteScreen: screen,
            settingsView: { AnyView(TranslateSettingsView()) })
    }
}

extension AppCore {
    func translateSelectedText() {
        guard translate.isTranslationReady else {
            showTranslationFailure(GoogleTranslationError.missingAPIKey.localizedDescription)
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            performSelectionTranslation(await selectedTextCapture.capture())
        }
    }

    func translateSelectedTextFromLauncher() {
        guard translate.isTranslationReady else {
            showTranslationFailure(GoogleTranslationError.missingAPIKey.localizedDescription)
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
        guard translate.isTranslationReady else { return }
        translate.prepare(screen: .selection)
        switch capture {
        case .failure(let error):
            translate.showFailure(error.message)
        case .success(let snapshot):
            translate.translate(snapshot.text)
        }
        palette.prepare(mode: .plugin(.translate))
        showPalette(mode: .plugin(.translate))
    }

    private func showTranslationFailure(_ message: String) {
        translate.prepare(screen: .selection)
        translate.showFailure(message)
        palette.prepare(mode: .plugin(.translate))
        showPalette(mode: .plugin(.translate))
    }

    /// Opens the Translate page. It is enterable with no key and no text: the page says what is
    /// missing rather than refusing to open, exactly as the selection screen does.
    func openTranslate() {
        translate.prepare(screen: .compose)
        palette.prepare(mode: .plugin(.translate))
        showPalette(mode: .plugin(.translate))
    }

    /// The retry row a failure leaves behind — the one request the page asks the user to spend.
    func retryTypedTranslation() {
        guard translate.screen == .compose else { return }
        translate.retry(palette.query)
    }

    func copyTranslationResult(itemID: String) {
        guard let text = translate.text(for: itemID) else { return }
        hidePalette(restoreFocus: false)
        Paster.copyPlainText(text)
    }
}
