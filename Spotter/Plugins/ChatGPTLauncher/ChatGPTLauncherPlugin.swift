import AppKit
import SwiftUI

extension PluginActionKey {
    static let openChatGPTLauncher = standard(
        pluginID: .chatGPTLauncher, actionID: "open", title: "Send to ChatGPT")
}

@MainActor
enum ChatGPTLauncherPlugin {
    static func registration(core: AppCore) -> PluginRegistration {
        let open: () -> Void = { [weak core] in core?.openChatGPTLauncher() }
        let screen = PluginPaletteScreenRegistration(
            placeholder: "Type a prompt for ChatGPT…",
            snapshot: { query in snapshot(query: query) },
            performPrimaryAction: { [weak core] _ in core?.sendCurrentPromptToChatGPT() },
            actions: { _ in nil })

        return PluginRegistration(
            metadata: PluginMetadata(
                id: .chatGPTLauncher,
                name: "Send to ChatGPT",
                summary:
                    "Open a new chat in the ChatGPT desktop app and send the prompt you type in Spotter.",
                systemImage: "bubble.left.and.bubble.right",
                tint: .green),
            defaultEnabled: true,
            permissions: [.accessibility],
            shortcutActions: [
                PluginActionRegistration(key: .openChatGPTLauncher, perform: open)
            ],
            launcherCommands: [
                PluginCommandRegistration(
                    id: "command:chatgpt-launcher", name: "Send to ChatGPT",
                    systemImage: "bubble.left.and.bubble.right",
                    actionKey: .openChatGPTLauncher, perform: open)
            ],
            paletteScreen: screen,
            onDisable: { [weak core] in
                core?.chatGPTLauncher.cancel()
                if core?.palette.mode == .plugin(.chatGPTLauncher) {
                    core?.palette.prepare(mode: .launcher)
                }
            },
            settingsView: { AnyView(ChatGPTLauncherSettingsView()) })
    }

    private static func snapshot(query: String) -> PluginPaletteSnapshot {
        guard let prompt = ChatGPTPrompt.prepared(query) else {
            return PluginPaletteSnapshot(
                sectionTitle: "ChatGPT", items: [],
                emptyMessage: "Type a prompt, then press ↵")
        }
        return PluginPaletteSnapshot(
            sectionTitle: "ChatGPT",
            items: [
                PluginPaletteItem(
                    id: "prompt",
                    title: prompt,
                    subtitle: "Open a new chat and send this prompt",
                    icon: .symbol("arrow.up.message"),
                    titleLineLimit: 2,
                    primaryActionTitle: "Send to ChatGPT")
            ],
            emptyMessage: "Type a prompt, then press ↵")
    }
}

extension AppCore {
    func openChatGPTLauncher() {
        guard plugins.isEnabled(.chatGPTLauncher) else { return }
        showPalette(mode: .plugin(.chatGPTLauncher))
    }

    func sendCurrentPromptToChatGPT() {
        guard plugins.isEnabled(.chatGPTLauncher),
            let prompt = ChatGPTPrompt.prepared(palette.query),
            let deepLink = ChatGPTPrompt.deepLink(for: prompt)
        else { return }

        guard let applicationURL = NSWorkspace.shared.urlForApplication(toOpen: deepLink),
            Bundle(url: applicationURL)?.bundleIdentifier == ChatGPTPrompt.appBundleIdentifier
        else {
            hud.show(
                title: "ChatGPT for macOS Not Found",
                symbol: "exclamationmark.triangle", isNoOp: true)
            return
        }
        guard Permissions.ensureAccessibility() else {
            hud.show(
                title: "Allow Spotter in Accessibility",
                symbol: "hand.raised", isNoOp: true)
            return
        }

        hidePalette(restoreFocus: false)
        chatGPTLauncher.send(
            prompt: prompt, deepLink: deepLink, applicationURL: applicationURL
        ) { [weak self] outcome in
            switch outcome {
            case .sent:
                break
            case .draftReady:
                self?.hud.show(
                    title: "Draft Ready — Press Return",
                    symbol: "return", isNoOp: true)
            case .appDidNotLaunch:
                AppLog.error("chatgpt-launcher", "ChatGPT did not launch after the deep link opened.")
                self?.hud.show(
                    title: "ChatGPT Did Not Open",
                    symbol: "exclamationmark.triangle", isNoOp: true)
            case .keyboardEventUnavailable:
                AppLog.error("chatgpt-launcher", "Could not create the verified Return key event.")
                self?.hud.show(
                    title: "Draft Ready — Press Return",
                    symbol: "return", isNoOp: true)
            }
        }
    }
}
