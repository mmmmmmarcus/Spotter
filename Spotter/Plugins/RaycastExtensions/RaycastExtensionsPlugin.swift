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
            dynamicLauncherCommands: { [weak core] in
                guard let core, core.extensions.isEnabled, core.extensions.showsInLauncher else { return [] }
                return core.extensions.installed.flatMap { owner in
                    owner.manifest.commands.map { command in
                        let ref = ExtensionCommandRef(extensionName: owner.manifest.name, commandName: command.name)
                        return PluginCommandRegistration(id: ref.entryID, name: command.title,
                            systemImage: "puzzlepiece.extension", iconFilePath: owner.iconPath, actionKey: key(ref, title: command.title)) {
                                guard let entry = core.extensions.launcherEntry(forEntryID: ref.entryID) else { return }
                                core.extensionCoordinator.runExtensionCommand(entry)
                            }
                    }
                }
            },
            paletteScreen: PluginPaletteScreenRegistration(
                placeholder: "Search extension…",
                canvas: { context in AnyView(RaycastExtensionCanvas(core: core, context: context)) },
                livePlaceholder: { core.extensionCoordinator.screen.searchPlaceholder },
                handleBack: {
                    guard core.extensions.navigationDepth > 1 else { return false }
                    Task { _ = await core.extensions.popNavigation() }
                    return true
                },
                snapshot: { _ in
                    let screen = core.extensionCoordinator.screen
                    let items = screen.items.map(\.node)
                    return PluginPaletteSnapshot(sectionTitle: screen.navigationTitle ?? "Extension",
                        items: items.enumerated().map { index, node in
                            PluginPaletteItem(id: String(index), title: node.string("title") ?? "", subtitle: nil,
                                icon: .symbol("puzzlepiece.extension"), primaryActionTitle: "Run")
                        }, emptyMessage: "")
                },
                performPrimaryAction: { id in activate(core, index: Int(id) ?? 0) },
                actions: { id in
                    let screen = core.extensionCoordinator.screen
                    let actions = ExtensionScreen.actions(in: screen.actionPanel(forItemAt: Int(id) ?? 0))
                    return PopoverMenuContent(header: screen.navigationTitle, items: actions.map { action in
                        PopoverMenuItem(title: [action.enclosingSubmenuTitle, action.title].compactMap { $0 }.joined(separator: " › "), systemImage: "puzzlepiece.extension", shortcut: action.shortcutCaps?.joined(), isDestructive: action.isDestructive) {
                            if let handler = action.handler { core.extensions.dispatch(handler: handler) }
                        }
                    })
                },
                onOpen: { core.extensionCoordinator.beginQuery() },
                onClose: { core.extensionCoordinator.endQuery() },
                observeChanges: { core.extensionCoordinator.observe($0) }),
            onStart: { core.extensionCoordinator.start() },
            settingsView: { AnyView(RaycastExtensionsSettingsView(core: core)) })
    }

    static func activate(_ core: AppCore, index: Int) {
        let screen = core.extensionCoordinator.screen
        if let handler = ExtensionScreen.actions(in: screen.actionPanel(forItemAt: index)).first?.handler {
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
            if let accessory = ExtensionSearchAccessory(node: screen.searchBarAccessory) {
                Picker("Filter", selection: Binding(
                    get: { core.extensions.accessorySelection(accessory) ?? "" },
                    set: { core.extensions.chooseAccessorySelection(accessory, value: $0) })) {
                    ForEach(accessory.items, id: \.value) { Text($0.title).tag($0.value) }
                }.padding(.horizontal, Theme.Spacing.xl)
            }
            ExtensionCommandView(screen: screen, state: core.extensions.state, selection: selected,
                assetsPath: assets, scroll: context.scroll,
                onSelect: { core.palette.selection = $0 }, onActivate: { RaycastExtensionsPlugin.activate(core, index: $0) },
                onActions: { context.actions(String($0)) }, onFieldChange: { node, value in
                    if let handler = node.handler("onTinycastChange") { core.extensions.dispatch(handler: handler, arguments: [value]) }
                })
            if let panel = screen.actionPanel(forItemAt: selected), !panel.children.isEmpty {
                HStack {
                    Spacer()
                    Menu("Actions") { RaycastActionMenu(nodes: panel.children, manager: core.extensions) }
                        .menuStyle(.borderlessButton).fixedSize()
                }.padding(Theme.Spacing.md)
            }
            ForEach(core.extensions.toasts) { toast in
                ExtensionToastPill(toast: toast, onAction: { core.extensions.runToastAction(token: $0) },
                    onDismiss: { core.extensions.hide(toast: toast.id) })
            }
        }
        .environment(core.extensionCoordinator.controls)
        .environment(core.extensions)
        .modifier(ExtensionSelectionForwarder(screen: screen, selection: selected))
    }
}

private struct RaycastActionMenu: View {
    let nodes: [RenderNode]
    let manager: ExtensionManager
    var body: some View {
        ForEach(nodes) { node in
            switch node.type {
            case "Action":
                Button(node.string("title") ?? "Action", role: node.string("style") == "destructive" ? .destructive : nil) {
                    if let handler = node.handler("onAction") { manager.dispatch(handler: handler) }
                }
            case "ActionPanel.Submenu":
                Menu(node.string("title") ?? "Actions") {
                    RaycastActionMenu(nodes: node.children, manager: manager)
                }
            case "ActionPanel.Section":
                Section(node.string("title") ?? "") {
                    RaycastActionMenu(nodes: node.children, manager: manager)
                }
            default: EmptyView()
            }
        }
    }
}
