import SwiftUI

struct QuickAIChatView: View {
    @ObservedObject var controller: QuickAIChatController
    @ObservedObject var chat: AIChatStore
    @ObservedObject var tools: AIToolStore
    @ObservedObject var router: OpenRouterStore
    @FocusState private var composerFocused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: Theme.Spacing.md) {
            if !controller.isExpanded { sidebarButton }
            conversation
        }
        .overlayPreferenceValue(QuickAISendAnchors.self) { anchors in
            GeometryReader { geometry in
                if let id = controller.sendingMessageID,
                    let sessionID = controller.sessionID,
                    let message = chat.messages(in: sessionID).first(where: { $0.id == id }),
                    let source = anchors.source, let destination = anchors.destination {
                    QuickAISendingBubble(message: message, source: geometry[source], destination: geometry[destination]) {
                        controller.finishSendingAnimation(id)
                    }
                    .id(id)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .tint(.primary)
        .onAppear { composerFocused = true }
        .onChange(of: controller.focusToken) { composerFocused = true }
    }

    private var conversation: some View {
        VStack(spacing: 0) {
            if controller.isExpanded {
                HStack {
                    sidebarButton
                    QuickAIChatDragArea()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    toolbarButton(symbol: "square.and.pencil", help: "New Chat (⌘N)", action: controller.newConversation)
                        .keyboardShortcut("n", modifiers: .command)
                    closeButton
                }
                .frame(height: Theme.Size.noteGlassButton)
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.top, Theme.Spacing.xl)
                .padding(.bottom, Theme.Spacing.md)
            }
            HStack(spacing: 0) {
                if controller.showsSidebar {
                    historySidebar
                        .frame(width: Theme.QuickAI.sidebarWidth)
                        .overlay(alignment: .trailing) { Divider() }
                }
                VStack(spacing: 0) {
                    if let sessionID = controller.sessionID {
                        AIChatTranscriptView(chat: chat, tools: tools, sessionID: sessionID, isFloating: true,
                            awaitingFirstReply: !controller.hasReceivedReply, sendingMessageID: controller.sendingMessageID)
                            .id(sessionID)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if controller.isExpanded {
                        Text("Ask Spotter")
                            .foregroundStyle(.secondary)
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
                            .padding(Theme.Spacing.xl)
                    } else {
                        composer
                    }
                }
                .frame(width: controller.isExpanded ? Theme.Size.quickAIWidth * 2 : nil)
                .frame(maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .background { Theme.QuickAI.backdrop(isExpanded: controller.isExpanded).allowsHitTesting(false) }
        .clipShape(RoundedRectangle(cornerRadius: min(Theme.Radius.panel, controller.bodyHeight / 2),
            style: controller.isExpanded ? .continuous : .circular))
    }

    private var sidebarButton: some View {
        toolbarButton(symbol: "sidebar.left", help: "Toggle Conversation History (⌘⇧S)", action: controller.toggleSidebar,
            diameter: controller.isExpanded ? Theme.Size.noteGlassButton : Theme.Size.quickAIComposerHeight)
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .accessibilityValue(controller.showsSidebar ? "Expanded" : "Collapsed")
    }

    private var historySidebar: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let sections = AIChatEngine.historySections(sidebarSessions, now: context.date, calendar: .current)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    ForEach(sections) { section in
                        Text(section.period.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.top, Theme.Spacing.md)
                            .padding(.bottom, Theme.Spacing.xs)
                        ForEach(section.sessions) { session in
                            sessionRow(session)
                        }
                    }
                    if sections.isEmpty {
                        Text("No conversations yet")
                            .font(.caption).foregroundStyle(.secondary)
                            .padding(Theme.Spacing.md)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.bottom, Theme.Spacing.md)
        }
    }

    private func sessionRow(_ session: AIChatSession) -> some View {
        Button { controller.openSession(session.id) } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: session.systemImage).foregroundStyle(.secondary)
                Text(session.title).lineLimit(1)
                Spacer(minLength: 0)
                if chat.waitingSessionID == session.id { ProgressView().controlSize(.mini) }
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(session.id == controller.sessionID ? Theme.Colors.selection : .clear,
                in: RoundedRectangle(cornerRadius: Theme.Radius.row))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(session.title)
        .accessibilityAddTraits(session.id == controller.sessionID ? [.isSelected] : [])
        .contextMenu {
            Button("Copy Conversation", systemImage: "doc.on.clipboard") {
                Paster.copyPlainText(chat.transcript(in: session.id))
            }
            Button("Delete Conversation", systemImage: "trash", role: .destructive) {
                AppCore.shared.confirmDeleteAIChatSession(session.id)
            }
        }
    }

    private var sidebarSessions: [AIChatSession] {
        chat.orderedSessions.filter { !$0.messages.isEmpty || $0.titleOverride != nil || $0.id == controller.sessionID }
    }

    private var closeButton: some View {
        toolbarButton(symbol: "xmark", help: "Close Quick AI Chat") { controller.hide() }
            .keyboardShortcut("w", modifiers: .command)
    }

    private func toolbarButton(symbol: String, help: String, action: @escaping () -> Void,
        diameter: CGFloat = Theme.Size.noteGlassButton) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: diameter, height: diameter)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(width: diameter, height: diameter)
        .focusable(false)
        .accessibilityLabel(help)
        .glassEffect(.regular.tint(Theme.Colors.quickAIControlTint).interactive(), in: Circle())
        .help(help)
    }

    private var composer: some View {
        HStack(spacing: Theme.Spacing.md) {
            TextField("Message", text: $controller.draft, prompt: Text("Ask Spotter")
                .foregroundStyle(Theme.Colors.textSecondary))
                .textFieldStyle(.plain)
                .font(Theme.Typography.rowTitle)
                .focused($composerFocused)
                .onSubmit { controller.submit() }
                .accessibilityLabel("Quick AI Chat message")
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
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .frame(height: Theme.Size.quickAIComposerHeight)
        .anchorPreference(key: QuickAISendAnchors.self, value: .bounds) { QuickAISendAnchors.Value(source: $0) }
    }
}

struct QuickAISendAnchors: PreferenceKey {
    struct Value {
        var source: Anchor<CGRect>?
        var destination: Anchor<CGRect>?
    }

    static var defaultValue: Value { Value() }

    static func reduce(value: inout Value, nextValue: () -> Value) {
        let next = nextValue()
        value.source = next.source ?? value.source
        value.destination = next.destination ?? value.destination
    }
}

private struct QuickAISendingBubble: View {
    let message: AIChatMessage
    let source: CGRect
    let destination: CGRect
    let completion: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0

    var body: some View {
        AIChatRow(message: message, isStreaming: false,
            bubbleInset: Theme.Size.chatBubbleInset / 3, showsRouting: false)
            .frame(width: destination.width, height: destination.height)
            .scaleEffect(reduceMotion ? 1 : 0.94 + 0.06 * progress, anchor: .bottomTrailing)
            .opacity(0.35 + 0.65 * progress)
            .position(x: destination.midX,
                y: reduceMotion ? destination.midY : source.midY + (destination.midY - source.midY) * progress)
            .task {
                withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.46, bounce: 0.12)) {
                    progress = 1
                }
                do { try await Task.sleep(for: .milliseconds(reduceMotion ? 180 : 650)) }
                catch { return }
                completion()
            }
    }
}
