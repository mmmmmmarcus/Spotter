import SwiftUI

struct QuickAIChatView: View {
    @ObservedObject var controller: QuickAIChatController
    @ObservedObject var chat: AIChatStore
    @ObservedObject var tools: AIToolStore
    @ObservedObject var router: OpenRouterStore
    @FocusState private var composerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let sessionID = controller.sessionID {
                HStack {
                    closeButton
                    QuickAIChatDragArea()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    toolbarButton(symbol: "square.and.pencil", help: "New Chat (⌘N)", action: controller.newConversation)
                        .keyboardShortcut("n", modifiers: .command)
                }
                .frame(height: Theme.Size.noteGlassButton)
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.top, Theme.Spacing.xl)
                .padding(.bottom, Theme.Spacing.md)
                AIChatTranscriptView(chat: chat, tools: tools, sessionID: sessionID, isFloating: true, awaitingFirstReply: !controller.hasReceivedReply)
                    .id(sessionID)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let notice = controller.notice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Spacing.xl)
                    .frame(height: Theme.Size.headerHeight)
            }
            if controller.isExpanded {
                composer
                    .glassEffect(.regular, in: Capsule())
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.vertical, Theme.Spacing.xl)
            } else {
                composer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .background { Theme.QuickAI.backdrop(isExpanded: controller.isExpanded).allowsHitTesting(false) }
        .tint(.primary)
        .onAppear { composerFocused = true }
        .onChange(of: controller.focusToken) { composerFocused = true }
    }

    private var closeButton: some View {
        toolbarButton(symbol: "xmark", help: "Close Quick AI Chat") { controller.hide() }
            .keyboardShortcut("w", modifiers: .command)
    }

    private func toolbarButton(symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: Theme.Size.noteGlassButton, height: Theme.Size.noteGlassButton)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(width: Theme.Size.noteGlassButton, height: Theme.Size.noteGlassButton)
        .focusable(false)
        .accessibilityLabel(help)
        .glassEffect(.regular.interactive(), in: Circle())
        .help(help)
    }

    private var composer: some View {
        HStack(spacing: Theme.Spacing.md) {
            Button { AppCore.shared.chooseAIChatAttachments() } label: {
                Image(systemName: chat.pendingAttachments.isEmpty ? "paperclip" : "paperclip.circle.fill")
                    .symbolRenderingMode(.monochrome)
            }
            .buttonStyle(.plain)
            .help(chat.pendingAttachments.isEmpty ? "Attach Files" : "\(chat.pendingAttachments.count) attachment(s)")
            .accessibilityLabel("Attach Files")
            .contextMenu {
                if !chat.pendingAttachments.isEmpty {
                    Button("Clear Attachments", role: .destructive) { chat.clearPendingAttachments() }
                }
            }
            TextField("Message", text: $controller.draft, prompt: Text("Ask Spotter")
                .foregroundStyle(Theme.Colors.textSecondary))
                .textFieldStyle(.plain)
                .font(Theme.Typography.rowTitle)
                .focused($composerFocused)
                .onSubmit { controller.submit() }
                .accessibilityLabel("Quick AI Chat message")
            if !chat.isReady {
                Button(action: controller.openSettings) {
                    Image(systemName: "key")
                        .symbolRenderingMode(.monochrome)
                }
                .buttonStyle(.plain)
                .help("AI Chat Settings")
                .accessibilityLabel("AI Chat Settings")
            } else if let sessionID = controller.sessionID, chat.waitingSessionID == sessionID {
                Button { chat.stop() } label: {
                    Image(systemName: "stop.circle")
                        .symbolRenderingMode(.monochrome)
                }
                .buttonStyle(.plain)
                .help("Stop Reply")
                .accessibilityLabel("Stop Reply")
            } else {
                Button(action: controller.submit) {
                    Image(systemName: "arrow.up.circle.fill")
                        .symbolRenderingMode(.monochrome)
                }
                .buttonStyle(.plain)
                .disabled(chat.isWaiting || controller.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Send (↵)")
                .accessibilityLabel("Send")
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .frame(height: Theme.Size.quickAIComposerHeight)
    }
}
