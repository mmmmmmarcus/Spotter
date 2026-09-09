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
                name: "AI Chat & Command",
                summary:
                    "Chat through OpenRouter or hand a prompt to ChatGPT on the web, plus define and proofread selected text.",
                systemImage: "sparkles",
                tint: .purple,
                settingsPlacement: .system),
            defaultEnabled: true,
            canDisable: false,
            exportsEnabledState: false,
            permissions: [.accessibility],
            shortcutActions: [
                PluginActionRegistration(key: .openAIChat, perform: open)
            ],
            launcherCommands: [
                PluginCommandRegistration(
                    id: "command:ai-chat", name: "AI Chat", systemImage: "sparkles",
                    actionKey: .openAIChat, perform: open)
            ],
            // Every AI command, shipped or user-authored, is a launcher entry that resolves its own
            // recorder through `AppEntry.hotKeyAction` — the shape custom commands and quicklinks use.
            dynamicLauncherCommands: { [weak core] in
                (core?.aiCommands.commands ?? []).map { command in
                    PluginCommandRegistration(
                        id: command.entryID, name: command.name,
                        systemImage: command.systemImage
                    ) { [weak core] in core?.runAICommandFromLauncher(id: command.id) }
                }
            },
            readEnabled: { true },
            settingsView: { AnyView(AIChatSettingsView()) })
    }
}

/// The chat mode's ⌘K menu — fixed content, since the transcript has no row selection.
@MainActor
enum AIChatActionsMenu {
    static func content(core: AppCore) -> PopoverMenuContent {
        var items: [PopoverMenuItem] = []
        if core.aiChat.isWaiting {
            items.append(
                PopoverMenuItem(title: "Stop Waiting", systemImage: "stop.circle") {
                    core.aiChat.stop()
                })
        }
        // The web handoff is an action on the draft, so it lives here rather than in the footer.
        // Sampled when the menu opens, which is exactly when typing is frozen, so it can't go stale.
        let draft = core.palette.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !draft.isEmpty {
            items.append(
                PopoverMenuItem(title: "Send to ChatGPT", systemImage: "globe") {
                    if core.sendAIChatPromptToChatGPT(draft) { core.palette.query = "" }
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
                ) { core.confirmDeleteAIChatSession() })
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
        showPalette(mode: .aiChat)
    }

    /// Return on a running AI row: back into the conversation that is waiting.
    func openAIChat(sessionID: UUID) {
        aiChat.switchTo(sessionID)
        palette.prepare(mode: .aiChat)
        showPalette(mode: .aiChat)
    }

    /// Enter chat with the draft in the composer, unsent — Tab's carry-in path.
    func openAIChat(draft: String) {
        aiChat.startNewSession()
        palette.mode = .aiChat
        palette.query = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func startAIChat(prompt rawPrompt: String) {
        aiChat.startNewSession()
        palette.mode = .aiChat
        let prompt = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        palette.query = prompt
        if !prompt.isEmpty, aiChat.send(prompt) { palette.query = "" }
    }

    @discardableResult
    func sendAIChatPromptToChatGPT(_ prompt: String) -> Bool {
        guard let url = AIChatEngine.chatGPTURL(for: prompt) else { return false }
        guard NSWorkspace.shared.open(url) else {
            AppLog.error("ai-chat", "The ChatGPT web URL could not be opened.")
            hud.show(
                title: "Could Not Open ChatGPT", symbol: "exclamationmark.triangle", isNoOp: true)
            return false
        }
        hidePalette(restoreFocus: false)
        return true
    }

    func confirmDeleteAIChatSession() {
        let title = aiChat.current.title
        confirmInPalette(
            PaletteConfirmation(
                title: "Delete \(title)?",
                message: "This conversation will be permanently removed from synced Spotter data.",
                actionTitle: "Delete"
            ) { [weak self] in
                self?.aiChat.deleteCurrentSession()
            })
    }

    /// The one funnel for an AI command's global shortcut. The key is the gate: with none, the
    /// command reports that instead of capturing anything.
    func runAICommand(id: UUID) {
        guard let command = aiCommands.command(id: id) else { return }
        guard openRouter.isReady else {
            showAICommandFailure(command, message: Self.aiCommandKeyMessage)
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            presentAICommand(command, capture: await selectedTextCapture.capture())
        }
    }

    /// The launcher row's path: the palette dismisses first so the capture reads the app the user
    /// came from, not Spotter.
    func runAICommandFromLauncher(id: UUID) {
        guard let command = aiCommands.command(id: id) else { return }
        guard openRouter.isReady else {
            showAICommandFailure(command, message: Self.aiCommandKeyMessage)
            return
        }
        guard palette.mode == .launcher else {
            runAICommand(id: id)
            return
        }
        hidePalette()
        Task { @MainActor [weak self] in
            guard let self else { return }
            presentAICommand(
                command, capture: await selectedTextCapture.captureAfterRestoringFocus())
        }
    }

    private static let aiCommandKeyMessage =
        "Add an OpenRouter API key in Settings → AI Chat & Command to use this command."

    private func presentAICommand(
        _ command: AICommand,
        capture: Result<SelectedTextSnapshot, SelectedTextCaptureFailure>
    ) {
        switch capture {
        case .failure(let error):
            aiChat.showCommandFailure(command: command, message: error.message)
        case .success(let snapshot):
            aiChat.startCommandConversation(command: command, selection: snapshot.text)
        }
        palette.prepare(mode: .aiChat)
        showPalette(mode: .aiChat)
    }

    private func showAICommandFailure(_ command: AICommand, message: String) {
        aiChat.showCommandFailure(command: command, message: message)
        palette.prepare(mode: .aiChat)
        showPalette(mode: .aiChat)
    }
}
