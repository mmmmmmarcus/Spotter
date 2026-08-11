import AppKit
import Combine
import SwiftUI

extension PluginActionKey {
    static let openMoleMenu = standard(pluginID: .mole, actionID: "menu", title: "Mole")
    static let openMoleStatus = standard(
        pluginID: .mole, actionID: "status", title: "Mole System Status")
    static let openMoleHistory = standard(
        pluginID: .mole, actionID: "history", title: "Mole Cleanup History")
    static let openMoleClean = standard(pluginID: .mole, actionID: "clean", title: "Mole Clean")
    static let openMoleOptimize = standard(
        pluginID: .mole, actionID: "optimize", title: "Mole Optimize")
    static let openMolePurge = standard(pluginID: .mole, actionID: "purge", title: "Mole Purge")
    static let openMoleUninstall = standard(
        pluginID: .mole, actionID: "uninstall", title: "Mole Uninstall App")
    static let openMoleAnalyze = standard(
        pluginID: .mole, actionID: "analyze", title: "Mole Analyze Disk")
    static let openMoleInstaller = standard(
        pluginID: .mole, actionID: "installer", title: "Mole Remove Installers")
}

@MainActor
enum MolePlugin {
    static func registration(core: AppCore) -> PluginRegistration {
        let screen = PluginPaletteScreenRegistration(
            placeholder: "Choose a Mole command…",
            livePlaceholder: { [weak core] in core?.mole.screen.placeholder },
            snapshot: { [weak core] query in
                guard let core else {
                    return PluginPaletteSnapshot(
                        sectionTitle: "Mole", items: [], emptyMessage: "Plugin unavailable")
                }
                return MoleResults.snapshot(manager: core.mole, query: query)
            },
            performPrimaryAction: { [weak core] itemID in
                core?.performMoleRow(itemID: itemID)
            },
            actions: { [weak core] itemID in
                guard let core else { return nil }
                return MoleResults.menu(core: core, itemID: itemID)
            },
            onClose: { [weak core] in core?.mole.stop() },
            observeChanges: { [weak core] invalidate in
                core?.mole.objectWillChange.sink { invalidate() } ?? AnyCancellable {}
            })

        return PluginRegistration(
            metadata: PluginMetadata(
                id: .mole,
                name: "Mole",
                summary:
                    "Drive the Mole CLI from the launcher: health, cleanup, optimize, purge, uninstall and disk analysis, all rendered in the palette.",
                systemImage: "chart.pie",
                tint: .green),
            defaultEnabled: true,
            shortcutActions: [
                PluginActionRegistration(key: .openMoleMenu) { core.openMole(.menu) },
                PluginActionRegistration(key: .openMoleStatus) { core.openMole(.status) },
                PluginActionRegistration(key: .openMoleHistory) { core.openMole(.history) },
                PluginActionRegistration(key: .openMoleClean) { core.openMole(.clean) },
                PluginActionRegistration(key: .openMoleOptimize) { core.openMole(.optimize) },
                PluginActionRegistration(key: .openMolePurge) { core.openMole(.purge) },
                PluginActionRegistration(key: .openMoleUninstall) { core.openMole(.uninstall) },
                PluginActionRegistration(key: .openMoleAnalyze) { core.openMole(.analyze) },
                PluginActionRegistration(key: .openMoleInstaller) { core.openMole(.installer) },
            ],
            launcherCommands: MoleCommand.allCases.map { command in
                PluginCommandRegistration(
                    id: command.commandID,
                    name: command.title,
                    systemImage: command.systemImage,
                    actionKey: command.shortcutKey
                ) { core.runMole(command) }
            },
            paletteScreen: screen,
            onDisable: { [weak core] in
                core?.mole.stop()
                if core?.palette.mode == .plugin(.mole) {
                    core?.palette.prepare(mode: .launcher)
                }
            },
            settingsView: { AnyView(MoleSettingsView()) })
    }
}

extension MoleCommand {
    var shortcutKey: PluginActionKey {
        switch self {
        case .menu: .openMoleMenu
        case .status: .openMoleStatus
        case .history: .openMoleHistory
        case .clean: .openMoleClean
        case .optimize: .openMoleOptimize
        case .purge: .openMolePurge
        case .uninstall: .openMoleUninstall
        case .analyze: .openMoleAnalyze
        case .installer: .openMoleInstaller
        }
    }
}

/// Turns manager state into palette rows. Pure mapping — no I/O — so the screen stays a snapshot.
@MainActor
enum MoleResults {
    static func snapshot(manager: MoleManager, query: String) -> PluginPaletteSnapshot {
        let section = manager.screen.sectionTitle
        if manager.screen == .menu {
            return PluginPaletteSnapshot(
                sectionTitle: section, items: filtered(menuItems(), query: query),
                emptyMessage: "No matching command")
        }
        switch manager.state {
        case .idle:
            return PluginPaletteSnapshot(
                sectionTitle: section, items: [], emptyMessage: "Loading Mole…")
        case .loading:
            return PluginPaletteSnapshot(
                sectionTitle: section, items: [], isLoading: true,
                loadingMessage: loadingMessage(manager: manager), emptyMessage: "Asking Mole…")
        case .failed(let message):
            return PluginPaletteSnapshot(
                sectionTitle: section, items: [], errorMessage: message, emptyMessage: message)
        case .status(let status):
            return PluginPaletteSnapshot(
                sectionTitle: section, items: filtered(statusItems(status), query: query),
                emptyMessage: "No matching status rows")
        case .history(let entries):
            guard !entries.isEmpty else {
                return PluginPaletteSnapshot(
                    sectionTitle: section, items: [],
                    emptyMessage: "No cleanup history yet — run Mole Clean to create some.")
            }
            return PluginPaletteSnapshot(
                sectionTitle: section, items: filtered(historyItems(entries), query: query),
                emptyMessage: "No matching history")
        case .report(let report):
            return PluginPaletteSnapshot(
                sectionTitle: section,
                items: runRow(manager: manager)
                    + filtered(reportItems(report), query: query),
                emptyMessage: report.isEmpty
                    ? "Nothing to do — Mole found no reclaimable items." : "No matching item")
        case .purge(let entries):
            return PluginPaletteSnapshot(
                sectionTitle: section,
                items: runRow(manager: manager) + filtered(purgeItems(entries), query: query),
                emptyMessage: entries.isEmpty
                    ? "No build artifacts found in your project folders." : "No matching directory")
        case .apps(let apps):
            return PluginPaletteSnapshot(
                sectionTitle: section, items: filtered(appItems(apps), query: query),
                emptyMessage: "No matching app")
        case .analysis(let analysis):
            return PluginPaletteSnapshot(
                sectionTitle: "Mole · " + shortPath(analysis.path),
                items: ascendRow(manager: manager)
                    + filtered(diskItems(analysis), query: query),
                emptyMessage: "This folder is empty")
        case .installers(let entries):
            return PluginPaletteSnapshot(
                sectionTitle: section,
                items: installerProgressRow(manager: manager, count: entries.count)
                    + filtered(installerItems(entries), query: query),
                isLoading: manager.isLoadingPreview,
                loadingMessage: loadingMessage(manager: manager),
                emptyMessage: entries.isEmpty
                    ? "No installer files found — Downloads and friends are clean."
                    : "No matching installer")
        }
    }

    // MARK: - Rows

    private static func menuItems() -> [PluginPaletteItem] {
        MoleCommand.hubCommands.map { command in
            PluginPaletteItem(
                id: "menu:" + command.rawValue,
                title: command.title.replacingOccurrences(of: "Mole ", with: ""),
                subtitle: command.summary,
                icon: .symbol(command.systemImage),
                primaryActionTitle: "Open")
        }
    }

    private static func statusItems(_ status: MoleStatus) -> [PluginPaletteItem] {
        var items = [
            PluginPaletteItem(
                id: "health",
                title: "Health Score \(status.healthScore)",
                subtitle: status.healthMessage,
                icon: .symbol("heart.text.square"),
                accessories: [.init(systemImage: "gauge", text: "\(status.healthScore)/100")],
                primaryActionTitle: "Copy Value")
        ]
        items += status.rows.map { row in
            PluginPaletteItem(
                id: "row:" + row.title,
                title: row.title,
                subtitle: row.detail.isEmpty ? nil : row.detail,
                icon: .symbol("circle.fill"),
                accessories: [.init(systemImage: "number", text: row.value)],
                primaryActionTitle: "Copy Value")
        }
        return items
    }

    private static func historyItems(_ entries: [MoleHistoryEntry]) -> [PluginPaletteItem] {
        entries.enumerated().map { index, entry in
            PluginPaletteItem(
                id: "history:\(index)",
                title: "\(entry.command.capitalized) · \(entry.size)",
                subtitle: "\(entry.startedAt) · \(entry.items) items"
                    + (entry.failedTasks > 0 ? " · \(entry.failedTasks) failed" : ""),
                icon: .symbol("clock.arrow.circlepath"),
                primaryActionTitle: "Copy Summary")
        }
    }

    private static func reportItems(_ report: MoleReport) -> [PluginPaletteItem] {
        report.items.enumerated().map { index, item in
            PluginPaletteItem(
                id: "item:\(index)",
                title: item.title,
                subtitle: item.section.isEmpty ? nil : item.section,
                icon: .symbol("circle.dashed"),
                accessories: item.detail.isEmpty
                    ? [] : [.init(systemImage: "externaldrive", text: item.detail)],
                primaryActionTitle: "Copy Line")
        }
    }

    private static func purgeItems(_ entries: [MolePurgeEntry]) -> [PluginPaletteItem] {
        entries.enumerated().map { index, entry in
            PluginPaletteItem(
                id: "purge:\(index)",
                title: (entry.path as NSString).lastPathComponent,
                subtitle: entry.path,
                icon: .symbol("hammer"),
                accessories: [.init(systemImage: "externaldrive", text: entry.size)],
                primaryActionTitle: "Reveal in Finder")
        }
    }

    private static func appItems(_ apps: [MoleApp]) -> [PluginPaletteItem] {
        apps.enumerated().map { index, app in
            PluginPaletteItem(
                id: "app:\(index)",
                title: app.name,
                subtitle: app.path,
                icon: app.path.isEmpty ? .symbol("app") : .file(path: app.path),
                accessories: app.size.isEmpty
                    ? [] : [.init(systemImage: "externaldrive", text: app.size)],
                primaryActionTitle: "Move to Trash")
        }
    }

    private static func installerItems(_ entries: [MoleInstallerEntry]) -> [PluginPaletteItem] {
        entries.enumerated().map { index, entry in
            PluginPaletteItem(
                id: "installer:\(index)",
                title: entry.name,
                subtitle: entry.folder,
                icon: .file(path: entry.path),
                accessories: [
                    .init(systemImage: "externaldrive", text: MoleParser.bytes(entry.size))
                ],
                primaryActionTitle: "Move to Trash")
        }
    }

    private static func installerProgressRow(manager: MoleManager, count: Int)
        -> [PluginPaletteItem]
    {
        guard manager.isLoadingPreview else { return [] }
        let path = manager.installerScanPath ?? NSHomeDirectory()
        let folder = (path as NSString).lastPathComponent
        return [
            PluginPaletteItem(
                id: "installer-progress",
                title: "Scanning \(folder)…",
                subtitle: "Found \(count) installer \(count == 1 ? "file" : "files") so far · "
                    + shortPath(path),
                icon: .symbol("hourglass"),
                primaryActionTitle: "Scanning…")
        ]
    }

    private static func diskItems(_ analysis: MoleAnalysis) -> [PluginPaletteItem] {
        analysis.entries.enumerated().map { index, entry in
            PluginPaletteItem(
                id: "entry:\(index)",
                title: entry.name,
                subtitle: entry.isDirectory ? "Folder" : "File",
                icon: .symbol(entry.isDirectory ? "folder" : "doc"),
                accessories: [
                    .init(systemImage: "externaldrive", text: MoleParser.bytes(entry.size))
                ],
                primaryActionTitle: entry.isDirectory ? "Open" : "Reveal in Finder")
        }
    }

    /// The one row that turns a preview into an action, pinned above the list it describes.
    private static func runRow(manager: MoleManager) -> [PluginPaletteItem] {
        guard let action = pendingAction(for: manager.screen) else { return [] }
        if manager.isLoadingPreview {
            let count: Int
            if case .report(let report) = manager.state {
                count = report.items.count
            } else {
                count = 0
            }
            return [
                PluginPaletteItem(
                    id: "run",
                    title: "Still scanning caches…",
                    subtitle: count == 0 ? "Mole is building the preview."
                        : "Found \(count) reclaimable \(count == 1 ? "item" : "items") so far.",
                    icon: .symbol("hourglass"),
                    primaryActionTitle: "Scanning…")
            ]
        }
        let running = manager.runningAction != nil
        let summary = manager.lastRunSummary.joined(separator: " · ")
        return [
            PluginPaletteItem(
                id: "run",
                title: running ? "Running \(action.title)…" : action.title,
                subtitle: summary.isEmpty
                    ? "Runs the command for real — Spotter asks first." : summary,
                icon: .symbol(running ? "hourglass" : "play.circle.fill"),
                subtitleLineLimit: 2,
                primaryActionTitle: running ? "Running…" : "Run")
        ]
    }

    private static func ascendRow(manager: MoleManager) -> [PluginPaletteItem] {
        guard manager.canAscend else { return [] }
        return [
            PluginPaletteItem(
                id: "up",
                title: "Back",
                subtitle: shortPath((manager.analyzePath as NSString).deletingLastPathComponent),
                icon: .symbol("arrow.uturn.backward"),
                primaryActionTitle: "Go Up")
        ]
    }

    static func pendingAction(for screen: MoleScreen) -> MoleAction? {
        switch screen {
        case .clean: .clean
        case .optimize: .optimize
        case .purge: .purge
        default: nil
        }
    }

    private static func loadingMessage(manager: MoleManager) -> String {
        switch manager.screen {
        case .installer: "Scanning for installer files…"
        case .clean: "Scanning caches…"
        case .optimize: "Checking system services…"
        case .purge: "Scanning project folders…"
        case .uninstall: "Listing installed apps…"
        case .analyze: "Measuring \(shortPath(manager.analyzePath))…"
        default: "Asking Mole…"
        }
    }

    static func shortPath(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    // MARK: - Actions menu

    static func menu(core: AppCore, itemID: String) -> PopoverMenuContent? {
        let manager = core.mole
        var items: [PopoverMenuItem] = []

        if let installer = installerEntry(manager: manager, itemID: itemID) {
            items.append(
                PopoverMenuItem(title: "Move to Trash", systemImage: "trash", isDestructive: true) {
                    core.trashMoleInstaller(installer)
                })
        }
        if let app = app(manager: manager, itemID: itemID) {
            items.append(
                PopoverMenuItem(title: "Move to Trash", systemImage: "trash") {
                    core.runMoleAction(.uninstall(name: app.uninstallName, permanent: false))
                })
            items.append(
                PopoverMenuItem(
                    title: "Delete Permanently", systemImage: "trash.slash", isDestructive: true
                ) { core.runMoleAction(.uninstall(name: app.uninstallName, permanent: true)) })
            items.append(
                PopoverMenuItem(title: "Reveal in Finder", systemImage: "folder") {
                    core.revealInFinder(path: app.path)
                })
            items.append(
                PopoverMenuItem(title: "Copy Bundle ID", systemImage: "doc.on.doc") {
                    core.hidePalette(restoreFocus: false)
                    Paster.copyPlainText(app.bundleID)
                })
        } else if let path = revealablePath(manager: manager, itemID: itemID) {
            items.append(
                PopoverMenuItem(title: "Reveal in Finder", systemImage: "folder") {
                    core.revealInFinder(path: path)
                })
            items.append(
                PopoverMenuItem(title: "Copy Path", systemImage: "doc.on.doc") {
                    core.hidePalette(restoreFocus: false)
                    Paster.copyPlainText(path)
                })
        }

        if let action = pendingAction(for: manager.screen), !manager.isRunning,
            !manager.isLoadingPreview
        {
            items.append(
                PopoverMenuItem(
                    title: action.title, systemImage: "play.circle",
                    isDestructive: action.isPermanent
                ) { core.runMoleAction(action) })
        }

        items.append(
            PopoverMenuItem(title: "Refresh", systemImage: "arrow.clockwise", shortcut: "⌘R") {
                manager.reload()
            })
        if manager.screen != .menu {
            items.append(
                PopoverMenuItem(title: "All Mole Commands", systemImage: "circle.grid.2x2") {
                    core.openMole(.menu)
                })
        }
        items.append(
            PopoverMenuItem(title: "Mole Settings…", systemImage: "gearshape") {
                core.hidePalette(restoreFocus: false)
                core.showSettings(plugin: .mole)
            })
        return PopoverMenuContent(header: "Mole", items: items)
    }

    // MARK: - Item lookup

    static func app(manager: MoleManager, itemID: String) -> MoleApp? {
        guard case .apps(let apps) = manager.state, itemID.hasPrefix("app:"),
            let index = Int(itemID.dropFirst("app:".count)), apps.indices.contains(index)
        else { return nil }
        return apps[index]
    }

    static func installerEntry(manager: MoleManager, itemID: String) -> MoleInstallerEntry? {
        guard case .installers(let entries) = manager.state, itemID.hasPrefix("installer:"),
            let index = Int(itemID.dropFirst("installer:".count)), entries.indices.contains(index)
        else { return nil }
        return entries[index]
    }

    static func diskEntry(manager: MoleManager, itemID: String) -> MoleDiskEntry? {
        guard case .analysis(let analysis) = manager.state, itemID.hasPrefix("entry:"),
            let index = Int(itemID.dropFirst("entry:".count)),
            analysis.entries.indices.contains(index)
        else { return nil }
        return analysis.entries[index]
    }

    /// Rows that point at something on disk, so the same menu entries work across the screens.
    static func revealablePath(manager: MoleManager, itemID: String) -> String? {
        if let entry = diskEntry(manager: manager, itemID: itemID) { return entry.path }
        if let entry = installerEntry(manager: manager, itemID: itemID) { return entry.path }
        guard case .purge(let entries) = manager.state, itemID.hasPrefix("purge:"),
            let index = Int(itemID.dropFirst("purge:".count)), entries.indices.contains(index)
        else { return nil }
        return (entries[index].path as NSString).expandingTildeInPath
    }

    static func copyText(manager: MoleManager, itemID: String) -> String? {
        switch manager.state {
        case .status(let status):
            if itemID == "health" { return "\(status.healthScore) (\(status.healthMessage))" }
            let title = String(itemID.dropFirst("row:".count))
            return status.rows.first { $0.title == title }.map { "\($0.title): \($0.value)" }
        case .history(let entries):
            let index = Int(itemID.dropFirst("history:".count)) ?? -1
            guard entries.indices.contains(index) else { return nil }
            let entry = entries[index]
            return "\(entry.command) \(entry.startedAt): \(entry.items) items, \(entry.size)"
        case .report(let report):
            let index = Int(itemID.dropFirst("item:".count)) ?? -1
            guard report.items.indices.contains(index) else { return nil }
            let item = report.items[index]
            return [item.section, item.title, item.detail]
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
        case .idle, .loading, .failed, .purge, .apps, .analysis, .installers:
            return nil
        }
    }

    private static func filtered(_ items: [PluginPaletteItem], query: String)
        -> [PluginPaletteItem]
    {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }
        return items.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
                || $0.subtitle?.localizedCaseInsensitiveContains(trimmed) == true
        }
    }
}

extension AppCore {
    func openMole(_ screen: MoleScreen) {
        guard plugins.isEnabled(.mole) else { return }
        mole.open(screen)
        palette.prepare(mode: .plugin(.mole))
        showPalette(mode: .plugin(.mole))
    }

    func runMole(_ command: MoleCommand) {
        guard plugins.isEnabled(.mole) else { return }
        openMole(command.screen)
    }

    /// Installer files are plain files, so Spotter trashes them itself — recoverable, confirmed
    /// in-palette, and the list re-reads so what's left is what's shown.
    func trashMoleInstaller(_ entry: MoleInstallerEntry) {
        guard plugins.isEnabled(.mole) else { return }
        confirmInPalette(
            PaletteConfirmation(
                title: "Move “\(entry.name)” to Trash?",
                message:
                    "The \(MoleParser.bytes(entry.size)) installer file moves to the Trash. Anything it installed is untouched.",
                actionTitle: "Move to Trash"
            ) { [weak self] in
                guard let self else { return }
                do {
                    try FileManager.default.trashItem(
                        at: URL(fileURLWithPath: entry.path), resultingItemURL: nil)
                    self.hud.show(
                        title: "Moved to Trash · \(MoleParser.bytes(entry.size))", symbol: "trash")
                } catch {
                    AppLog.error(
                        "mole", "Trashing \(entry.name) failed: \(error.localizedDescription)")
                    self.hud.show(
                        title: "Couldn't move “\(entry.name)” to Trash",
                        symbol: "exclamationmark.triangle")
                }
                self.mole.reload()
            })
    }

    /// The one funnel every state-changing Mole run passes through, so no path skips the confirmation.
    /// Whether an app row can offer the Mole hand-off: real apps only, never Spotter itself.
    func canUninstallWithMole(_ app: AppEntry) -> Bool {
        plugins.isEnabled(.mole) && mole.isInstalled && app.kind == .application
            && app.bundleID != Bundle.main.bundleIdentifier
    }

    /// Launcher app rows hand their uninstall to the same confirmed background-task funnel.
    func uninstallWithMole(_ app: AppEntry) {
        guard canUninstallWithMole(app) else { return }
        runMoleAction(.uninstall(name: app.name, permanent: false))
    }

    func runMoleAction(_ action: MoleAction) {
        guard plugins.isEnabled(.mole), !mole.isRunning else { return }
        confirmInPalette(
            PaletteConfirmation(
                title: "\(action.title)?",
                message: action.confirmation,
                actionTitle: action.title,
                isDestructive: action.isPermanent
            ) { [weak self] in
                guard let self, !self.mole.isRunning else { return }
                let taskID = self.backgroundTasks.begin(
                    title: action.backgroundTaskTitle,
                    detail: "Starting \(action.title.lowercased())…",
                    systemImage: action.systemImage)
                if !self.mole.run(action, taskID: taskID) {
                    self.backgroundTasks.fail(id: taskID, detail: "Mole couldn't start this task.")
                }
                self.mole.stop()
                self.palette.prepare(mode: .launcher)
                self.showPalette(mode: .launcher)
            })
    }

    func performMoleRow(itemID: String) {
        guard plugins.isEnabled(.mole) else { return }
        if itemID.hasPrefix("menu:") {
            let raw = String(itemID.dropFirst("menu:".count))
            guard let command = MoleCommand(rawValue: raw) else { return }
            runMole(command)
            return
        }
        if itemID == "run" {
            guard !mole.isLoadingPreview else { return }
            guard let action = MoleResults.pendingAction(for: mole.screen) else { return }
            runMoleAction(action)
            return
        }
        if itemID == "up" {
            mole.ascend()
            return
        }
        if let entry = MoleResults.diskEntry(manager: mole, itemID: itemID) {
            entry.isDirectory ? mole.descend(into: entry) : revealInFinder(path: entry.path)
            return
        }
        if let installer = MoleResults.installerEntry(manager: mole, itemID: itemID) {
            trashMoleInstaller(installer)
            return
        }
        if let app = MoleResults.app(manager: mole, itemID: itemID) {
            runMoleAction(.uninstall(name: app.uninstallName, permanent: false))
            return
        }
        if let path = MoleResults.revealablePath(manager: mole, itemID: itemID) {
            revealInFinder(path: path)
            return
        }
        guard let text = MoleResults.copyText(manager: mole, itemID: itemID) else { return }
        hidePalette(restoreFocus: false)
        Paster.copyPlainText(text)
    }

    func revealInFinder(path: String) {
        guard !path.isEmpty else { return }
        hidePalette(restoreFocus: false)
        AppLauncher.showInFinder(URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
    }
}
