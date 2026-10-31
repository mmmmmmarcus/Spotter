import AppKit
import Carbon.HIToolbox
import SwiftUI

extension PluginActionKey {
    static let openAIChat = standard(pluginID: .aiChat, actionID: "open", title: "AI Chat")
    static let quickAIChat = standard(pluginID: .aiChat, actionID: "quick-chat", title: "Quick AI Chat")
}

@MainActor
enum AIChatPlugin {
    static func defaultCommandShortcuts(includesShift: Bool) -> [(UUID, KeyShortcut)] {
        let modifiers = controlKey | optionKey | cmdKey | (includesShift ? shiftKey : 0)
        return [
            (AIBuiltInCommand.spelling.id, KeyShortcut(carbonKeyCode: Int(kVK_ANSI_F), carbonModifiers: modifiers)),
            (AIBuiltInCommand.pronunciation.id, KeyShortcut(carbonKeyCode: Int(kVK_ANSI_P), carbonModifiers: modifiers))
        ]
    }

    static func migrateSpellingShortcut(hotKeys: HotKeyManager, defaults: UserDefaults = .standard) {
        let marker = "ai-commands.spelling-hyper-f-migrated"
        guard !defaults.bool(forKey: marker) else { return }
        defer { defaults.set(true, forKey: marker) }
        let action = HotKeyAction.aiCommand(id: AIBuiltInCommand.spelling.id)
        guard let current = hotKeys.shortcut(for: action), current.carbonKeyCode == kVK_ANSI_W,
              [controlKey | optionKey | cmdKey, controlKey | optionKey | cmdKey | shiftKey].contains(current.carbonModifiers)
        else { return }
        let replacement = KeyShortcut(carbonKeyCode: Int(kVK_ANSI_F), carbonModifiers: current.carbonModifiers)
        guard hotKeys.conflictOwner(of: replacement, excluding: action) == nil else {
            AppLog.info("ai-chat", "Kept the spelling shortcut because Hyper+F is already assigned.")
            return
        }
        hotKeys.setShortcut(replacement, for: action)
    }

    static func registration(core: AppCore) -> PluginRegistration {
        let open: () -> Void = { [weak core] in core?.openAIChat() }
        return PluginRegistration(
            metadata: PluginMetadata(
                id: .aiChat,
                name: "AI Chat & Command",
                summary:
                    "Chat through OpenRouter, use MCP and Cua tools, or define, proofread and pronounce selected text.",
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
        if command.replacesSelection { AppLog.info("ai-spelling", "Command dispatched.") }
        guard aiChat.isReady else {
            showAICommandFailure(command, message: Self.aiCommandKeyMessage)
            return
        }
        captureAICommand(command, restoringFocus: false)
    }

    /// The launcher row's path: the palette dismisses first so the capture reads the app the user
    /// came from, not Spotter.
    func runAICommandFromLauncher(id: UUID) {
        guard let command = aiCommands.command(id: id) else { return }
        if command.replacesSelection { AppLog.info("ai-spelling", "Command dispatched.") }
        guard aiChat.isReady else {
            showAICommandFailure(command, message: Self.aiCommandKeyMessage)
            return
        }
        guard palette.mode == .launcher else {
            runAICommand(id: id)
            return
        }
        hidePalette()
        captureAICommand(command, restoringFocus: true)
    }

    private func captureAICommand(_ command: AICommand, restoringFocus: Bool) {
        let previous = aiCommandCaptureTask
        previous?.cancel()
        aiChat.stop()
        aiCommandCaptureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await previous?.value
            _ = await aiCommandCleanupTask?.value
            guard !Task.isCancelled else { return }
            let capture = restoringFocus
                ? await selectedTextCapture.captureAfterRestoringFocus()
                : await selectedTextCapture.capture()
            guard !Task.isCancelled else { return }
            await presentAICommand(command, capture: capture)
        }
    }

    private static let aiCommandKeyMessage =
        "Configure OpenRouter or install Claude/Codex CLI in Settings → AI Chat & Command to use this command."

    private func presentAICommand(
        _ command: AICommand,
        capture: Result<SelectedTextSnapshot, SelectedTextCaptureFailure>
    ) async {
        if command.replacesSelection {
            switch capture {
            case .failure(let error): showAICommandFailure(command, message: error.message)
            case .success(let snapshot):
                do {
                    let target = try AISelectionReplacement.capture(text: snapshot.text, pid: snapshot.source.processIdentifier)
                    do { try await target.prepare() }
                    catch {
                        AppLog.error("ai-spelling", "Progress failed: \(target.diagnosticSummary)")
                        restoreAICommandSelection(target)
                        _ = await target.restorationTask?.value
                        throw error
                    }
                    AppLog.info("ai-spelling", target.usesInlineProgress ? "Using inline replacement." : "Using guarded native paste.")
                    aiChat.replaceSpelling(command: command, selection: snapshot.text, onCancel: { [weak self] in
                        self?.restoreAICommandSelection(target)
                    }) { [weak self] result in
                        guard let self else { target.restoreOriginal(); return }
                        aiCommandCaptureTask = Task { @MainActor [weak self] in
                            guard let self else { target.restoreOriginal(); return }
                            do {
                                let replacement = try result.get()
                                AppLog.info("ai-spelling", "Reply received; validating replacement.")
                                try await target.complete(with: replacement) {
                                    let captured = await self.selectedTextCapture.capture()
                                    guard case .success(let current) = captured,
                                          current.source.processIdentifier == snapshot.source.processIdentifier else { return nil }
                                    return current.text
                                }
                                AppLog.info("ai-spelling", "Replacement completed.")
                            } catch {
                                AppLog.error("ai-spelling", "Replacement failed: \(target.diagnosticSummary)")
                                restoreAICommandSelection(target)
                                _ = await target.restorationTask?.value
                                if !Task.isCancelled { showAICommandFailure(command, message: error.localizedDescription) }
                            }
                        }
                    }
                } catch {
                    showAICommandFailure(command, message: error.localizedDescription)
                }
            }
            return
        }
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

    private func restoreAICommandSelection(_ target: AISelectionReplacement) {
        target.restoreOriginal()
        aiCommandCleanupTask = target.restorationTask
        let id = UUID()
        aiCommandRecoveryTasks[id] = Task { @MainActor [weak self] in
            await target.finishRestoringWhenFocused()
            self?.aiCommandRecoveryTasks.removeValue(forKey: id)
        }
    }

    private func showAICommandFailure(_ command: AICommand, message: String) {
        if command.replacesSelection {
            AppLog.error("ai-spelling", message)
            hud.show(title: message, symbol: "exclamationmark.triangle", isNoOp: true)
            return
        }
        let sessionID = aiChat.showCommandFailure(command: command, message: message,
            selectSession: false)
        showAICommandSession(sessionID)
    }

    private func showAICommandSession(_ sessionID: UUID) {
        showQuickAIChat(sessionID: sessionID)
    }
}
