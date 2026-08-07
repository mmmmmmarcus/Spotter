# AI Chat

A conversation inside the palette, at launcher size. **Tab** from the launcher enters it (the cycle
is Apps → AI Chat → Clipboard), the shared header search field is the composer, and the body renders
the running transcript.

**Tab always opens a fresh session.** With an empty query it lands on a new blank session; with a
typed query it starts a new session *and sends immediately* — type the question in the launcher,
Tab, and it's already asked (no key configured, the text stays in the composer beside the
add-a-key notice). An already-empty current session is reused so cycling modes can't pile up
blanks. Earlier conversations live in the **session menu**: the bottom-left palette menu in chat
mode lists sessions newest-first (titled by their first user turn, the Notes derive-don't-ask rule)
plus New Session (also **⌘N** anywhere in chat), and the ⌘K menu adds Delete Session.

Enabled by default, but inert without an OpenRouter API key — the key is the gate, shared with
Selection Tools and entered there once (the same owner decision: entering or syncing a key is the
consent act). Files live in `Spotter/Plugins/AIChat/`.

## Files

| File | Role |
| --- | --- |
| `AIChatTypes.swift` | Foundation-only, pure: the message model, the system prompt, transcript windowing. |
| `AIChatStore.swift` | The conversation, the one in-flight request, and failure state. |
| `AIChatPlugin.swift` | Registration, the ⌘K menu, and `AppCore.openAIChat`. |
| `AIChatView.swift` | The transcript body, in the palette's own list chrome. |
| `AIChatSettingsView.swift` | Enable switch, chat model, shortcut, privacy callout. |

`Tools/ai-chat-test.swift` compiles `AIChatTypes.swift` standalone, so it must stay free of AppKit
and SwiftUI. The network lives in `OpenRouterStore`, never here.

## Interaction

- **↵ sends** whatever is typed and clears the field; the reply appends when it lands. While a reply
  is in flight the footer pill reads "Thinking…" and a pulsing status row sits under the transcript.
- The transcript keeps the newest content pinned to the bottom, user turns render as right-aligned
  bubbles (`chatBubble` radius, `controlSurface` fill), assistant turns as plain leading result
  text, and everything is text-selectable.
- **⌘K**: Stop Waiting (while in flight), Copy Last Reply, Copy Conversation, New Session, Delete
  Session, a Web Search on/off toggle, and AI Chat Settings…
- **Esc** backs out to the launcher (the standard ladder); the conversation survives, and re-entering
  chat resumes it. ↑/↓ do nothing — the transcript has no row selection.
- `AIChatMode` is a core `PaletteMode` (like Emoji) rather than a `PluginPaletteList` screen: a
  conversation flow is not a filter-a-list interaction, and the emoji grid is the precedent for a
  mode with its own body view while the plugin carries enable state, the launcher command and the
  shortcut.

## Requests

`AIChatStore.send` appends the user turn, windows the transcript to a character budget
(`AIChatEngine.transcriptWindow`, newest kept, the latest message always surviving), prefixes the
system prompt, and calls the multi-turn `OpenRouterStore.chat(messages:model:)` with the dedicated
`chatModel` (default `anthropic/claude-sonnet-5` — chat carries multi-turn reasoning, so it defaults
a class up from the quick selection actions; synced as `openRouterChatModel`). Requests carry a
`max_tokens` cap: OpenRouter reserves credits for the whole completion window up front, so an
uncapped request 402s on a small balance even when the reply would cost cents. The key is re-checked
on both sides of the await, replies are non-streaming in this version, and a failure renders as a
status row carrying OpenRouter's own error message, with the sent turn retained. The reply lands in
the session that asked, even if the user switched sessions while waiting; failures also log to
Settings → Diagnostics.

## Web search

An optional per-chat capability, off by default: when enabled (Settings → AI Chat, or the ⌘K
toggle), requests carry OpenRouter's Exa-backed `web` plugin (`plugins: [{id: "web"}]`, 5 results),
letting replies cite current information. It rides the same key and the same consented request to
the same provider — no new network surface — but each search adds a small per-message cost, which is
why it ships off. Synced as `openRouterChatWebSearch`.

## Privacy

Conversations are session-only by design: nothing is persisted, New Conversation or quitting Spotter
clears the transcript, and messages go only to OpenRouter under the user's own key.
