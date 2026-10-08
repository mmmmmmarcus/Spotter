import AppKit
import Combine
import SwiftUI

@MainActor
final class ExtensionCoordinator: ObservableObject {
    unowned let core: AppCore
    @Published private(set) var enabled = UserDefaults.standard.bool(forKey: "raycast-extensions.enabled")
    @Published var packageManager = ExtensionPackageManager(rawValue: UserDefaults.standard.string(forKey: "raycast-extensions.package-manager") ?? "automatic") ?? .automatic {
        didSet { UserDefaults.standard.set(packageManager.rawValue, forKey: "raycast-extensions.package-manager") }
    }
    @Published var customSearchPaths = UserDefaults.standard.string(forKey: "raycast-extensions.search-paths") ?? "" {
        didSet { UserDefaults.standard.set(customSearchPaths, forKey: "raycast-extensions.search-paths") }
    }
    @Published var isBrowsingStore = false
    private var queryObserver: AnyCancellable?
    private var invalidation: (@MainActor () -> Void)?
    private var generation = UUID()
    private var runGeneration = UUID()
    private var hostHiding = false
    lazy var controls = ExtensionPaletteState(palette: core.palette)
    struct PendingArguments {
        let entry: AppEntry
        let command: ExtensionCommand
        let fallbackText: String?
        let launchContext: [String: RenderValue]
    }
    @Published var pendingArguments: PendingArguments?
    @Published var argumentFocus: String?
    @Published var argumentValues: [String: String] = [:]
    @Published var actionsRequest = UUID()
    var target: NSRunningApplication?

    init(core: AppCore) { self.core = core }

    func start() {
        core.extensions.start(coordinator: self)
        core.extensions.setShowsInLauncher(UserDefaults.standard.object(forKey: "raycast-extensions.show-in-launcher") as? Bool ?? true)
        core.extensions.onCommandsChanged = { [weak self] in
            guard let self else { return }
            core.plugins.reloadDynamicCommands(for: .raycastExtensions)
            core.hotKeys.refreshPluginActions(core.plugins.shortcutActions)
        }
        Task { await core.extensions.setEnabled(enabled) }
    }

    func setEnabled(_ value: Bool) {
        if value {
            let alert = NSAlert()
            alert.messageText = "Enable Raycast Extensions?"
            alert.informativeText = "Extensions are third-party JavaScript running on this Mac. They can access files, run commands and contact their own services. Store searches contact Raycast; source installs contact GitHub and package registries when you request them."
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Enable")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        enabled = value
        UserDefaults.standard.set(value, forKey: "raycast-extensions.enabled")
        if !value { core.raycastStore.close() }
        Task {
            await core.extensions.setEnabled(value)
            if isBrowsingStore { core.raycastStore.queryChanged(core.palette.query) }
        }
    }

    func observe(_ invalidate: @escaping @MainActor () -> Void) -> AnyCancellable {
        invalidation = invalidate
        generation = UUID()
        track(generation)
        let storeObserver = core.raycastStore.objectWillChange.sink { Task { @MainActor in invalidate() } }
        let modeObserver = objectWillChange.sink { Task { @MainActor in invalidate() } }
        return AnyCancellable { [weak self] in
            storeObserver.cancel()
            modeObserver.cancel()
            Task { @MainActor in self?.generation = UUID(); self?.invalidation = nil }
        }
    }

    private func track(_ token: UUID) {
        guard generation == token else { return }
        withObservationTracking {
            _ = core.extensions.state
            _ = core.extensions.toasts
            _ = core.extensions.accessoryValues
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.invalidation?()
                self.track(token)
            }
        }
    }

    func beginQuery() {
        queryObserver = core.palette.$query.removeDuplicates().sink { [weak self] query in
            guard let self else { return }
            if isBrowsingStore { core.raycastStore.queryChanged(query); return }
            guard let handler = screen.searchTextHandler else { return }
            core.extensions.dispatch(handler: handler, arguments: [query])
        }
    }

    func endQuery() {
        queryObserver = nil
        if isBrowsingStore { core.raycastStore.close(); isBrowsingStore = false; return }
        controls.dismissControlList()
        pendingArguments = nil
        argumentValues = [:]
        guard !hostHiding, !core.extensions.isAuthorizing else { return }
        let token = runGeneration
        Task { if runGeneration == token { await core.extensions.stop() } }
    }

    var screen: ExtensionScreen {
        if pendingArguments != nil { return .empty }
        if case .rendered(let tree) = core.extensions.state { return ExtensionScreen(tree: tree, query: core.palette.query) }
        return .empty
    }

    func actions(at selection: Int, query: String = "") -> [ExtensionAction] {
        let actions = ExtensionScreen.actions(in: screen.actionPanel(forItemAt: selection))
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return actions }
        let needle = FuzzyMatch.Query(text)
        return actions.filter { FuzzyMatch.match(needle, candidate: $0.title) != nil }
    }

    func runExtensionCommand(_ entry: AppEntry, arguments: [String: String] = [:], fallbackText: String? = nil,
        launchType: ExtensionLaunchType = .userInitiated, launchContext: [String: RenderValue] = [:]) {
        guard enabled, let (owner, command) = core.extensions.resolve(entry) else { return }
        if isBrowsingStore { core.raycastStore.close(); isBrowsingStore = false }
        if !core.isPaletteShowing { target = NSWorkspace.shared.frontmostApplication }
        if launchType == .userInitiated, command.arguments.contains(where: { arguments[$0.name] == nil }) {
            argumentFocus = command.arguments.first?.name
            argumentValues = arguments
            pendingArguments = PendingArguments(entry: entry, command: command, fallbackText: fallbackText, launchContext: launchContext)
            runGeneration = UUID()
            core.showPalette(mode: .plugin(.raycastExtensions))
            return
        }
        pendingArguments = nil
        runGeneration = UUID()
        if command.mode == .view {
            core.showPalette(mode: .plugin(.raycastExtensions))
            if let fallbackText { core.palette.query = fallbackText }
        }
        else { core.hidePalette(restoreFocus: false) }
        Task {
            await core.extensions.run(owner, command: command, arguments: arguments,
                fallbackText: fallbackText, launchType: launchType, launchContext: launchContext)
        }
    }

    func handleURL(_ url: URL) {
        guard enabled else { return }
        switch ExtensionOAuthSession.handleCallbackURL(url) {
        case .delivered: reopenPalette(hasRunningCommand: core.extensions.running != nil); return
        case .expired: showHUD("The extension login has expired. Try again."); return
        case .ignored: break
        }
        guard let link = ExtensionDeepLink.parse(url: url) else { return }
        Task {
            await core.extensions.refresh()
            guard let (owner, command) = core.extensions.resolve(link),
                let entry = core.extensions.launcherEntry(forEntryID: ExtensionCommandRef(extensionName: owner.id, commandName: command.name).entryID) else {
                showHUD("This extension command is not installed.")
                return
            }
            runExtensionCommand(entry, arguments: link.arguments, fallbackText: link.fallbackText, launchType: link.launchType)
        }
    }

    func handleKey(_ event: NSEvent) -> Bool {
        guard !isBrowsingStore, core.palette.mode == .plugin(.raycastExtensions), !controls.menuOpen else { return false }
        if pendingArguments != nil { return false }
        let screen = self.screen
        var modifiers: EventModifiers = []
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        if !modifiers.isEmpty, let character = event.charactersIgnoringModifiers?.first {
            let actions = ExtensionScreen.actions(in: screen.actionPanel(forItemAt: core.palette.selection))
            if let handler = actions.first(where: { $0.matches(key: KeyEquivalent(character), modifiers: modifiers) })?.handler {
                core.extensions.dispatch(handler: handler)
                return true
            }
        }
        if event.keyCode == 53, modifiers.isEmpty {
            if core.extensions.navigationDepth > 1 { Task { _ = await core.extensions.popNavigation() } }
            else { core.showPalette(mode: .launcher) }
            return true
        }
        if event.keyCode == 36, modifiers.isEmpty, !controls.isEditingField {
            RaycastExtensionsPlugin.activate(core, index: core.palette.selection)
            return true
        }
        if case .grid(let layout) = screen.kind, modifiers.isEmpty {
            let geometry = ExtensionGridGeometry(counts: screen.sectionCounts, columns: layout.columns)
            let old = core.palette.selection
            switch event.keyCode {
            case 125: core.palette.selection = geometry.down(from: old)
            case 126: core.palette.selection = geometry.up(from: old)
            case 123: core.palette.selection = max(0, old - 1)
            case 124: core.palette.selection = min(max(0, geometry.cellCount - 1), old + 1)
            default: return false
            }
            core.palette.followToken = UUID()
            return true
        }
        if screen.kind == .form, modifiers.isEmpty, [125, 126].contains(event.keyCode) {
            guard !screen.ownsVerticalKeys(at: core.palette.selection) else { return false }
            core.palette.selection = min(max(0, core.palette.selection + (event.keyCode == 125 ? 1 : -1)), max(0, screen.items.count - 1))
            core.palette.followToken = UUID()
            return true
        }
        if screen.kind == .form, event.keyCode == 48, modifiers.isSubset(of: [.shift]) {
            let count = screen.items.count
            guard count > 0 else { return true }
            core.palette.selection = (core.palette.selection + (modifiers.contains(.shift) ? count - 1 : 1)) % count
            core.palette.followToken = UUID()
            return true
        }
        return false
    }

    func submitArguments() {
        guard let pending = pendingArguments else { return }
        var values = argumentValues
        for argument in pending.command.arguments {
            let value = values[argument.name] ?? ""
            guard !argument.required || !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                showHUD("Missing required argument: " + argument.placeholder)
                return
            }
            values[argument.name] = value
        }
        runExtensionCommand(pending.entry, arguments: values, fallbackText: pending.fallbackText, launchContext: pending.launchContext)
    }

    func showExtensionSettings(for owner: InstalledExtension) {
        core.showSettings(destination: .raycastExtension(owner.id))
    }

    func openStore() {
        Task { await core.extensions.stop() }
        isBrowsingStore = true
        core.showPalette(mode: .plugin(.raycastExtensions))
        core.palette.query = ""
        beginQuery()
    }
    var pasteTarget: NSRunningApplication? { core.isPaletteShowing ? core.extensionPasteTarget : (target ?? core.extensionPasteTarget) }
    var applicationURLs: [URL] { core.appIndex.apps.filter { $0.kind == .application }.map(\.url) }
    var isPaletteVisible: Bool { core.isPaletteShowing }
    var isAuthorizing: Bool { core.extensions.isAuthorizing }
    func closeMainWindow() {
        hostHiding = true
        core.hidePalette(restoreFocus: false)
        hostHiding = false
    }
    func reopenPalette(hasRunningCommand: Bool) { core.showPalette(mode: hasRunningCommand ? .plugin(.raycastExtensions) : .launcher) }
    func popExtensionToRoot() { core.showPalette(mode: .launcher) }
    func clearSearchBar() { core.palette.query = "" }
    func showHUD(_ message: String) { core.hud.show(title: message, symbol: "puzzlepiece.extension") }
    func confirmExtensionAlert(_ value: ExtensionAlert) async -> Bool {
        let alert = NSAlert()
        alert.messageText = value.title
        alert.informativeText = value.message ?? ""
        alert.addButton(withTitle: value.dismissTitle ?? "Cancel")
        alert.addButton(withTitle: value.primaryTitle)
        return alert.runModal() == .alertSecondButtonReturn
    }
}
