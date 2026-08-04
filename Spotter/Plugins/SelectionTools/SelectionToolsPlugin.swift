import AppKit
import Combine
import SwiftUI

extension PluginActionKey {
    static let searchSelectedText = standard(
        pluginID: .selectionTools, actionID: "search", title: "Search Selected Text")
    static let translateSelectedText = standard(
        pluginID: .selectionTools, actionID: "translate", title: "Translate Selected Text")
    static let checkSelectedTextGrammar = standard(
        pluginID: .selectionTools, actionID: "grammar", title: "Check Selected Text Grammar")
}

@MainActor
enum SelectionToolsPlugin {
    static func registration(core: AppCore) -> PluginRegistration {
        let runAction: (SelectionToolAction) -> Void = { [weak core] action in
            core?.runSelectionTool(action)
        }
        let runCommand: (SelectionToolAction) -> Void = { [weak core] action in
            core?.runSelectionToolFromLauncher(action)
        }
        let screen = PluginPaletteScreenRegistration(
            placeholder: "Filter Selection Tools results…",
            snapshot: { [weak core] query in
                guard let core else {
                    return PluginPaletteSnapshot(
                        sectionTitle: "Selection Tools", items: [],
                        emptyMessage: "Plugin unavailable")
                }
                return SelectionToolsResults.snapshot(
                    state: core.selectionTools.state, query: query)
            },
            performPrimaryAction: { [weak core] itemID in
                core?.copySelectionToolsResult(itemID: itemID)
            },
            actions: { [weak core] itemID in
                guard let core,
                    SelectionToolsResults.copyText(
                        state: core.selectionTools.state, itemID: itemID) != nil
                else { return nil }
                var items = [
                    PopoverMenuItem(
                        title: copyTitle(state: core.selectionTools.state, itemID: itemID),
                        systemImage: "doc.on.doc", shortcut: "↵"
                    ) { core.copySelectionToolsResult(itemID: itemID) }
                ]
                if itemID != "original", core.selectionTools.originalText != nil {
                    items.append(
                        PopoverMenuItem(title: "Copy Original", systemImage: "doc.on.doc") {
                            core.copySelectionToolsResult(itemID: "original")
                        })
                }
                return PopoverMenuContent(header: "Selection Tools", items: items)
            },
            observeChanges: { [weak core] invalidate in
                core?.selectionTools.objectWillChange.sink { invalidate() }
                    ?? AnyCancellable {}
            })

        return PluginRegistration(
            metadata: PluginMetadata(
                id: .selectionTools,
                name: "Selection Tools",
                summary: "Search, translate, and check grammar for text selected in another app.",
                systemImage: "selection.pin.in.out",
                tint: .teal),
            defaultEnabled: true,
            permissions: [.accessibility],
            shortcutActions: [
                PluginActionRegistration(key: .searchSelectedText) { runAction(.search) },
                PluginActionRegistration(key: .translateSelectedText) { runAction(.translate) },
                PluginActionRegistration(key: .checkSelectedTextGrammar) { runAction(.grammar) },
            ],
            launcherCommands: [
                PluginCommandRegistration(
                    id: "command:selection-tools:search",
                    name: "Search Selected Text",
                    systemImage: "magnifyingglass",
                    actionKey: .searchSelectedText
                ) { runCommand(.search) },
                PluginCommandRegistration(
                    id: "command:selection-tools:translate",
                    name: "Translate Selected Text",
                    systemImage: "translate",
                    actionKey: .translateSelectedText
                ) { runCommand(.translate) },
                PluginCommandRegistration(
                    id: "command:selection-tools:grammar",
                    name: "Check Selected Text Grammar",
                    systemImage: "text.badge.checkmark",
                    actionKey: .checkSelectedTextGrammar
                ) { runCommand(.grammar) },
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

    private static func copyTitle(
        state: SelectionToolsState, itemID: String
    ) -> String {
        if itemID == "original" { return "Copy Original" }
        return switch state {
        case .translated: "Copy Translation"
        case .grammarChecked: "Copy Corrected Text"
        case .idle, .loading, .failed: "Copy Result"
        }
    }
}

extension AppCore {
    func runSelectionTool(_ action: SelectionToolAction) {
        guard plugins.isEnabled(.selectionTools) else { return }
        // The frontmost-app snapshot happens synchronously inside captureSelection, before its first await; the palette only shows after capture completes.
        Task { @MainActor [weak self] in
            guard let self else { return }
            let capture = await selectionTools.captureSelection()
            performSelectionTool(action, capture: capture)
        }
    }

    func runSelectionToolFromLauncher(_ action: SelectionToolAction) {
        guard plugins.isEnabled(.selectionTools) else { return }
        guard palette.mode == .launcher else {
            runSelectionTool(action)
            return
        }

        // The Launcher has key focus by command activation time. Hide it to restore the source app, then recapture from NSWorkspace; previousApplication is used only by the existing focus-restoration path, never as selection data.
        hidePalette()
        Task { @MainActor [weak self] in
            guard let self else { return }
            let capture = await captureSelectionAfterRestoringFocus()
            performSelectionTool(action, capture: capture)
        }
    }

    private func performSelectionTool(
        _ action: SelectionToolAction,
        capture: Result<SelectedTextSnapshot, SelectionToolsFailure>
    ) {
        guard plugins.isEnabled(.selectionTools) else { return }
        switch capture {
        case .failure(let error):
            selectionTools.showFailure(action: action, error: error)
            showSelectionToolsPalette()
        case .success(let snapshot):
            if action == .search {
                selectionTools.reset()
                guard let url = SearchURLBuilder.googleSearchURL(for: snapshot.text) else {
                    selectionTools.showFailure(action: action, error: .invalidSearchURL)
                    showSelectionToolsPalette()
                    return
                }
                guard NSWorkspace.shared.open(url) else {
                    selectionTools.showFailure(action: action, error: .browserOpenFailed)
                    showSelectionToolsPalette()
                    return
                }
                return
            }
            selectionTools.start(action: action, snapshot: snapshot)
            showSelectionToolsPalette()
        }
    }

    private func captureSelectionAfterRestoringFocus()
        async -> Result<SelectedTextSnapshot, SelectionToolsFailure>
    {
        var lastResult: Result<SelectedTextSnapshot, SelectionToolsFailure> =
            .failure(.noFrontmostApplication)
        for attempt in 0..<6 {
            await Task.yield()
            lastResult = await selectionTools.captureSelection()
            guard case .failure(let error) = lastResult, error.isTransientFocusFailure,
                attempt < 5
            else { return lastResult }
            try? await Task.sleep(for: .milliseconds(40))
        }
        return lastResult
    }

    func copySelectionToolsResult(itemID: String) {
        guard plugins.isEnabled(.selectionTools),
            let text = SelectionToolsResults.copyText(
                state: selectionTools.state, itemID: itemID)
        else { return }
        hidePalette(restoreFocus: false)
        Paster.copyPlainText(text)
    }

    private func showSelectionToolsPalette() {
        palette.prepare(mode: .plugin(.selectionTools))
        showPalette(mode: .plugin(.selectionTools))
    }
}

private extension SelectionToolsFailure {
    // Only pre-capture focus states retry here; the control/selection failures already exhausted the reader's own retries and the ⌘C fallback, so repeating them would triple the wait for the same answer.
    var isTransientFocusFailure: Bool {
        switch self {
        case .noFrontmostApplication, .spotterIsFrontmost:
            true
        case .accessibilityDenied, .focusedControlUnavailable, .selectedTextUnavailable,
            .emptySelection, .invalidSearchURL, .browserOpenFailed,
            .sourceLanguageUnknown, .translationLanguagesNotInstalled, .translationUnavailable,
            .grammarUnavailable, .llmRequestFailed, .cancelled:
            false
        }
    }
}
