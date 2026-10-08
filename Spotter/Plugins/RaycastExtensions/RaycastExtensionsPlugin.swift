import AppKit
import Combine
import SwiftUI

@MainActor
enum RaycastExtensionsPlugin {
    static func key(_ ref: ExtensionCommandRef, title: String) -> PluginActionKey {
        .standard(pluginID: .raycastExtensions, actionID: ref.entryID, title: title)
    }

    static func registration(core: AppCore) -> PluginRegistration {
        PluginRegistration(
            metadata: PluginMetadata(id: .raycastExtensions, name: "Raycast Extensions",
                summary: "Install and run Raycast extensions with a native interface.", systemImage: "puzzlepiece.extension", tint: .purple),
            dynamicShortcutActions: {
                guard core.extensions.isEnabled else { return [] }
                return core.extensions.installed.flatMap { owner in owner.manifest.commands.map { command in
                    let ref = ExtensionCommandRef(extensionName: owner.id, commandName: command.name)
                    return PluginActionRegistration(key: key(ref, title: command.title)) {
                        guard let entry = core.extensions.launcherEntry(forEntryID: ref.entryID) else { return }
                        core.extensionCoordinator.runExtensionCommand(entry)
                    }
                } }
            },
            launcherCommands: [PluginCommandRegistration(
                id: "command:raycast-extensions:manage", name: "Raycast extension store",
                systemImage: "puzzlepiece.extension") { core.extensionCoordinator.openStore() }],
            dynamicLauncherCommands: { [weak core] in
                guard let core, core.extensions.isEnabled, core.extensions.showsInLauncher else { return [] }
                return core.extensions.installed.flatMap { owner in
                    owner.manifest.commands.map { command in
                        let ref = ExtensionCommandRef(extensionName: owner.manifest.name, commandName: command.name)
                        return PluginCommandRegistration(id: ref.entryID, name: command.title,
                            systemImage: "puzzlepiece.extension", iconFilePath: core.extensions.launcherEntry(forEntryID: ref.entryID)?.iconFilePath, actionKey: key(ref, title: command.title),
                            alternateNames: command.launcherSearchNames(extensionTitle: owner.title, extensionName: owner.id),
                            detailLabel: owner.title) {
                                guard let entry = core.extensions.launcherEntry(forEntryID: ref.entryID) else { return }
                                core.extensionCoordinator.runExtensionCommand(entry)
                            }
                    }
                }
            },
            paletteScreen: PluginPaletteScreenRegistration(
                placeholder: "Search extension…",
                canvas: { context in core.extensionCoordinator.isBrowsingStore ? nil : AnyView(RaycastExtensionCanvas(core: core, context: context)) },
                livePlaceholder: { core.extensionCoordinator.isBrowsingStore ? "Search Raycast Store or paste a GitHub extension URL…" : core.extensionCoordinator.screen.searchPlaceholder },
                handleBack: {
                    guard !core.extensionCoordinator.isBrowsingStore, core.extensions.navigationDepth > 1 else { return false }
                    Task { _ = await core.extensions.popNavigation() }
                    return true
                },
                snapshot: { query in
                    if core.extensionCoordinator.isBrowsingStore { return core.raycastStore.snapshot(query: query) }
                    let screen = core.extensionCoordinator.screen
                    let items = screen.items.map(\.node)
                    return PluginPaletteSnapshot(sectionTitle: screen.navigationTitle ?? "Extension",
                        items: items.enumerated().map { index, node in
                            PluginPaletteItem(id: String(index), title: node.string("title") ?? "", subtitle: nil,
                                icon: .symbol("puzzlepiece.extension"), primaryActionTitle: screen.primaryActionTitle(at: index))
                        }, emptyMessage: "")
                },
                performPrimaryAction: { id in
                    if core.extensionCoordinator.isBrowsingStore { core.raycastStore.activate(id, query: core.palette.query) }
                    else { activate(core, index: Int(id) ?? 0) }
                },
                actions: { id in
                    if core.extensionCoordinator.isBrowsingStore { return nil }
                    let screen = core.extensionCoordinator.screen
                    let actions = core.extensionCoordinator.actions(at: Int(id) ?? 0, query: core.palette.menuTypeaheadQuery)
                    return PopoverMenuContent(header: screen.navigationTitle, items: actions.map { action in
                        PopoverMenuItem(title: [action.enclosingSubmenuTitle, action.title].compactMap { $0 }.joined(separator: " › "), systemImage: "puzzlepiece.extension", shortcut: action.shortcutCaps?.joined(), isDestructive: action.isDestructive) {
                            if let handler = action.handler { core.extensions.dispatch(handler: handler) }
                        }
                    })
                },
                onOpen: { core.extensionCoordinator.beginQuery() },
                onClose: { core.extensionCoordinator.endQuery() },
                observeChanges: { core.extensionCoordinator.observe($0) }),
            onStart: { core.extensionCoordinator.start() })
    }

    static func activate(_ core: AppCore, index: Int) {
        let screen = core.extensionCoordinator.screen
        guard let primary = screen.primaryAction(at: index) else { return }
        if primary.enclosingSubmenuTitle != nil {
            core.palette.selection = index
            core.extensionCoordinator.actionsRequest = UUID()
        } else if let handler = primary.handler {
            core.extensions.dispatch(handler: handler)
        }
    }
}

private struct RaycastExtensionCanvas: View {
    let core: AppCore
    let context: PluginPaletteCanvasContext
    var body: some View {
        let screen = core.extensionCoordinator.screen
        let selected = Int(context.selectedID ?? "0") ?? 0
        let assets = core.extensions.running.flatMap { core.extensions.extensionNamed($0.extensionName)?.assetsPath }
        VStack(spacing: 0) {
            if core.extensionCoordinator.pendingArguments != nil {
                EmptyResults(text: "Enter the command arguments above, then press Return.")
            } else if core.extensions.isAuthorizing {
                EmptyResults(text: "Finish signing in to the extension in your browser.")
            } else {
                ExtensionCommandView(screen: screen, state: core.extensions.state, selection: selected,
                assetsPath: assets, scroll: context.scroll,
                onSelect: { core.palette.selection = $0 }, onActivate: { RaycastExtensionsPlugin.activate(core, index: $0) },
                onActions: { context.actions(String($0)) }, onFieldChange: { node, value in
                    if let handler = node.handler("onTinycastChange") { core.extensions.dispatch(handler: handler, arguments: [value]) }
                })
            }
            ForEach(core.extensions.toasts) { toast in
                ExtensionToastPill(toast: toast, onAction: { core.extensions.runToastAction(token: $0) },
                    onDismiss: { core.extensions.hide(toast: toast.id) })
            }
        }
        .modifier(ExtensionSelectionForwarder(screen: screen, selection: selected))
        .environment(core.extensionCoordinator.controls)
        .environment(core.extensions)
    }
}


struct RaycastSearchAccessory: View {
    let core: AppCore

    var body: some View {
        if let accessory = ExtensionSearchAccessory(node: core.extensionCoordinator.screen.searchBarAccessory), !accessory.items.isEmpty {
            Picker(accessory.tooltip ?? "Filter", selection: Binding(
                get: { core.extensions.accessorySelection(accessory) ?? "" },
                set: { core.extensions.chooseAccessorySelection(accessory, value: $0) })) {
                ForEach(accessory.items, id: \.value) { Text($0.title).tag($0.value) }
            }
            .labelsHidden()
            .fixedSize()
        }
    }
}

struct RaycastArgumentsHeader: View {
    @ObservedObject var coordinator: ExtensionCoordinator
    @FocusState private var focused: String?

    var body: some View {
        if let pending = coordinator.pendingArguments {
            CommandArgumentsRow(arguments: pending.command.arguments, icon: nil,
                value: { name in Binding(get: { coordinator.argumentValues[name] ?? "" }, set: { coordinator.argumentValues[name] = $0 }) },
                focused: $focused, onSubmit: { coordinator.submitArguments() })
                .frame(maxWidth: .infinity, alignment: .leading)
                .onAppear { focused = coordinator.argumentFocus }
                .onChange(of: coordinator.argumentFocus) { focused = coordinator.argumentFocus }
                .onChange(of: focused) { coordinator.argumentFocus = focused }
        }
    }
}
