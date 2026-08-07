import AppKit
import SwiftUI

extension PluginActionKey {
    static let openAIChat = standard(pluginID: .aiChat, actionID: "open", title: "AI Chat")
}

@MainActor
enum AIChatPlugin {
    static func registration(core: AppCore) -> PluginRegistration {
        let open: () -> Void = { [weak core] in core?.openAIChat() }
        return PluginRegistration(
            metadata: PluginMetadata(
                id: .aiChat,
                name: "AI Chat",
                summary:
                    "Chat with an AI right in the palette — Tab from the launcher, ask, and keep the conversation going. Uses your OpenRouter key.",
                systemImage: "sparkles",
                tint: .purple),
            defaultEnabled: true,
            shortcutActions: [PluginActionRegistration(key: .openAIChat, perform: open)],
            launcherCommands: [
                PluginCommandRegistration(
                    id: "command:ai-chat", name: "AI Chat", systemImage: "sparkles",
                    actionKey: .openAIChat, perform: open)
            ],
            onDisable: { [weak core] in
                core?.aiChat.stop()
                if core?.palette.mode == .aiChat {
                    core?.palette.prepare(mode: .launcher)
                }
            },
            settingsView: { AnyView(AIChatSettingsView()) })
    }
}

/// The chat mode's ⌘K menu — fixed content, since the transcript has no row selection.
@MainActor
enum AIChatActionsMenu {
    static func content(core: AppCore) -> PopoverMenuContent {
        var items: [PopoverMenuItem] = []
        if core.aiChat.phase == .waiting {
            items.append(
                PopoverMenuItem(title: "Stop Waiting", systemImage: "stop.circle") {
                    core.aiChat.stop()
                })
        }
        if let reply = core.aiChat.lastAssistantReply {
            items.append(
                PopoverMenuItem(title: "Copy Last Reply", systemImage: "doc.on.doc") {
                    core.hidePalette(restoreFocus: false)
                    Paster.copyPlainText(reply)
                })
        }
        if !core.aiChat.messages.isEmpty {
            items.append(
                PopoverMenuItem(title: "Copy Conversation", systemImage: "doc.on.clipboard") {
                    core.hidePalette(restoreFocus: false)
                    Paster.copyPlainText(core.aiChat.transcript)
                })
            items.append(
                PopoverMenuItem(
                    title: "New Session", systemImage: "square.and.pencil", shortcut: "⌘N"
                ) { core.aiChat.startNewSession() })
            items.append(
                PopoverMenuItem(
                    title: "Delete Session", systemImage: "trash", isDestructive: true
                ) { core.aiChat.deleteCurrentSession() })
        }
        items.append(
            PopoverMenuItem(
                title: core.openRouter.chatWebSearch ? "Web Search: On" : "Web Search: Off",
                systemImage: "globe"
            ) { core.openRouter.setChatWebSearch(!core.openRouter.chatWebSearch) })
        items.append(
            PopoverMenuItem(title: "AI Chat Settings…", systemImage: "gearshape") {
                core.hidePalette(restoreFocus: false)
                core.showSettings(plugin: .aiChat)
            })
        return PopoverMenuContent(header: "AI Chat", items: items)
    }
}

/// The bottom-left menu in chat mode: the session list, newest first, plus New Session — the same
/// role the notes list plays for Notes.
@MainActor
enum AIChatSessionsMenu {
    static func content(core: AppCore) -> PopoverMenuContent {
        var items = [
            PopoverMenuItem(
                title: "New Session", systemImage: "square.and.pencil", shortcut: "⌘N"
            ) { core.aiChat.startNewSession() }
        ]
        items += core.aiChat.orderedSessions.prefix(12).map { session in
            PopoverMenuItem(
                title: session.title,
                systemImage: session.id == core.aiChat.currentID
                    ? "checkmark.circle.fill" : "bubble.left"
            ) { core.aiChat.switchTo(session.id) }
        }
        return PopoverMenuContent(header: "Sessions", items: items)
    }
}

extension AppCore {
    func openAIChat() {
        guard plugins.isEnabled(.aiChat) else { return }
        showPalette(mode: .aiChat)
    }
}
