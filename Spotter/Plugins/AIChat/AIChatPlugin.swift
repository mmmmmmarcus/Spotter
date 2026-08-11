import AppKit
import NaturalLanguage
import SwiftUI

extension PluginActionKey {
    static let openAIChat = standard(pluginID: .aiChat, actionID: "open", title: "AI Chat")
    // Preserve the original defaults keys so existing Selection Tools bindings survive the move.
    static let translateSelectedText = PluginActionKey(
        pluginID: .aiChat, actionID: "translate", title: "Translate Selected Text",
        defaultsKey: "KeyboardShortcuts_plugin.selection-tools.translate")
    static let defineSelectedText = PluginActionKey(
        pluginID: .aiChat, actionID: "define", title: "Define Selected Text",
        defaultsKey: "KeyboardShortcuts_plugin.selection-tools.define")
    static let checkSelectedTextGrammar = PluginActionKey(
        pluginID: .aiChat, actionID: "grammar", title: "Check Selected Text Grammar",
        defaultsKey: "KeyboardShortcuts_plugin.selection-tools.grammar")
}

@MainActor
enum AIChatPlugin {
    static func registration(core: AppCore) -> PluginRegistration {
        let open: () -> Void = { [weak core] in core?.openAIChat() }
        let runAction: (AIChatSelectionAction) -> Void = { [weak core] action in
            core?.runAIChatSelectionAction(action)
        }
        let runCommand: (AIChatSelectionAction) -> Void = { [weak core] action in
            core?.runAIChatSelectionActionFromLauncher(action)
        }
        return PluginRegistration(
            metadata: PluginMetadata(
                id: .aiChat,
                name: "AI Chat",
                summary:
                    "Chat through OpenRouter or hand a prompt to ChatGPT on the web, plus translate, define, and proofread selected text.",
                systemImage: "sparkles",
                tint: .purple,
                settingsPlacement: .application),
            defaultEnabled: true,
            canDisable: false,
            exportsEnabledState: false,
            permissions: [.accessibility],
            shortcutActions: [
                PluginActionRegistration(key: .openAIChat, perform: open),
                PluginActionRegistration(key: .translateSelectedText) { runAction(.translate) },
                PluginActionRegistration(key: .defineSelectedText) { runAction(.define) },
                PluginActionRegistration(key: .checkSelectedTextGrammar) { runAction(.grammar) },
            ],
            launcherCommands: [
                PluginCommandRegistration(
                    id: "command:ai-chat", name: "AI Chat", systemImage: "sparkles",
                    actionKey: .openAIChat, perform: open),
                PluginCommandRegistration(
                    id: "command:selection-tools:translate",
                    name: "Translate Selected Text",
                    systemImage: "translate",
                    actionKey: .translateSelectedText
                ) { runCommand(.translate) },
                PluginCommandRegistration(
                    id: "command:selection-tools:define",
                    name: "Define Selected Text",
                    systemImage: "character.book.closed",
                    actionKey: .defineSelectedText
                ) { runCommand(.define) },
                PluginCommandRegistration(
                    id: "command:selection-tools:grammar",
                    name: "Check Selected Text Grammar",
                    systemImage: "text.badge.checkmark",
                    actionKey: .checkSelectedTextGrammar
                ) { runCommand(.grammar) },
            ],
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
                message: "This conversation is session-only and will be permanently removed.",
                actionTitle: "Delete"
            ) { [weak self] in
                self?.aiChat.deleteCurrentSession()
            })
    }

    func runAIChatSelectionAction(_ action: AIChatSelectionAction) {
        guard openRouter.isReady else {
            showAIChatSelectionFailure(
                action: action,
                message: "Add an OpenRouter API key in Settings → General → AI to use this action.")
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            presentAIChatSelection(action, capture: await selectedTextCapture.capture())
        }
    }

    func runAIChatSelectionActionFromLauncher(_ action: AIChatSelectionAction) {
        guard openRouter.isReady else {
            showAIChatSelectionFailure(
                action: action,
                message: "Add an OpenRouter API key in Settings → General → AI to use this action.")
            return
        }
        guard palette.mode == .launcher else {
            runAIChatSelectionAction(action)
            return
        }
        hidePalette()
        Task { @MainActor [weak self] in
            guard let self else { return }
            presentAIChatSelection(
                action, capture: await selectedTextCapture.captureAfterRestoringFocus())
        }
    }

    private func presentAIChatSelection(
        _ action: AIChatSelectionAction,
        capture: Result<SelectedTextSnapshot, SelectedTextCaptureFailure>
    ) {
        switch capture {
        case .failure(let error):
            aiChat.showSelectionFailure(action: action, message: error.message)
        case .success(let snapshot):
            let detectedLanguage = action == .translate
                ? NLLanguageRecognizer.dominantLanguage(for: snapshot.text)?.rawValue : nil
            aiChat.startSelectionConversation(
                action: action, text: snapshot.text,
                detectedSourceLanguage: detectedLanguage)
        }
        palette.prepare(mode: .aiChat)
        showPalette(mode: .aiChat)
    }

    private func showAIChatSelectionFailure(
        action: AIChatSelectionAction, message: String
    ) {
        aiChat.showSelectionFailure(action: action, message: message)
        palette.prepare(mode: .aiChat)
        showPalette(mode: .aiChat)
    }
}
