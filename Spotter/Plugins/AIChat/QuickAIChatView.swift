import SwiftUI

struct QuickAIChatView: View {
    @ObservedObject var controller: QuickAIChatController
    @ObservedObject var chat: AIChatStore
    @ObservedObject var tools: AIToolStore
    @ObservedObject var router: OpenRouterStore
    @FocusState private var composerFocused: Bool
    @Namespace private var sessionTransition
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if controller.isExpanded {
                conversation
                    .transition(.opacity)
            } else {
                VStack(spacing: Theme.Spacing.md) {
                    if controller.showsHistory { historyPills }
                    if let notice = controller.notice {
                        Text(notice).font(.caption).foregroundStyle(.secondary)
                            .frame(height: Theme.Size.headerHeight)
                    }
                    HStack(spacing: Theme.Spacing.md) {
                        composer
                            .background { Theme.QuickAI.backdrop(isExpanded: false).allowsHitTesting(false) }
                            .clipShape(Capsule())
                        historyButton
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
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
                    QuickAIChatDragArea()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    historyButton
                    toolbarButton(symbol: "square.and.pencil", help: "New Chat (⌘N)", action: controller.newConversation)
                        .keyboardShortcut("n", modifiers: .command)
                    closeButton
                }
                .frame(height: Theme.Size.noteGlassButton)
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.top, Theme.Spacing.xl)
                .padding(.bottom, Theme.Spacing.md)
            }
                VStack(spacing: 0) {
                    if let sessionID = controller.sessionID {
                        AIChatTranscriptView(chat: chat, tools: tools, sessionID: sessionID, isFloating: true,
                            awaitingFirstReply: !controller.hasReceivedReply, sendingMessageID: controller.sendingMessageID)
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
                    composer
                        .glassEffect(.regular, in: Capsule())
                        .padding(Theme.Spacing.xl)
                }
                .frame(width: Theme.Size.quickAIWidth * 2)
                .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .background {
            if let id = controller.sessionID { sessionSurface(id: id, expanded: true) }
        }
        .clipShape(RoundedRectangle(cornerRadius: min(Theme.Radius.panel, controller.bodyHeight / 2),
            style: controller.isExpanded ? .continuous : .circular))
    }

    private var historyButton: some View {
        Group {
            if controller.isExpanded {
                toolbarButton(symbol: "clock", help: "Conversation History (⌘⇧S)", action: controller.toggleHistory)
            } else {
                Button(action: controller.toggleHistory) {
                    Image(systemName: "clock")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: Theme.Size.quickAIComposerHeight, height: Theme.Size.quickAIComposerHeight)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .background { Theme.QuickAI.backdrop(isExpanded: false).allowsHitTesting(false) }
                .clipShape(Circle())
                .background { QuickAIChatCompactGlass().allowsHitTesting(false) }
                .accessibilityLabel("Conversation History (⌘⇧S)")
                .help("Conversation History (⌘⇧S)")
            }
        }
        .keyboardShortcut("s", modifiers: [.command, .shift])
        .accessibilityValue(controller.showsHistory ? "Expanded" : "Collapsed")
    }

    private var historyPills: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                ForEach(controller.historySessions) { session in sessionRow(session) }
                if controller.historySessions.isEmpty {
                    Text("No conversations yet")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: Theme.Size.quickAIComposerHeight)
                        .background(Theme.Colors.quickAIBackdrop)
                        .clipShape(Capsule())
                        .background { QuickAIChatCompactGlass() }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func sessionRow(_ session: AIChatSession) -> some View {
        Button {
            withAnimation(reduceMotion ? .easeOut(duration: 0.16) : .spring(duration: 0.34, bounce: 0.08)) {
                controller.openSession(session.id)
            }
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: session.systemImage).foregroundStyle(.secondary)
                Text(session.title).lineLimit(1)
                Spacer(minLength: 0)
                if chat.waitingSessionID == session.id { ProgressView().controlSize(.mini) }
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: Theme.Size.quickAIComposerHeight)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background { sessionSurface(id: session.id, expanded: false) }
        .clipShape(Capsule())
        .background { QuickAIChatCompactGlass().allowsHitTesting(false) }
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

    @ViewBuilder
    private func sessionSurface(id: UUID, expanded: Bool) -> some View {
        let fill = expanded ? Theme.QuickAI.backdrop(isExpanded: true)
            : LinearGradient(colors: [Theme.Colors.quickAIBackdrop, Theme.Colors.quickAIBackdrop], startPoint: .top, endPoint: .bottom)
        let surface = RoundedRectangle(cornerRadius: expanded ? Theme.Radius.panel : Theme.Size.quickAIComposerHeight / 2)
            .fill(fill)
        if reduceMotion {
            surface.allowsHitTesting(false)
        } else {
            surface.matchedGeometryEffect(id: id, in: sessionTransition).allowsHitTesting(false)
        }
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
        .environment(\.appearsActive, true)
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
