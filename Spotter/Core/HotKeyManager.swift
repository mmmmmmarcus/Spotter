import Foundation

/// Owns all global shortcut bindings: persistence, Carbon registration (via `HotKeyCenter`), conflict lookup, and dispatch.
@MainActor
final class HotKeyManager: ObservableObject {
    var onTogglePalette: (() -> Void)?
    var onRunPluginAction: ((PluginActionKey) -> Void)?
    var onRunCustomCommand: ((UUID) -> Void)?

    /// The recorder currently capturing keystrokes, or `nil`; keeping this as plain app state makes recorders glitch-free, and any active recorder pauses both engines so the shortcut being typed can't fire the binding it's replacing.
    @Published var recordingAction: HotKeyAction? {
        didSet {
            guard recordingAction != oldValue else { return }
            center.isPaused = recordingAction != nil
            doubleTapMonitor.isPaused = recordingAction != nil
        }
    }

    /// The second engine: Carbon can't register a modifier-only shortcut, so double-taps are recognized by an event tap instead.
    let doubleTapMonitor = DoubleTapMonitor()

    private let center = HotKeyCenter()
    private var doubleTaps: [DoubleTapModifier: HotKeyAction] = [:]
    private let boundKey = "boundAppBundleIDs"
    private let boundPaneKey = "boundPaneBundleIDs"
    private let boundCustomCommandKey = "boundCustomCommandIDs"

    private var pluginActions: [PluginActionKey] = []

    func start(
        pluginActions: [PluginActionKey],
        defaultPluginShortcuts: [(PluginActionKey, KeyShortcut)] = [],
        customCommandIDs: Set<UUID>
    ) {
        self.pluginActions = pluginActions
        seedDefaultPluginShortcuts(defaultPluginShortcuts)
        register(.togglePalette)
        register(.togglePaletteBackup)
        for action in pluginActions { register(.plugin(action)) }
        for bundleID in boundBundleIDs { register(.app(bundleID: bundleID)) }
        for bundleID in boundPaneBundleIDs { register(.settingsPane(bundleID: bundleID)) }
        let stale = Set(boundCustomCommandIDs).subtracting(customCommandIDs)
        for id in stale {
            UserDefaults.standard.removeObject(forKey: HotKeyAction.customCommand(id: id).defaultsKey)
        }
        let live = Set(boundCustomCommandIDs).intersection(customCommandIDs)
        persistBoundCustomCommandIDs(live)
        for id in live { register(.customCommand(id: id)) }

        doubleTapMonitor.onDoubleTap = { [weak self] modifier in
            guard let self, let action = doubleTaps[modifier] else { return }
            perform(action)
        }
        doubleTapMonitor.start()
        syncDoubleTaps()
    }

    /// Seeds a shipped default once. The marker distinguishes a deliberate later unbind from a fresh install.
    private func seedDefaultPluginShortcuts(
        _ defaults: [(PluginActionKey, KeyShortcut)]
    ) {
        for (key, shortcut) in defaults {
            let action = HotKeyAction.plugin(key)
            let marker = "hotkey.default-seeded." + key.defaultsKey
            guard UserDefaults.standard.object(forKey: marker) == nil else { continue }
            defer { UserDefaults.standard.set(true, forKey: marker) }
            guard UserDefaults.standard.object(forKey: action.defaultsKey) == nil else { continue }
            guard conflictOwner(of: shortcut, excluding: action) == nil else { continue }
            setShortcut(shortcut, for: action)
        }
    }

    /// Bundle IDs that currently have a per-app hotkey — lets `start()` know which records to load and lets launcher rows show keycaps.
    var boundBundleIDs: [String] {
        UserDefaults.standard.stringArray(forKey: boundKey) ?? []
    }

    /// Settings-pane bundle IDs with a hotkey — same role as `boundBundleIDs`, own namespace.
    var boundPaneBundleIDs: [String] {
        UserDefaults.standard.stringArray(forKey: boundPaneKey) ?? []
    }

    /// Custom-command UUIDs with a Carbon binding, indexed separately so startup can re-register them.
    var boundCustomCommandIDs: [UUID] {
        (UserDefaults.standard.stringArray(forKey: boundCustomCommandKey) ?? [])
            .compactMap(UUID.init(uuidString:))
    }

    func shortcut(for action: HotKeyAction) -> KeyShortcut? {
        binding(for: action)?.shortcut
    }

    /// A combo decodes from the bare legacy `KeyShortcut` record, so existing `KeyboardShortcuts_*` values and old backups still load; a double-tap has its own shape.
    func binding(for action: HotKeyAction) -> HotKeyBinding? {
        // The stored value is a JSON *string* (a legacy package format); anything else reads as unbound.
        guard
            let json = UserDefaults.standard.string(forKey: action.defaultsKey),
            let data = json.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(HotKeyBinding.self, from: data)
    }

    func setShortcut(_ shortcut: KeyShortcut?, for action: HotKeyAction) {
        setBinding(shortcut.map(HotKeyBinding.combo), for: action)
    }

    /// Persists (or clears, when `nil`) the binding, swaps the live registration, and publishes so the launcher and recorders re-render.
    func setBinding(_ binding: HotKeyBinding?, for action: HotKeyAction) {
        objectWillChange.send()
        let previous = self.binding(for: action)
        if let binding,
            let data = try? JSONEncoder().encode(binding),
            let json = String(data: data, encoding: .utf8)
        {
            UserDefaults.standard.set(json, forKey: action.defaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: action.defaultsKey)
        }
        // Unregister unconditionally: the previous binding may have been a combo even when the new one isn't.
        center.unregister(id: action.defaultsKey)
        register(action)

        switch action {
        case .app(let bundleID):
            var set = Set(boundBundleIDs)
            if binding == nil { set.remove(bundleID) } else { set.insert(bundleID) }
            UserDefaults.standard.set(Array(set), forKey: boundKey)
        case .settingsPane(let bundleID):
            var set = Set(boundPaneBundleIDs)
            if binding == nil { set.remove(bundleID) } else { set.insert(bundleID) }
            UserDefaults.standard.set(Array(set), forKey: boundPaneKey)
        case .customCommand(let id):
            var set = Set(boundCustomCommandIDs)
            if binding == nil { set.remove(id) } else { set.insert(id) }
            persistBoundCustomCommandIDs(set)
        case .togglePalette, .togglePaletteBackup, .plugin:
            break
        }
        // A rebuild re-decodes every action; only a double-tap entering or leaving changes the map.
        if previous?.doubleTapModifier != nil || binding?.doubleTapModifier != nil {
            syncDoubleTaps()
        }
    }

    func conflictOwner(of shortcut: KeyShortcut, excluding action: HotKeyAction) -> String? {
        conflictOwner(of: .combo(shortcut), excluding: action)
    }

    /// The display name of whatever else `binding` is bound to (or `nil` if free), driving the recorder's "Used by …" message. Comparing whole bindings gives double-taps conflict detection on the same terms as combos.
    func conflictOwner(of binding: HotKeyBinding, excluding action: HotKeyAction) -> String? {
        for candidate in candidateActions
        where candidate != action && self.binding(for: candidate) == binding {
            return displayName(of: candidate)
        }
        return nil
    }

    /// Every action that could currently hold a binding — the search space for conflicts and for rebuilding the double-tap map.
    private var candidateActions: [HotKeyAction] {
        var actions: [HotKeyAction] = [.togglePalette, .togglePaletteBackup]
        actions += pluginActions.map(HotKeyAction.plugin)
        actions += boundBundleIDs.map { .app(bundleID: $0) }
        actions += boundPaneBundleIDs.map { .settingsPane(bundleID: $0) }
        actions += boundCustomCommandIDs.map { .customCommand(id: $0) }
        return actions
    }

    /// Rebuilt wholesale rather than patched, so the map can't drift from what's on disk. Conflict detection keeps it one action per modifier.
    private func syncDoubleTaps() {
        var map: [DoubleTapModifier: HotKeyAction] = [:]
        for action in candidateActions {
            guard let modifier = binding(for: action)?.doubleTapModifier else { continue }
            map[modifier] = action
        }
        doubleTaps = map
        doubleTapMonitor.update(bound: Set(map.keys))
    }

    private func displayName(of action: HotKeyAction) -> String {
        switch action {
        case .togglePalette:
            return "App Launcher"
        case .togglePaletteBackup:
            return "App Launcher (Backup)"
        case .plugin(let action):
            return action.title
        case .app(let bundleID):
            let apps = AppCore.shared.appIndex.apps
            return apps.first { $0.kind == .application && $0.bundleID == bundleID }?.name
                ?? bundleID
        case .settingsPane(let bundleID):
            let apps = AppCore.shared.appIndex.apps
            return apps.first { $0.kind == .systemSettings && $0.bundleID == bundleID }?.name
                ?? bundleID
        case .customCommand(let id):
            return AppCore.shared.customCommands.command(id: id)?.name ?? "Custom Command"
        }
    }

    private func register(_ action: HotKeyAction) {
        guard let shortcut = shortcut(for: action) else { return }
        center.register(id: action.defaultsKey, shortcut: shortcut) { [weak self] in
            self?.perform(action)
        }
    }

    private func perform(_ action: HotKeyAction) {
        switch action {
        case .togglePalette, .togglePaletteBackup: onTogglePalette?()
        case .plugin(let action): onRunPluginAction?(action)
        case .app(let bundleID): AppLauncher.toggle(bundleID: bundleID)
        case .settingsPane(let bundleID): AppLauncher.openSettingsPane(bundleID: bundleID)
        case .customCommand(let id): onRunCustomCommand?(id)
        }
    }

    private func persistBoundCustomCommandIDs(_ ids: Set<UUID>) {
        UserDefaults.standard.set(
            ids.map { $0.uuidString.lowercased() }.sorted(), forKey: boundCustomCommandKey)
    }
}
