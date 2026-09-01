import AppKit
import Combine
import SwiftUI

extension PluginActionKey {
    static let openSnippets = standard(
        pluginID: .textReplacement, actionID: "open-snippets", title: "Search Snippets")
}

/// Snippets: named reusable text, searched and pasted from the palette. A snippet may carry an
/// expansion keyword, which is the original Text Replacement behavior — the plugin keeps its
/// historical `text-replacement` identity so enable state, shortcuts and stored data survive.
@MainActor
enum TextReplacementPlugin {
    static func registration(core: AppCore) -> PluginRegistration {
        let open: () -> Void = { [weak core] in core?.openSnippets() }
        let screen = PluginPaletteScreenRegistration(
            placeholder: "Search your snippets…",
            snapshot: { [weak core] query in
                guard let core else {
                    return PluginPaletteSnapshot(
                        sectionTitle: "Snippets", items: [], emptyMessage: "Plugin unavailable")
                }
                return snapshot(store: core.textReplacements, query: query)
            },
            performPrimaryAction: { [weak core] itemID in
                core?.performSnippetRow(itemID: itemID, paste: true)
            },
            performSecondaryAction: { [weak core] itemID in
                core?.performSnippetRow(itemID: itemID, paste: false)
            },
            actions: { [weak core] itemID in
                guard let core,
                    let snippet = core.textReplacements.snippets.first(
                        where: { $0.id.uuidString == itemID })
                else { return nil }
                return PopoverMenuContent(
                    header: snippet.name,
                    items: [
                        PopoverMenuItem(title: "Paste Snippet", systemImage: "text.insert", shortcut: "↵") {
                            core.performSnippetRow(itemID: itemID, paste: true)
                        },
                        PopoverMenuItem(title: "Copy Snippet", systemImage: "doc.on.doc", shortcut: "⌘↵") {
                            core.performSnippetRow(itemID: itemID, paste: false)
                        },
                        PopoverMenuItem(title: "Snippets Settings…", systemImage: "gearshape") {
                            core.hidePalette(restoreFocus: false)
                            core.showSettings(plugin: .textReplacement)
                        },
                    ])
            },
            observeChanges: { [weak core] invalidate in
                core?.textReplacements.objectWillChange.sink { invalidate() } ?? AnyCancellable {}
            })
        return PluginRegistration(
            metadata: PluginMetadata(
                id: .textReplacement,
                name: "Snippets",
                summary:
                    "Save named pieces of text to search and paste anywhere — and give a snippet a keyword to expand it as you type.",
                systemImage: "text.badge.plus",
                tint: .teal),
            defaultEnabled: true,
            permissions: [.accessibility],
            shortcutActions: [PluginActionRegistration(key: .openSnippets, perform: open)],
            launcherCommands: [
                PluginCommandRegistration(
                    id: "command:snippets", name: "Search Snippets",
                    systemImage: "text.badge.plus", actionKey: .openSnippets, perform: open)
            ],
            paletteScreen: screen,
            onEnable: { [weak core] in core?.textReplacementManager.start() },
            onDisable: { [weak core] in
                core?.textReplacementManager.stop()
                if core?.palette.mode == .plugin(.textReplacement) {
                    core?.palette.prepare(mode: .launcher)
                }
            },
            settingsView: {
                AnyView(
                    TextReplacementSettingsView(
                        store: core.textReplacements, manager: core.textReplacementManager))
            })
    }

    /// Rows: name over a one-line content preview, with the expansion trigger as an accessory chip.
    private static func snapshot(
        store: TextReplacementStore, query: String
    ) -> PluginPaletteSnapshot {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let visible = store.snippets
            .filter { snippet in
                trimmed.isEmpty
                    || snippet.name.localizedCaseInsensitiveContains(trimmed)
                    || snippet.content.localizedCaseInsensitiveContains(trimmed)
                    || snippet.keyword?.localizedCaseInsensitiveContains(trimmed) == true
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let items = visible.map { snippet -> PluginPaletteItem in
            var accessories: [PluginPaletteAccessory] = []
            if let keyword = snippet.keyword {
                accessories.append(
                    PluginPaletteAccessory(systemImage: "keyboard", text: store.prefix + keyword))
            }
            return PluginPaletteItem(
                id: snippet.id.uuidString,
                title: snippet.name,
                subtitle: snippet.content
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespaces),
                icon: .tintedSymbol("text.quote", tint: .teal),
                accessories: accessories,
                primaryActionTitle: "Paste Snippet")
        }
        return PluginPaletteSnapshot(
            sectionTitle: "Snippets", items: items,
            emptyMessage: store.snippets.isEmpty
                ? "No snippets yet — add one in Settings → Snippets."
                : "No matching snippet.")
    }
}

extension AppCore {
    func openSnippets() {
        guard plugins.isEnabled(.textReplacement) else { return }
        showPalette(mode: .plugin(.textReplacement))
    }

    /// A snippet row's action: paste into the previous app (↵), or copy without pasting (⌘↵).
    func performSnippetRow(itemID: String, paste: Bool) {
        guard plugins.isEnabled(.textReplacement),
            let snippet = textReplacements.snippets.first(where: { $0.id.uuidString == itemID })
        else { return }
        let previous = previousApplication
        hidePalette(restoreFocus: false)
        if paste {
            Paster.pasteString(snippet.content, previousApp: previous)
        } else {
            Paster.copyPlainText(snippet.content)
            hud.show(title: "Copied \(snippet.name)", symbol: "doc.on.doc")
        }
    }
}
