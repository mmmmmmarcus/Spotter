import SwiftUI

struct AIChatTranscriptView: View {
    @ObservedObject var chat: AIChatStore
    @ObservedObject var tools: AIToolStore
    let sessionID: UUID
    var isFloating = false
    var awaitingFirstReply = false
    var sendingMessageID: UUID? = nil
    @State private var followsBottom = true
    @State private var isUserScrolling = false
    private static let bottomAnchor = "ai-chat-bottom"
    private var messages: [AIChatMessage] { chat.messages(in: sessionID) }
    private var phase: AIChatPhase { chat.requests.phase(for: sessionID) }
    private var edgeMask: EdgeDissolveMask {
        isFloating ? EdgeDissolveMask(topFade: awaitingFirstReply ? 0 : Theme.Spacing.xxl, bottomFade: Theme.Spacing.xxl) : EdgeDissolveMask()
    }

    private var toolActivities: [AIToolActivity] { tools.activities.filter { $0.sessionID == sessionID } }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    ForEach(messages) { message in
                        AIChatRow(message: message, isStreaming: message.id == chat.streamingReply?.id,
                            bubbleInset: isFloating ? Theme.Size.chatBubbleInset / 3 : Theme.Size.chatBubbleInset,
                            showsRouting: !isFloating)
                            .anchorPreference(key: QuickAISendAnchors.self, value: .bounds) { anchor in
                                QuickAISendAnchors.Value(destination: message.id == sendingMessageID ? anchor : nil)
                            }
                            .opacity(message.id == sendingMessageID ? 0 : 1)
                    }
                    if !toolActivities.isEmpty {
                        DisclosureGroup("Tool activity · \(toolActivities.count)") {
                            ForEach(toolActivities) { activity in
                                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                    Text(activity.title).font(.caption.weight(.semibold))
                                    Text(activity.detail).font(.caption).foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, Theme.Spacing.xs)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                    }
                    if phase == .waiting, tools.isRunning {
                        HStack {
                            AIChatStatusRow(text: tools.status, pulses: true)
                            Spacer()
                            Button("Stop") { chat.stop() }.controlSize(.small)
                        }
                    } else if phase == .waiting {
                        AIChatStatusRow(
                            text: chat.waitingStatus, pulses: true)
                    }
                    if case .failed(let reason) = phase {
                        AIChatStatusRow(
                            symbol: "exclamationmark.triangle", text: reason, pulses: false)
                    }
                    Color.clear.frame(height: 1).id(Self.bottomAnchor)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.xs)
                .padding(.bottom, Theme.Spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .modifier(edgeMask)
            .thinScrollbar()
            .defaultScrollAnchor(awaitingFirstReply ? .top : .bottom)
            .onScrollPhaseChange { _, phase in
                isUserScrolling = phase == .tracking || phase == .interacting || phase == .decelerating
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentSize.height - geometry.visibleRect.maxY < 60
            } action: { _, nearBottom in
                if isUserScrolling || nearBottom { followsBottom = nearBottom }
            }
            .onChange(of: awaitingFirstReply) { _, waiting in
                if !waiting && followsBottom { proxy.scrollTo(Self.bottomAnchor, anchor: .bottom) }
            }
            .onChange(of: chat.streamingReply?.text) {
                if followsBottom && !awaitingFirstReply { proxy.scrollTo(Self.bottomAnchor, anchor: .bottom) }
            }
            // Follow the conversation: a sent turn and its landing reply both pin to the bottom.
            .onChange(of: messages.count) {
                guard !awaitingFirstReply else { return }
                if sendingMessageID != nil {
                    proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
                    return
                }
                withAnimation(.easeOut(duration: Theme.Animation.quick)) {
                    proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
                }
            }
            .onChange(of: tools.status) {
                if followsBottom && !awaitingFirstReply { proxy.scrollTo(Self.bottomAnchor, anchor: .bottom) }
            }
            .onChange(of: phase) {
                if followsBottom && !awaitingFirstReply { proxy.scrollTo(Self.bottomAnchor, anchor: .bottom) }
            }
        }
    }
}

struct AIChatRow: View {
    let message: AIChatMessage
    let isStreaming: Bool
    let bubbleInset: CGFloat
    let showsRouting: Bool

    var body: some View {
        // Messenger grammar: the user's turns are right-aligned bubbles, the assistant's replies
        // sit on the bare surface like results.
        if message.role == .user {
            HStack {
                Spacer(minLength: bubbleInset)
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
                        if let command = message.commandInput {
                            Image(systemName: command.symbol ?? "command")
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .help(command.name)
                                .accessibilityLabel(command.name)
                        }
                        Text(message.displayedText)
                    }
                    if !message.attachments.isEmpty {
                        ForEach(message.attachments) { attachment in
                            Label(attachment.name,
                                systemImage: attachment.kind == .image ? "photo" : attachment.kind == .pdf ? "doc.richtext" : "doc.text")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }
                .font(Theme.Typography.rowTitle)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.vertical, Theme.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.chatBubble, style: .continuous)
                        .fill(Theme.Colors.quickAIUserBubble)
                )
            }
            .padding(.horizontal, Theme.Spacing.md)
        } else {
            // Models answer in Markdown whether or not they are asked to; rendered, not raw.
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                if showsRouting, let selection = message.routing {
                    Label(LocalAIModel.label(selection.model)
                        ?? OpenRouterModelCatalog.modelName(for: selection.model, in: []) ?? selection.model,
                        systemImage: "arrow.trianglehead.branch")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .help("\(selection.label) · \(selection.model)")
                }
                AIChatMarkdownText(text: message.text, isStreaming: isStreaming)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
        }
    }
}

private struct AIChatStatusRow: View {
    var symbol: String? = nil
    let text: String
    let pulses: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            if let symbol {
                Image(systemName: symbol)
                .font(Theme.Typography.rowTrailing)
                .symbolRenderingMode(.monochrome)
                .symbolEffect(.pulse, isActive: pulses && !reduceMotion)
                .foregroundStyle(.secondary)
                .frame(width: Theme.Size.rowIcon)
            }
            statusText
                .foregroundStyle(.secondary)
                .overlay {
                    if pulses && !reduceMotion {
                        GeometryReader { geometry in
                            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                                let progress = context.date.timeIntervalSinceReferenceDate
                                    .truncatingRemainder(dividingBy: 2) / 2
                                LinearGradient(colors: [.clear, .primary.opacity(0.9), .clear],
                                    startPoint: .leading, endPoint: .trailing)
                                    .frame(width: geometry.size.width * 0.6)
                                    .offset(x: geometry.size.width * (progress * 1.6 - 0.6))
                            }
                        }
                        .mask(statusText)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
    }

    private var statusText: some View {
        Text(text)
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
    }
}
