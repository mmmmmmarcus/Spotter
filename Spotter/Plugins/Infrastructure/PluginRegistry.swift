import Combine
import SwiftUI

@MainActor
struct PluginActionRegistration {
    let key: PluginActionKey
    let perform: () -> Void
}

@MainActor
struct PluginCommandRegistration {
    let id: String
    let name: String
    let systemImage: String
    var actionKey: PluginActionKey?
    var defaultVisible = true
    let perform: () -> Void

    var entry: AppEntry {
        AppEntry(
            id: id, name: name,
            url: URL(string: "spotter://plugin-command/" + id)!,
            bundleID: nil, kind: .command, symbolImage: systemImage,
            pluginActionKey: actionKey)
    }
}

/// A plugin-owned data source rendered by the shared command-palette shell and row grammar.
@MainActor
struct PluginPaletteScreenRegistration {
    let placeholder: String
    let snapshot: (_ query: String) -> PluginPaletteSnapshot
    let performPrimaryAction: (_ itemID: String) -> Void
    let actions: (_ itemID: String) -> PopoverMenuContent?
    var onOpen: () -> Void = {}
    var onClose: () -> Void = {}
    var observeChanges: ((_ invalidate: @escaping @MainActor () -> Void) -> AnyCancellable)?
}

/// A compiled, signed built-in plugin registration that standardizes discovery without runtime loading.
@MainActor
struct PluginRegistration {
    let metadata: PluginMetadata
    let defaultEnabled: Bool
    var canDisable = true
    var exportsEnabledState = true
    var permissions: Set<PluginPermission> = []
    var shortcutActions: [PluginActionRegistration] = []
    var launcherCommands: [PluginCommandRegistration] = []
    var queryProvider: (any PluginQueryProvider)?
    var paletteScreen: PluginPaletteScreenRegistration?
    var readEnabled: (() -> Bool)?
    var writeEnabled: ((Bool) -> Void)?
    var onEnable: () -> Void = {}
    var onDisable: () -> Void = {}
    let settingsView: () -> AnyView
}

/// Ordered built-in registry; `AppCore` remains the sole owner of it and all captured managers.
@MainActor
final class PluginRegistry: ObservableObject {
    private let defaults: UserDefaults
    private var registrations: [PluginID: PluginRegistration] = [:]
    private var orderedIDs: [PluginID] = []
    private var enabledQueryProviders: [any PluginQueryProvider] = []
    private var commandOwners: [String: PluginID] = [:]
    private var paletteObservers: [PluginID: AnyCancellable] = [:]
    private var activePaletteScreen: PluginID?
    private var started = false
    var onCommandsChanged: (([AppEntry]) -> Void)?
    var onEnabledStatesChanged: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var plugins: [PluginMetadata] {
        orderedIDs.compactMap { registrations[$0]?.metadata }
    }

    var shortcutActions: [PluginActionKey] {
        orderedIDs.flatMap { registrations[$0]?.shortcutActions.map(\.key) ?? [] }
    }

    var launcherCommands: [AppEntry] {
        orderedIDs.flatMap { id -> [AppEntry] in
            guard isEnabled(id) else { return [] }
            return registrations[id]?.launcherCommands.map(\.entry) ?? []
        }
    }

    var initiallyHiddenLauncherCommands: [AppEntry] {
        orderedIDs.flatMap { id in
            registrations[id]?.launcherCommands.filter { !$0.defaultVisible }.map(\.entry) ?? []
        }
    }

    func register(_ registration: PluginRegistration) {
        let id = registration.metadata.id
        precondition(registrations[id] == nil, "Duplicate plugin id: \(id.rawValue)")
        for command in registration.launcherCommands {
            precondition(commandOwners[command.id] == nil, "Duplicate plugin command: \(command.id)")
            commandOwners[command.id] = id
        }
        registrations[id] = registration
        orderedIDs.append(id)
        if let observe = registration.paletteScreen?.observeChanges {
            paletteObservers[id] = observe { [weak self] in
                self?.objectWillChange.send()
            }
        }
        rebuildQueryProviders()
        onCommandsChanged?(launcherCommands)
    }

    func start() {
        guard !started else { return }
        started = true
        for id in orderedIDs where isEnabled(id) {
            registrations[id]?.onEnable()
        }
    }

    func isEnabled(_ id: PluginID) -> Bool {
        guard let registration = registrations[id] else { return false }
        if let readEnabled = registration.readEnabled { return readEnabled() }
        let key = enabledKey(for: id)
        guard defaults.object(forKey: key) != nil else { return registration.defaultEnabled }
        return defaults.bool(forKey: key)
    }

    func setEnabled(_ enabled: Bool, for id: PluginID) {
        guard let registration = registrations[id], registration.canDisable,
            enabled != isEnabled(id)
        else { return }

        objectWillChange.send()
        if !enabled { deactivatePaletteScreen(id) }
        if let writeEnabled = registration.writeEnabled {
            writeEnabled(enabled)
        } else {
            defaults.set(enabled, forKey: enabledKey(for: id))
        }
        if started {
            enabled ? registration.onEnable() : registration.onDisable()
        }
        rebuildQueryProviders()
        onCommandsChanged?(launcherCommands)
        onEnabledStatesChanged?()
    }

    func settingsView(for id: PluginID) -> AnyView {
        registrations[id]?.settingsView() ?? AnyView(EmptyView())
    }

    func paletteScreenPlaceholder(for id: PluginID) -> String? {
        guard isEnabled(id) else { return nil }
        return registrations[id]?.paletteScreen?.placeholder
    }

    func paletteSnapshot(for id: PluginID, query: String) -> PluginPaletteSnapshot? {
        guard isEnabled(id), let screen = registrations[id]?.paletteScreen else { return nil }
        return screen.snapshot(query)
    }

    func performPalettePrimaryAction(pluginID: PluginID, itemID: String) {
        guard isEnabled(pluginID), let screen = registrations[pluginID]?.paletteScreen else { return }
        screen.performPrimaryAction(itemID)
    }

    func paletteActions(pluginID: PluginID, itemID: String) -> PopoverMenuContent? {
        guard isEnabled(pluginID), let screen = registrations[pluginID]?.paletteScreen else {
            return nil
        }
        return screen.actions(itemID)
    }

    func activatePaletteScreen(_ id: PluginID) {
        guard isEnabled(id), let screen = registrations[id]?.paletteScreen else { return }
        guard activePaletteScreen != id else { return }
        if let activePaletteScreen {
            registrations[activePaletteScreen]?.paletteScreen?.onClose()
        }
        activePaletteScreen = id
        screen.onOpen()
    }

    func deactivatePaletteScreen(_ id: PluginID) {
        guard activePaletteScreen == id else { return }
        registrations[id]?.paletteScreen?.onClose()
        activePaletteScreen = nil
    }

    /// Runs only the precomputed enabled-provider array and returns the first claim by registry order.
    func evaluate(_ query: String, now: Date = Date(), calendar: Calendar = .current)
        -> PluginQueryResult?
    {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 256 else { return nil }
        for provider in enabledQueryProviders {
            if let result = provider.evaluate(trimmed, now: now, calendar: calendar) { return result }
        }
        return nil
    }

    func perform(_ key: PluginActionKey) {
        guard isEnabled(key.pluginID),
            let action = registrations[key.pluginID]?.shortcutActions.first(where: { $0.key == key })
        else { return }
        action.perform()
    }

    @discardableResult
    func performCommand(_ commandID: String) -> Bool {
        guard let owner = commandOwners[commandID], isEnabled(owner),
            let command = registrations[owner]?.launcherCommands.first(where: { $0.id == commandID })
        else { return false }
        command.perform()
        return true
    }

    func isCommandEnabled(_ commandID: String) -> Bool {
        commandOwners[commandID].map(isEnabled) ?? true
    }

    func plugins(requiring permission: PluginPermission) -> [PluginMetadata] {
        orderedIDs.compactMap { id in
            guard registrations[id]?.permissions.contains(permission) == true else { return nil }
            return registrations[id]?.metadata
        }
    }

    /// Network consent is excluded by its registration; imports must never grant it.
    func exportedEnabledStates() -> [String: Bool] {
        Dictionary(uniqueKeysWithValues: orderedIDs.compactMap { id in
            guard registrations[id]?.exportsEnabledState == true else { return nil }
            return (id.rawValue, isEnabled(id))
        })
    }

    @discardableResult
    func applyEnabledStates(_ states: [String: Bool]) -> Int {
        var applied = 0
        for (rawID, enabled) in states {
            let id = PluginID(rawValue: rawID)
            guard registrations[id]?.exportsEnabledState == true else { continue }
            setEnabled(enabled, for: id)
            applied += 1
        }
        return applied
    }

    private func rebuildQueryProviders() {
        enabledQueryProviders = orderedIDs.compactMap { id in
            guard isEnabled(id) else { return nil }
            return registrations[id]?.queryProvider
        }
    }

    private func enabledKey(for id: PluginID) -> String {
        "plugin.\(id.rawValue).enabled"
    }
}
