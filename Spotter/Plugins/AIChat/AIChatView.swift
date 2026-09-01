import SwiftUI

/// The conversation body of the AI Chat palette mode. The shared header search field is the
/// composer — this view only renders the transcript, in the palette's own list chrome.
struct AIChatView: View {
    @ObservedObject var chat: AIChatStore
    let scroll: ScrollIntent

    /// Anchor row pinned under the newest content so replies land scrolled into view.
    private static let bottomAnchor = "ai-chat-bottom"

    var body: some View {
        if !chat.isReady {
            EmptyResults(
                text: "AI Chat needs an OpenRouter API key — add one in Settings → General → AI.")
        } else if chat.messages.isEmpty && chat.phase == .idle {
            if chat.isWaiting {
                EmptyResults(
                    text:
                        "Another session is thinking — switch back from Sessions or stop it in Actions."
                )
            } else if historySessions.isEmpty {
                EmptyResults(
                    text: "Ask anything — Tab sends here, and ⌃⌥⌘C sends to ChatGPT on the web.")
            } else {
                history
            }
        } else {
            transcript
        }
    }

    /// Every past conversation, newest first; the blank current session is not history.
    private var historySessions: [AIChatSession] {
        chat.orderedSessions.filter { !$0.messages.isEmpty }
    }

    /// A fresh session opens on where you left off: the past conversations as rows, one click from
    /// resuming any of them. Typing and sending still starts the new conversation as before.
    private var history: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                SectionHeader(title: "History", isFirst: true)
                ForEach(historySessions) { session in
                    AIChatHistoryRow(session: session) { chat.switchTo(session.id) }
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.md)
            .hideNativeScrollers()
            .scrollOriginAnchor()
        }
        .edgeDissolve()
        .thinScrollbar()
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    ForEach(chat.messages) { message in
                        AIChatRow(message: message)
                    }
                    if chat.phase == .waiting {
                        AIChatStatusRow(symbol: "ellipsis", text: "Thinking…", pulses: true)
                    }
                    if case .failed(let reason) = chat.phase {
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
            .edgeDissolve()
            .thinScrollbar()
            .defaultScrollAnchor(.bottom)
            // Follow the conversation: a sent turn and its landing reply both pin to the bottom.
            .onChange(of: chat.messages.count) {
                withAnimation(.easeOut(duration: Theme.Animation.quick)) {
                    proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
                }
            }
            .onChange(of: chat.phase) {
                proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
            }
        }
    }
}

private struct AIChatHistoryRow: View {
    let session: AIChatSession
    let open: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(session.title)
                    .font(Theme.Typography.rowTitle)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Spacing.xl)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(hovered ? Theme.Colors.rowHover : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .armedHover($hovered)
    }

    private var subtitle: String {
        let turns = session.messages.count
        let started = session.startedAt.formatted(.relative(presentation: .named))
        return "\(started) · \(turns) \(turns == 1 ? "message" : "messages")"
    }
}

private struct AIChatRow: View {
    let message: AIChatMessage

    var body: some View {
        // Messenger grammar: the user's turns are right-aligned bubbles, the assistant's replies
        // sit on the bare surface like results.
        if message.role == .user {
            HStack {
                Spacer(minLength: Theme.Size.chatBubbleInset)
                Text(message.text)
                    .font(Theme.Typography.rowTitle)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.vertical, Theme.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.chatBubble, style: .continuous)
                            .fill(Theme.Colors.controlSurface)
                    )
            }
            .padding(.horizontal, Theme.Spacing.md)
        } else {
            // Models answer in Markdown whether or not they are asked to; rendered, not raw.
            AIChatMarkdownText(text: message.text)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
        }
    }
}

private struct AIChatStatusRow: View {
    let symbol: String
    let text: String
    let pulses: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Image(systemName: symbol)
                .font(Theme.Typography.rowTrailing)
                .symbolRenderingMode(.hierarchical)
                .symbolEffect(.pulse, isActive: pulses)
                .foregroundStyle(.secondary)
                .frame(width: Theme.Size.rowIcon)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
    }
}
