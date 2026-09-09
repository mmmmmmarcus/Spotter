import AppKit

extension AppCore {
    func performLauncherFallback(_ fallback: LauncherFallback) {
        guard palette.mode == .launcher else { return }
        switch fallback.action {
        case .aiChat:
            startAIChat(prompt: fallback.query)
        case .chatGPT:
            sendAIChatPromptToChatGPT(fallback.query)
        case .terminal:
            runInTerminal(fallback.query)
        case .fileSearch:
            openFileSearch(query: fallback.query)
        }
    }

    private func runInTerminal(_ command: String) {
        hidePalette(restoreFocus: false)
        let terminal = settings.preferredTerminal
        Task {
            let outcome = await TerminalCommandRunner.run(command, terminal: terminal)
            guard outcome != .success else { return }
            AppLog.error("launcher", "Terminal handoff failed: \(outcome)")
            hud.show(
                title: "Could Not Run in Terminal", symbol: "exclamationmark.triangle",
                isNoOp: true)
        }
    }
}
