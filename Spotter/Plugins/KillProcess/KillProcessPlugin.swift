import AppKit
import Combine
import SwiftUI

extension PluginActionKey {
    static let openKillProcess = standard(
        pluginID: .killProcess, actionID: "open", title: "Kill Process")
}

@MainActor
enum KillProcessPlugin {
    static func registration(core: AppCore) -> PluginRegistration {
        let open: () -> Void = { [weak core] in core?.openKillProcess() }
        let screen = PluginPaletteScreenRegistration(
            placeholder: "Filter processes by name, path, or PID…",
            snapshot: { [weak core] query in
                guard let core else {
                    return PluginPaletteSnapshot(
                        sectionTitle: "Processes", items: [], emptyMessage: "Plugin unavailable")
                }
                return snapshot(manager: core.killProcess, query: query)
            },
            performPrimaryAction: { [weak core] itemID in
                guard let core, let process = process(itemID: itemID, manager: core.killProcess) else {
                    return
                }
                core.performKillProcessAction(.kill, process: process)
            },
            actions: { [weak core] itemID in
                guard let core, let process = process(itemID: itemID, manager: core.killProcess) else {
                    return nil
                }
                return actions(process: process, core: core)
            },
            onOpen: { [weak core] in core?.killProcess.start() },
            onClose: { [weak core] in core?.killProcess.stop() },
            observeChanges: { [weak core] invalidate in
                core?.killProcess.objectWillChange.sink { invalidate() }
                    ?? AnyCancellable {}
            })
        return PluginRegistration(
            metadata: PluginMetadata(
                id: .killProcess,
                name: "Kill Process",
                summary: "Inspect, terminate, force-terminate, and restart running processes.",
                systemImage: "xmark.octagon",
                tint: .red),
            defaultEnabled: true,
            shortcutActions: [PluginActionRegistration(key: .openKillProcess, perform: open)],
            launcherCommands: [
                PluginCommandRegistration(
                    id: "command:kill-process", name: "Kill Process",
                    systemImage: "xmark.octagon", actionKey: .openKillProcess, perform: open)
            ],
            paletteScreen: screen,
            onDisable: { [weak core] in
                core?.killProcess.stop()
                if core?.palette.mode == .plugin(.killProcess) {
                    core?.palette.prepare(mode: .launcher)
                }
            },
            settingsView: { AnyView(KillProcessSettingsView()) })
    }

    private static func snapshot(
        manager: KillProcessManager, query: String
    ) -> PluginPaletteSnapshot {
        let processes = manager.errorMessage == nil
            ? visibleProcesses(manager: manager, query: query) : []
        let items = processes.map { process in
            PluginPaletteItem(
                id: String(process.id),
                title: process.appName ?? process.processName,
                subtitle: subtitle(for: process),
                icon: process.appBundlePath.map { .file(path: $0) } ?? .symbol("terminal"),
                accessories: [
                    PluginPaletteAccessory(
                        systemImage: "cpu",
                        text: process.cpu.formatted(.number.precision(.fractionLength(2))) + "%"),
                    PluginPaletteAccessory(
                        systemImage: "memorychip",
                        text: ByteCountFormatter.string(
                            fromByteCount: process.memoryKB * 1024, countStyle: .memory)),
                ],
                primaryActionTitle: "Kill Process")
        }
        return PluginPaletteSnapshot(
            sectionTitle: "Processes", items: items,
            isLoading: manager.isRefreshing,
            errorMessage: manager.errorMessage,
            emptyMessage: query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "No processes found" : "No matching processes")
    }

    private static func visibleProcesses(
        manager: KillProcessManager, query: String
    ) -> [RunningProcessInfo] {
        let defaults = UserDefaults.standard
        let sort = ProcessSort(
            rawValue: defaults.string(forKey: "kill-process.sort") ?? ProcessSort.cpu.rawValue)
            ?? .cpu
        return KillProcessEngine.visible(
            manager.processes, query: query, sort: sort,
            groupingApplications: defaults.object(forKey: "kill-process.group-apps") == nil
                || defaults.bool(forKey: "kill-process.group-apps"),
            searchPaths: defaults.bool(forKey: "kill-process.search-paths"),
            searchPIDs: defaults.object(forKey: "kill-process.search-pids") == nil
                || defaults.bool(forKey: "kill-process.search-pids"),
            prioritizeApps: defaults.object(forKey: "kill-process.prioritize-apps") == nil
                || defaults.bool(forKey: "kill-process.prioritize-apps"))
    }

    private static func process(
        itemID: String, manager: KillProcessManager
    ) -> RunningProcessInfo? {
        visibleProcesses(manager: manager, query: "").first { String($0.id) == itemID }
    }

    private static func subtitle(for process: RunningProcessInfo) -> String? {
        let defaults = UserDefaults.standard
        var parts: [String] = []
        if let appName = process.appName, appName != process.processName {
            parts.append(process.processName)
        }
        if process.kind == .aggregatedApp {
            parts.append("\(process.childProcessIDs.count + 1) processes")
        }
        if defaults.object(forKey: "kill-process.show-pid") == nil
            || defaults.bool(forKey: "kill-process.show-pid")
        {
            parts.append("PID \(process.id)")
        }
        if defaults.bool(forKey: "kill-process.show-path"), !process.executablePath.isEmpty {
            parts.append(process.executablePath)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func actions(
        process: RunningProcessInfo, core: AppCore
    ) -> PopoverMenuContent {
        var items = [
            PopoverMenuItem(
                title: "Kill Process", systemImage: "xmark.circle", shortcut: "↵",
                isDestructive: true
            ) { core.performKillProcessAction(.kill, process: process) },
            PopoverMenuItem(
                title: "Force Kill", systemImage: "bolt.fill", isDestructive: true
            ) { core.performKillProcessAction(.forceKill, process: process) },
        ]
        if process.canRestart {
            items.append(
                PopoverMenuItem(title: "Restart", systemImage: "arrow.clockwise") {
                    core.performKillProcessAction(.restart, process: process)
                })
            items.append(
                PopoverMenuItem(
                    title: "Force Restart", systemImage: "arrow.trianglehead.2.clockwise.rotate.90",
                    isDestructive: true
                ) { core.performKillProcessAction(.forceRestart, process: process) })
        }
        items.append(
            PopoverMenuItem(
                title: "Kill All \(process.processName)", systemImage: "xmark.circle.fill",
                isDestructive: true
            ) { core.performKillProcessAction(.killAll, process: process) })
        items.append(
            PopoverMenuItem(
                title: "Force Kill All \(process.processName)", systemImage: "bolt.circle.fill",
                isDestructive: true
            ) { core.performKillProcessAction(.forceKillAll, process: process) })
        if !process.executablePath.isEmpty {
            items.append(
                PopoverMenuItem(title: "Copy Path", systemImage: "doc.on.doc") {
                    core.performKillProcessAction(.copyPath, process: process)
                })
        }
        items.append(
            PopoverMenuItem(
                title: "Refresh Processes", systemImage: "arrow.clockwise"
            ) { Task { await core.killProcess.refresh() } })
        return PopoverMenuContent(header: process.appName ?? process.processName, items: items)
    }
}

extension AppCore {
    func openKillProcess() {
        guard plugins.isEnabled(.killProcess) else { return }
        showPalette(mode: .plugin(.killProcess))
    }

    func performKillProcessAction(
        _ action: KillProcessAction, process: RunningProcessInfo
    ) {
        if action == .copyPath {
            hidePalette(restoreFocus: false)
            Paster.copyPlainText(process.executablePath)
            return
        }

        let title = action.title
        Task {
            do {
                switch action {
                case .kill, .forceKill:
                    try await killProcess.terminate(process, force: action.isForced)
                case .restart, .forceRestart:
                    try await killProcess.restart(process, force: action.isForced)
                case .killAll, .forceKillAll:
                    try await killProcess.terminateAll(
                        named: process.processName, force: action.isForced)
                case .copyPath:
                    break
                }
            } catch {
                Self.presentKillProcessFailure(title, error: error)
            }
        }
    }

    private static func presentKillProcessFailure(_ action: String, error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "\(action) Failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

enum KillProcessAction {
    case kill, forceKill, restart, forceRestart, killAll, forceKillAll, copyPath

    var isForced: Bool {
        self == .forceKill || self == .forceRestart || self == .forceKillAll
    }

    var title: String {
        switch self {
        case .kill: return "Kill"
        case .forceKill: return "Force Kill"
        case .restart: return "Restart"
        case .forceRestart: return "Force Restart"
        case .killAll: return "Kill All"
        case .forceKillAll: return "Force Kill All"
        case .copyPath: return "Copy Path"
        }
    }
}
