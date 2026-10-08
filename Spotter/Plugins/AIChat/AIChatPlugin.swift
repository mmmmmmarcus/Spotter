import AppKit
import Carbon.HIToolbox
import SwiftUI

extension PluginActionKey {
    static let openAIChat = standard(pluginID: .aiChat, actionID: "open", title: "AI Chat")
    static let quickAIChat = standard(pluginID: .aiChat, actionID: "quick-chat", title: "Quick AI Chat")
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
                    "Chat through OpenRouter, use MCP and Cua tools, or define and proofread selected text.",
                systemImage: "sparkles",
                tint: .purple,
                settingsPlacement: .system),
            permissions: [.accessibility],
            shortcutActions: [
                PluginActionRegistration(key: .openAIChat, perform: open),
                PluginActionRegistration(key: .quickAIChat,
                    defaultShortcut: KeyShortcut(carbonKeyCode: Int(kVK_Space), carbonModifiers: optionKey)) { [weak core] in
                    core?.toggleQuickAIChat()
                }
            ],
            launcherCommands: [
                PluginCommandRegistration(
                    id: "command:ai-chat", name: "AI Chat", systemImage: "sparkles",
                    actionKey: .openAIChat, perform: open),
                PluginCommandRegistration(
                    id: "command:quick-ai-chat", name: "Quick AI Chat", systemImage: "sparkles",
                    actionKey: .quickAIChat) { [weak core] in core?.toggleQuickAIChat() }
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
            settingsView: { AnyView(AIChatSettingsView()) })
    }
}

extension AppCore {
    func chooseAIChatAttachments() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Choose images, PDFs, source files or text documents to include with your next message."
        let response = panel.runModal()
        guard response == .OK else { return }
        Task { [weak self] in
            guard let self else { return }
            let batch = await AIChatAttachmentReader.read(panel.urls)
            let failures = batch.failures + aiChat.addPendingAttachments(batch.attachments)
            if !failures.isEmpty {
                let alert = NSAlert()
                alert.messageText = "Some attachments could not be added"
                alert.informativeText = failures.joined(separator: "\n")
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    func openAIChat() {
        showQuickAIChat()
    }

    func openAIChat(sessionID: UUID) {
        showQuickAIChat(sessionID: sessionID)
    }

    func openAIChat(draft: String) {
        quickAIChat.newConversation()
        quickAIChat.draft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        showQuickAIChat()
    }

    func startAIChat(prompt: String) {
        openAIChat(draft: prompt)
        quickAIChat.submit()
    }

    func confirmDeleteAIChatSession(_ id: UUID) {
        guard let session = aiChat.sessions.first(where: { $0.id == id }) else { return }
        quickAIChat.hide(restoreFocus: true)
        confirmInPalette(PaletteConfirmation(
            title: "Delete \(session.title)?",
            message: "This conversation will be permanently removed from synced Spotter data.",
            actionTitle: "Delete", onCancel: { [weak self] in self?.showQuickAIChat() }
        ) { [weak self] in
            guard let self else { return }
            quickAIChat.deleteSession(id)
            showQuickAIChat()
        })
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

    /// The one funnel for an AI command's global shortcut. The key is the gate: with none, the
    /// command reports that instead of capturing anything.
    func runAICommand(id: UUID) {
        guard let command = aiCommands.command(id: id) else { return }
        guard aiChat.isReady else {
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
        guard aiChat.isReady else {
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
        "Configure OpenRouter or install Claude/Codex CLI in Settings → AI Chat & Command to use this command."

    private func presentAICommand(
        _ command: AICommand,
        capture: Result<SelectedTextSnapshot, SelectedTextCaptureFailure>
    ) {
        let sessionID: UUID
        switch capture {
        case .failure(let error):
            sessionID = aiChat.showCommandFailure(command: command, message: error.message,
                selectSession: false)
        case .success(let snapshot):
            sessionID = aiChat.startCommandConversation(command: command, selection: snapshot.text,
                selectSession: false)
        }
        showAICommandSession(sessionID)
    }

    private func showAICommandFailure(_ command: AICommand, message: String) {
        let sessionID = aiChat.showCommandFailure(command: command, message: message,
            selectSession: false)
        showAICommandSession(sessionID)
    }

    private func showAICommandSession(_ sessionID: UUID) {
        showQuickAIChat(sessionID: sessionID)
    }
}
