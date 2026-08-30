import AppKit
import Combine
import SwiftUI

extension PluginActionKey {
    static let openOnePassword = standard(
        pluginID: .onePassword, actionID: "open", title: "Search 1Password")
    static let generateOnePasswordPassword = standard(
        pluginID: .onePassword, actionID: "generate-password", title: "1Password Generate Password")
}

@MainActor
enum OnePasswordPlugin {
    static func registration(core: AppCore) -> PluginRegistration {
        let open: () -> Void = { [weak core] in core?.openOnePassword() }
        let generate: () -> Void = { [weak core] in core?.runOnePasswordGeneratePassword() }
        let screen = PluginPaletteScreenRegistration(
            placeholder: "Search your 1Password items…",
            snapshot: { [weak core] query in
                guard let core else {
                    return PluginPaletteSnapshot(
                        sectionTitle: "1Password", items: [], emptyMessage: "Plugin unavailable")
                }
                return OnePasswordResults.snapshot(manager: core.onePassword, query: query)
            },
            performPrimaryAction: { [weak core] itemID in
                core?.performOnePasswordRow(itemID: itemID)
            },
            performSecondaryAction: { [weak core] itemID in
                guard let core,
                    let item = OnePasswordResults.item(manager: core.onePassword, itemID: itemID),
                    OnePasswordItemAction.available(forCategory: item.category)
                        .contains(.copyPassword)
                else { return }
                core.performOnePasswordAction(.copyPassword, item: item)
            },
            actions: { [weak core] itemID in
                guard let core else { return nil }
                return OnePasswordResults.menu(core: core, itemID: itemID)
            },
            // No onClose: an in-flight `op` read keeps running while the palette hides for
            // 1Password's authorization window — see OnePasswordManager.
            onOpen: { [weak core] in core?.onePassword.open() },
            observeChanges: { [weak core] invalidate in
                core?.onePassword.objectWillChange.sink { invalidate() } ?? AnyCancellable {}
            })

        return PluginRegistration(
            metadata: PluginMetadata(
                id: .onePassword,
                name: "1Password",
                summary:
                    "Search 1Password items in the launcher, then open, copy or paste through the 1Password CLI.",
                systemImage: "key.fill",
                tint: .blue),
            defaultEnabled: true,
            permissions: [.accessibility],
            shortcutActions: [
                PluginActionRegistration(key: .openOnePassword, perform: open),
                PluginActionRegistration(key: .generateOnePasswordPassword, perform: generate),
            ],
            launcherCommands: [
                PluginCommandRegistration(
                    id: "command:1password", name: "Search 1Password",
                    systemImage: "key.fill", actionKey: .openOnePassword, perform: open),
                PluginCommandRegistration(
                    id: "command:1password-generate-password", name: "Generate Password",
                    systemImage: "wand.and.stars", actionKey: .generateOnePasswordPassword,
                    defaultVisible: false, perform: generate),
            ],
            paletteScreen: screen,
            onDisable: { [weak core] in
                core?.onePassword.reset()
                if core?.palette.mode == .plugin(.onePassword) {
                    core?.palette.prepare(mode: .launcher)
                }
            },
            settingsView: { AnyView(OnePasswordSettingsView()) })
    }
}

/// Turns manager state into palette rows. Pure mapping — no I/O — so the screen stays a snapshot.
@MainActor
enum OnePasswordResults {
    static let installGuideURL = "https://developer.1password.com/docs/cli/get-started/"

    static func snapshot(manager: OnePasswordManager, query: String) -> PluginPaletteSnapshot {
        guard manager.isInstalled else {
            return PluginPaletteSnapshot(
                sectionTitle: "1Password", items: [installRow()],
                emptyMessage: "1Password CLI not found")
        }
        switch manager.state {
        case .idle, .loading:
            return PluginPaletteSnapshot(
                sectionTitle: "1Password", items: [], isLoading: true,
                loadingMessage: "Waiting for 1Password — approve its prompt if one appeared…",
                emptyMessage: "Waiting for 1Password…")
        case .locked(let message):
            return PluginPaletteSnapshot(
                sectionTitle: "1Password", items: [unlockRow(message: message)],
                emptyMessage: "1Password is locked")
        case .failed(let message):
            return PluginPaletteSnapshot(
                sectionTitle: "1Password", items: [retryRow(message: message)],
                emptyMessage: "Couldn't reach 1Password")
        case .items(let items):
            let visible = OnePasswordParser.filtered(items, query: query)
            return PluginPaletteSnapshot(
                sectionTitle: "1Password", items: visible.map(itemRow),
                isLoading: manager.isRefreshing,
                loadingMessage: "Refreshing items…",
                emptyMessage: items.isEmpty ? "No items in 1Password" : "No matching item")
        }
    }

    // MARK: - Rows

    private static func installRow() -> PluginPaletteItem {
        PluginPaletteItem(
            id: "install",
            title: "1Password CLI not found",
            subtitle: "Install it with `brew install 1password-cli`, or set its path in Settings.",
            icon: .symbol("exclamationmark.triangle"),
            subtitleLineLimit: 2,
            primaryActionTitle: "Open Install Guide")
    }

    private static func retryRow(message: String) -> PluginPaletteItem {
        PluginPaletteItem(
            id: "retry",
            title: "Couldn't reach 1Password",
            subtitle: message,
            icon: .symbol("arrow.clockwise"),
            subtitleLineLimit: 2,
            primaryActionTitle: "Try Again")
    }

    private static func unlockRow(message: String) -> PluginPaletteItem {
        PluginPaletteItem(
            id: "unlock",
            title: "Unlock 1Password",
            subtitle: message,
            icon: .symbol("lock.fill"),
            subtitleLineLimit: 2,
            primaryActionTitle: "Unlock")
    }

    private static func itemRow(_ item: OnePasswordItem) -> PluginPaletteItem {
        var accessories: [PluginPaletteAccessory] = []
        if item.isFavorite {
            accessories.append(PluginPaletteAccessory(systemImage: "star.fill", text: ""))
        }
        if !item.vaultName.isEmpty {
            accessories.append(
                PluginPaletteAccessory(systemImage: "square.stack.3d.up", text: item.vaultName))
        }
        return PluginPaletteItem(
            id: item.id,
            title: item.title,
            subtitle: item.username ?? OnePasswordCategory.label(for: item.category),
            icon: .symbol(OnePasswordCategory.symbol(for: item.category)),
            accessories: accessories,
            primaryActionTitle: primaryAction(for: item).title)
    }

    static func primaryAction(for item: OnePasswordItem) -> OnePasswordItemAction {
        let preferred = OnePasswordItemAction(
            rawValue: UserDefaults.standard.string(forKey: OnePasswordManager.primaryActionKey)
                ?? "") ?? .openInApp
        return .primary(preferred: preferred, category: item.category)
    }

    // MARK: - Item lookup

    static func item(manager: OnePasswordManager, itemID: String) -> OnePasswordItem? {
        guard case .items(let items) = manager.state else { return nil }
        return items.first { $0.id == itemID }
    }

    // MARK: - Actions menu

    static func menu(core: AppCore, itemID: String) -> PopoverMenuContent? {
        let manager = core.onePassword
        var items: [PopoverMenuItem] = []
        var header = "1Password"

        if let item = item(manager: manager, itemID: itemID) {
            header = item.title
            let primary = primaryAction(for: item)
            for action in OnePasswordItemAction.available(forCategory: item.category) {
                items.append(
                    PopoverMenuItem(
                        title: action.title, systemImage: action.systemImage,
                        shortcut: action == primary ? "↵" : nil
                    ) { core.performOnePasswordAction(action, item: item) })
            }
        }

        items.append(
            PopoverMenuItem(title: "Refresh Items", systemImage: "arrow.clockwise") {
                manager.refresh()
            })
        items.append(
            PopoverMenuItem(title: "1Password Settings…", systemImage: "gearshape") {
                core.hidePalette(restoreFocus: false)
                core.showSettings(plugin: .onePassword)
            })
        return PopoverMenuContent(header: header, items: items)
    }
}

extension AppCore {
    func openOnePassword() {
        guard plugins.isEnabled(.onePassword) else { return }
        showPalette(mode: .plugin(.onePassword))
    }

    func performOnePasswordRow(itemID: String) {
        guard plugins.isEnabled(.onePassword) else { return }
        if itemID == "install" {
            hidePalette(restoreFocus: false)
            if let url = URL(string: OnePasswordResults.installGuideURL) {
                NSWorkspace.shared.open(url)
            }
            return
        }
        if itemID == "unlock" || itemID == "retry" {
            // Re-running the list read is what makes the 1Password app raise its unlock prompt.
            onePassword.refresh()
            return
        }
        guard let item = OnePasswordResults.item(manager: onePassword, itemID: itemID) else {
            return
        }
        performOnePasswordAction(OnePasswordResults.primaryAction(for: item), item: item)
    }

    func performOnePasswordAction(_ action: OnePasswordItemAction, item: OnePasswordItem) {
        guard plugins.isEnabled(.onePassword) else { return }
        switch action {
        case .openInApp:
            hidePalette(restoreFocus: false)
            let url = OnePasswordCLI.viewItemURL(
                accountID: onePassword.accountID, vaultID: item.vaultID, itemID: item.id)
            if let url = URL(string: url) { NSWorkspace.shared.open(url) }
        case .openInBrowser:
            guard let website = item.websiteURL, let url = URL(string: website) else {
                hud.show(title: "No Website on This Item", symbol: "safari", isNoOp: true)
                return
            }
            hidePalette(restoreFocus: false)
            NSWorkspace.shared.open(url)
        case .copyUsername, .copyPassword, .copyOneTimePassword,
            .pasteUsername, .pastePassword, .pasteOneTimePassword:
            revealAndDeliver(action, item: item)
        }
    }

    /// Fetch the secret only now, hand it straight to the pasteboard concealed, and never keep it.
    private func revealAndDeliver(_ action: OnePasswordItemAction, item: OnePasswordItem) {
        let previous = action.isPaste ? previousApplication : nil
        hidePalette(restoreFocus: false)
        let fieldName = action.isOneTimePassword
            ? "One-Time Password" : (action.field == "username" ? "Username" : "Password")
        Task { [weak self] in
            guard let self else { return }
            switch await self.onePassword.revealSecret(item: item, action: action) {
            case .success(let value):
                guard !value.isEmpty else {
                    self.hud.show(
                        title: "No \(fieldName) on This Item", symbol: "key", isNoOp: true)
                    return
                }
                if action.isPaste {
                    Paster.pasteConcealedString(value, previousApp: previous)
                    self.hud.show(title: "Pasted \(fieldName)", symbol: "key.fill")
                } else {
                    Paster.copyConcealedString(value)
                    self.hud.show(title: "Copied \(fieldName)", symbol: "key.fill")
                }
                // Both paths leave the secret on the pasteboard, so both arm the delayed clear.
                self.onePassword.scheduleClipboardClear()
            case .failure(let error):
                AppLog.error("1password", "\(action.title) failed: \(error.message)")
                self.hud.show(
                    title: error.isLocked ? "1Password Is Locked" : "\(action.title) Failed",
                    symbol: "exclamationmark.triangle", isNoOp: true)
            }
        }
    }

    func runOnePasswordGeneratePassword() {
        guard plugins.isEnabled(.onePassword) else { return }
        hidePalette(restoreFocus: false)
        let defaults = UserDefaults.standard
        let length = defaults.object(forKey: OnePasswordManager.passwordLengthKey) == nil
            ? 20 : defaults.integer(forKey: OnePasswordManager.passwordLengthKey)
        let digits = defaults.object(forKey: OnePasswordManager.passwordDigitsKey) == nil
            || defaults.bool(forKey: OnePasswordManager.passwordDigitsKey)
        let symbols = defaults.object(forKey: OnePasswordManager.passwordSymbolsKey) == nil
            || defaults.bool(forKey: OnePasswordManager.passwordSymbolsKey)
        Task { [weak self] in
            guard let self else { return }
            switch await self.onePassword.generatePassword(
                length: length, digits: digits, symbols: symbols)
            {
            case .success(let password):
                Paster.copyConcealedString(password)
                self.onePassword.scheduleClipboardClear()
                self.hud.show(title: "Password Copied", symbol: "key.fill")
            case .failure(let error):
                AppLog.error("1password", "Generate password failed: \(error.message)")
                self.hud.show(
                    title: "Couldn't Generate Password",
                    symbol: "exclamationmark.triangle", isNoOp: true)
            }
        }
    }
}
