import AppKit
import Combine
import SwiftUI

extension PluginActionKey {
    static let openQuicklinks = standard(
        pluginID: .quicklinks, actionID: "search", title: "Search Quicklinks")
    static let createQuicklink = standard(
        pluginID: .quicklinks, actionID: "create", title: "Create Quicklink")
}

@MainActor
enum QuicklinksPlugin {
    static func registration(core: AppCore) -> PluginRegistration {
        let screen = PluginPaletteScreenRegistration(
            placeholder: "Search your quicklinks…",
            livePlaceholder: { [weak core] in core?.quicklinkManager.placeholder },
            snapshot: { [weak core] query in
                guard let core else {
                    return PluginPaletteSnapshot(
                        sectionTitle: "Quicklinks", items: [], emptyMessage: "Plugin unavailable")
                }
                return QuicklinkResults.snapshot(manager: core.quicklinkManager, query: query)
            },
            performPrimaryAction: { [weak core] itemID in
                core?.performQuicklinkRow(itemID: itemID)
            },
            actions: { [weak core] itemID in
                guard let core else { return nil }
                return QuicklinkResults.menu(core: core, itemID: itemID)
            },
            // Closing the screen abandons a half-filled run; reopening always starts at the list.
            onClose: { [weak core] in core?.quicklinkManager.showList() },
            observeChanges: { [weak core] invalidate in
                guard let core else { return AnyCancellable {} }
                return Publishers.Merge(
                    core.quicklinks.objectWillChange, core.quicklinkManager.objectWillChange
                )
                .sink { invalidate() }
            })

        return PluginRegistration(
            metadata: PluginMetadata(
                id: .quicklinks,
                name: "Quicklinks",
                summary:
                    "Save links, files and deep links as launcher entries, with {argument} placeholders you fill as you go.",
                systemImage: "link",
                tint: .blue),
            defaultEnabled: true,
            shortcutActions: [
                PluginActionRegistration(key: .openQuicklinks) { core.openQuicklinks() },
                PluginActionRegistration(key: .createQuicklink) { core.createQuicklink() },
            ],
            launcherCommands: [
                PluginCommandRegistration(
                    id: "command:quicklinks:search", name: "Search Quicklinks",
                    systemImage: "link", actionKey: .openQuicklinks
                ) { core.openQuicklinks() },
                PluginCommandRegistration(
                    id: "command:quicklinks:create", name: "Create Quicklink",
                    systemImage: "link.badge.plus", actionKey: .createQuicklink
                ) { core.createQuicklink() },
            ],
            // A saved quicklink is launcher data, so the entry list is re-read rather than fixed at registration.
            dynamicLauncherCommands: { [weak core] in
                guard let core else { return [] }
                return core.quicklinks.sorted.map { quicklink in
                    PluginCommandRegistration(
                        id: QuicklinkResults.commandID(quicklink),
                        name: quicklink.name,
                        systemImage: "link",
                        iconFilePath: QuicklinkManager.openerBundlePath(for: quicklink)
                    ) { core.runQuicklink(id: quicklink.id) }
                }
            },
            paletteScreen: screen,
            onDisable: { [weak core] in
                if core?.palette.mode == .plugin(.quicklinks) {
                    core?.palette.prepare(mode: .launcher)
                }
            },
            settingsView: {
                AnyView(
                    QuicklinksSettingsView(store: core.quicklinks, appIndex: core.appIndex))
            })
    }
}

@MainActor
enum QuicklinkResults {
    static func commandID(_ quicklink: Quicklink) -> String { quicklink.entryID }

    static func snapshot(manager: QuicklinkManager, query: String) -> PluginPaletteSnapshot {
        switch manager.screen {
        case .list: return list(manager: manager, query: query)
        case .arguments: return arguments(manager: manager, query: query)
        }
    }

    private static func list(manager: QuicklinkManager, query: String) -> PluginPaletteSnapshot {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = manager.store.sorted.filter {
            trimmed.isEmpty || $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.link.localizedCaseInsensitiveContains(trimmed)
        }
        let items = matches.map { quicklink -> PluginPaletteItem in
            let count = QuicklinkTemplate.arguments(in: quicklink.link).count
            var accessories: [PluginPaletteAccessory] = []
            if quicklink.isPinned {
                accessories.append(.init(systemImage: "pin.fill", text: "Pinned"))
            }
            if count > 0 {
                accessories.append(
                    .init(
                        systemImage: "text.cursor",
                        text: count == 1 ? "1 argument" : "\(count) arguments"))
            }
            return PluginPaletteItem(
                id: "link:" + quicklink.id.uuidString.lowercased(),
                title: quicklink.name,
                subtitle: quicklink.link,
                icon: QuicklinkManager.openerBundlePath(for: quicklink)
                    .map(PluginPaletteIcon.file(path:)) ?? .symbol("link"),
                accessories: accessories,
                primaryActionTitle: count > 0 ? "Fill Arguments" : "Open")
        }
        return PluginPaletteSnapshot(
            sectionTitle: "Quicklinks", items: items,
            emptyMessage: manager.store.quicklinks.isEmpty
                ? "No quicklinks yet — add one in Settings → Quicklinks."
                : "No matching quicklink")
    }

    private static func arguments(manager: QuicklinkManager, query: String)
        -> PluginPaletteSnapshot
    {
        guard let run = manager.pending, let argument = run.current else {
            return PluginPaletteSnapshot(
                sectionTitle: "Quicklinks", items: [], emptyMessage: "Opening…")
        }
        let section = "\(run.quicklink.name) · \(argument.name)"
        guard argument.options.isEmpty else {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let items = argument.options.enumerated()
                .filter { trimmed.isEmpty || $0.element.localizedCaseInsensitiveContains(trimmed) }
                .map { index, option in
                    PluginPaletteItem(
                        id: "option:\(index)",
                        title: option,
                        subtitle: preview(run: run, value: option),
                        icon: .symbol("chevron.right.circle"),
                        primaryActionTitle: run.values.count == run.arguments.count - 1
                            ? "Open" : "Next")
                }
            return PluginPaletteSnapshot(
                sectionTitle: section, items: items, emptyMessage: "No matching option")
        }

        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return PluginPaletteSnapshot(
                sectionTitle: section, items: [],
                emptyMessage: "Type a value for \(argument.name), then press ↵")
        }
        let isLast = run.values.count == run.arguments.count - 1
        return PluginPaletteSnapshot(
            sectionTitle: section,
            items: [
                PluginPaletteItem(
                    id: "value",
                    title: value,
                    subtitle: preview(run: run, value: value),
                    icon: .symbol("text.cursor"),
                    primaryActionTitle: isLast ? "Open" : "Next")
            ],
            emptyMessage: "Type a value for \(argument.name)")
    }

    /// Shows what the link resolves to with this value applied; tokens still to come stay visible.
    private static func preview(run: QuicklinkManager.PendingRun, value: String) -> String {
        let destination = QuicklinkDestination.detect(run.quicklink.link)
        let filled = run.values + [value]
        var result = run.quicklink.link
        for (offset, token) in QuicklinkTemplate.arguments(in: result).enumerated().reversed()
        where offset < filled.count {
            result.replaceSubrange(
                token.range,
                with: destination.encodesValues
                    ? QuicklinkTemplate.percentEncoded(filled[offset]) : filled[offset])
        }
        return result
    }

    static func menu(core: AppCore, itemID: String) -> PopoverMenuContent? {
        let manager = core.quicklinkManager
        guard manager.screen == .list, let quicklink = quicklink(core: core, itemID: itemID) else {
            guard manager.screen == .arguments else { return nil }
            return PopoverMenuContent(
                header: "Quicklinks",
                items: [
                    PopoverMenuItem(title: "Back", systemImage: "arrow.uturn.backward") {
                        core.stepBackQuicklinkArgument()
                    }
                ])
        }
        return PopoverMenuContent(
            header: quicklink.name,
            items: [
                PopoverMenuItem(title: "Open", systemImage: "arrow.up.forward.app") {
                    core.runQuicklink(id: quicklink.id)
                },
                PopoverMenuItem(title: "Copy Link", systemImage: "doc.on.doc") {
                    core.hidePalette(restoreFocus: false)
                    Paster.copyPlainText(quicklink.link)
                },
                PopoverMenuItem(
                    title: quicklink.isPinned ? "Unpin" : "Pin",
                    systemImage: quicklink.isPinned ? "pin.slash" : "pin"
                ) { core.quicklinks.togglePinned(id: quicklink.id) },
                PopoverMenuItem(title: "Edit in Settings…", systemImage: "pencil") {
                    core.hidePalette(restoreFocus: false)
                    core.showSettings(plugin: .quicklinks)
                },
                PopoverMenuItem(title: "Delete", systemImage: "trash", isDestructive: true) {
                    core.confirmDeleteQuicklink(quicklink)
                },
            ])
    }

    static func quicklink(core: AppCore, itemID: String) -> Quicklink? {
        guard itemID.hasPrefix("link:"),
            let id = UUID(uuidString: String(itemID.dropFirst("link:".count)))
        else { return nil }
        return core.quicklinks.quicklink(id: id)
    }
}

extension AppCore {
    func openQuicklinks() {
        guard plugins.isEnabled(.quicklinks) else { return }
        quicklinkManager.showList()
        palette.prepare(mode: .plugin(.quicklinks))
        showPalette(mode: .plugin(.quicklinks))
    }

    func createQuicklink() {
        guard plugins.isEnabled(.quicklinks) else { return }
        hidePalette(restoreFocus: false)
        showSettings(plugin: .quicklinks)
    }

    func runQuicklink(id: UUID) {
        guard plugins.isEnabled(.quicklinks), let quicklink = quicklinks.quicklink(id: id) else {
            return
        }
        switch quicklinkManager.begin(quicklink) {
        case .opened:
            hidePalette(restoreFocus: false)
        case .awaitingArguments:
            // Arguments still to collect: stay on the plugin screen with a fresh prompt.
            showPalette(mode: .plugin(.quicklinks))
        case .failed:
            reportQuicklinkFailure(quicklink)
        }
    }

    func performQuicklinkRow(itemID: String) {
        guard plugins.isEnabled(.quicklinks) else { return }
        switch quicklinkManager.screen {
        case .list:
            guard let quicklink = QuicklinkResults.quicklink(core: self, itemID: itemID) else {
                return
            }
            runQuicklink(id: quicklink.id)
        case .arguments:
            guard let value = submittedValue(itemID: itemID) else { return }
            let quicklink = quicklinkManager.pending?.quicklink
            switch quicklinkManager.submit(value) {
            case .opened:
                hidePalette(restoreFocus: false)
            case .awaitingArguments:
                break
            case .failed:
                if let quicklink { reportQuicklinkFailure(quicklink) }
            }
        }
    }

    func confirmDeleteQuicklink(_ quicklink: Quicklink) {
        confirmInPalette(
            PaletteConfirmation(
                title: "Delete \(quicklink.name)?",
                message: "This quicklink and its launcher entry will be permanently deleted.",
                actionTitle: "Delete"
            ) { [weak self] in
                guard let self else { return }
                // Same trailing state a deleted custom command drops: its binding, alias and rankings.
                let action = HotKeyAction.quicklink(id: quicklink.id)
                if hotKeys.recordingAction == action { hotKeys.recordingAction = nil }
                hotKeys.setShortcut(nil, for: action)
                favorites.remove(keys: [quicklink.entryID])
                visibility.removeItemKeys([quicklink.entryID])
                aliases.removeKeys([quicklink.entryID])
                launcherRanking.reset(itemKey: quicklink.entryID)
                quicklinks.delete(id: quicklink.id)
            })
    }

    private func reportQuicklinkFailure(_ quicklink: Quicklink) {
        AppLog.error("quicklinks", "Could not open quicklink “\(quicklink.name)”.")
        hud.show(
            title: "Couldn’t Open \(quicklink.name)",
            symbol: "exclamationmark.triangle", isNoOp: true)
    }

    func stepBackQuicklinkArgument() {
        quicklinkManager.stepBack()
    }

    private func submittedValue(itemID: String) -> String? {
        if itemID == "value" {
            let typed = palette.query.trimmingCharacters(in: .whitespacesAndNewlines)
            return typed.isEmpty ? nil : typed
        }
        guard itemID.hasPrefix("option:"),
            let index = Int(itemID.dropFirst("option:".count)),
            let options = quicklinkManager.pending?.current?.options,
            options.indices.contains(index)
        else { return nil }
        return options[index]
    }
}
