# AI Chat

A conversation inside the palette, at launcher size. The shared header search field is the composer,
the body renders the running transcript, and **↵** (or ⌘↵) sends through Spotter's OpenRouter-backed
chat. That is the only send binding, and the footer says so: one primary button, `Send ↵`, exactly
like every other surface. Tab never sends — both Tab directions are purely the surface cycle, which
the header's mode glyph already advertises ("Switch surface (⇥)").

The web handoff is **Send to ChatGPT** in the ⌘K Actions menu, on the draft in the composer. It has
no key binding of its own (owner decision, Sep 2026): the Hyper-C chord — and with it
`PaletteViewModel.chatGPTChordToken` and the `PalettePanel.sendEvent` interception that carried it —
is gone, from the launcher as well as from chat. Nothing was persisted for that chord (it was
hardcoded, never a recorded shortcut), so no binding, recorder row or `KeyboardShortcuts_*` key is
orphaned by the removal, and the launcher's `Send to ChatGPT` row still reaches the same handoff.

From the launcher, **⌘↵** with a typed query starts a fresh AI Chat session and sends immediately,
while **Tab** enters chat carrying the draft into the composer unsent;
without a key, the text stays in the composer beside the add-a-key notice. With no draft, Tab keeps
the Apps → AI Chat → Clipboard → Emoji surface cycle and Shift-Tab walks it backward. Only the
launcher's query follows into chat; arriving from Clipboard or Emoji, the filter string is dropped
rather than sent. An already-empty current session is reused so cycling
modes cannot pile up blanks. Entering chat on that empty session shows **History**: every past
conversation as a row (title, relative start, turn count), one click from resuming — typing and
sending still starts the fresh conversation. Earlier conversations also live in the **session
menu**: the bottom-left palette menu in chat mode lists sessions newest-first (titled by their first
user turn, the Notes derive-don't-ask rule) plus New Session (also **⌘N** anywhere in chat), and the
⌘K menu adds Delete Session.

Every non-empty launcher query also exposes those same two destinations in a final `Try With` group,
after any normal results. The AI Chat row names the selected chat model — `Ask Gemini 2.0 Flash…`,
from `OpenRouterModelCatalog.modelName(for:in:)` — and falls back to `Send to AI Chat` with no API
key, since the key is the gate and an unkeyed row can't promise a model. Activating AI Chat follows
the fresh-session Tab path; activating ChatGPT follows the same web handoff the Actions menu runs.

AI Chat is an always-available system feature, shown in the Settings sidebar as **AI Chat &
Command**, but remains inert without an OpenRouter API key — the key is the gate and lives on that
same pane's **AI (OpenRouter)** card, moved there from General in 1.6.0 so the gate sits with the
feature it gates (entering or syncing a key is the consent act). The key field carries no example
and no instructions; what it keeps is the one thing entering a key actually commits the user to —
that messages go to OpenRouter under it, and that it rides settings backups and sync — replaced by
the validation result once the key has been checked. AI Chat also owns **AI commands**, the prompts that run on
selected text; Define Selected Text and Check Selected Text Grammar are the two Spotter ships.
Google-powered translation lives in the [Translate](translate.md) plugin. Its implementation lives in
`Spotter/Plugins/AIChat/` so it can reuse the registry's Settings, command, permission and shortcut
plumbing without being presented as an optional plugin.

## Files

| File | Role |
| --- | --- |
| `AIChatTypes.swift` | Foundation-only, pure: portable message/session models, derived session title, the request status vocabulary, system prompt, transcript windowing and ChatGPT web URL. |
| `AIChatStore.swift` | The conversation, the one in-flight request, and failure state. |
| `AIChatSelectionPrompts.swift` | Foundation-only: the prompts the two shipped AI commands start with. |
| `AICommand.swift` | Foundation-only, pure: the AI command record, built-in identity, `{selection}` substitution and list repair. |
| `AICommandStore.swift` | Foundation + Combine: the saved commands, their validation and the upgrade from the old prompt/model keys. |
| `AIChatMarkdown.swift` | Foundation-only, pure: splits a reply into Markdown blocks. |
| `AIChatPlugin.swift` | Registration, the ⌘K menu, and `AppCore.openAIChat`. |
| `AIChatView.swift` | The transcript body, in the palette's own list chrome. |
| `AIChatMarkdownView.swift` | Renders those blocks; inline spans go through SwiftUI's own parser. |
| `AIChatSettingsView.swift` | The OpenRouter API key, the chat model and web search, plus the AI command list and its editor sheet. |

`Core/OpenRouterModelCatalog.swift` is Foundation-only and pure too: it turns the `/models` payload
into the brand → model menus.

`Tools/ai-chat-test.swift` compiles `AIChatTypes.swift`, `AIChatMarkdown.swift`,
`AIChatSelectionPrompts.swift`, `AICommand.swift`, `AICommandStore.swift` and
`Core/OpenRouterModelCatalog.swift` standalone, so all six stay free of AppKit and SwiftUI. The
network lives in `OpenRouterStore`, never in any pure source.

## Choosing a model

The chat model and every AI command pick from a two-level menu — brand, then model — rather than a
typed identifier: OpenRouter publishes hundreds of models across dozens of vendors, which is a list
to browse, not a string to remember. A command's menu also carries **Default**, which is the command
following the chat model instead of pinning one of its own; the two shipped commands pin
`anthropic/claude-haiku-4.5`, the fast class their first answer has always used.
Opening Settings → AI Chat & Command reloads the catalog from
`https://openrouter.ai/api/v1/models` so the menu is what the provider offers right now; a Reload
button forces it, and the result is cached for 15 minutes and never persisted, so no stale list
outlives the app.

`OpenRouterModelCatalog` groups by the id's vendor prefix, strips the brand from the entry's
`"Anthropic: Claude Sonnet 5"` name, drops models that can't answer in text, orders brands
alphabetically and each brand's models newest first. The stored value is still the plain model id,
so existing settings, backups and sync are unchanged. A stored model the live catalog doesn't carry
— an older pick, or one OpenRouter has withdrawn — stays selected and stays selectable in a
**Current** section at the top of the menu, so nothing is silently rewritten. A command pinned to a
model the user's key can no longer reach therefore keeps that choice: its editor still names it, the
request still asks for it, and if OpenRouter refuses, the reply is a status row carrying OpenRouter's
own message. Only an empty pin resolves to the chat model — Spotter never silently answers as some
other model. Switching that command back to **Default** is one menu away.

The list is fetched only once a key exists: the key remains the gate, an absent key clears the
catalog, and the request itself is unauthenticated and carries nothing about this Mac or its
conversations — it reads the same public catalog anyone can. It rides the same cacheless session as
every other OpenRouter call.

## Reply formatting

Models answer in Markdown whether or not they are asked to, so assistant turns render it.
`AIChatMarkdown.blocks(in:)` splits a reply into paragraphs, headings, bullet / numbered / task list
items, block quotes, fenced code, pipe tables and rules; `AIChatMarkdownText` styles each block and
hands the inline spans — bold, italics, code, strikethrough, links — to SwiftUI's own Markdown
parser, which keeps the split shallow and the pure half testable. Structure is only recognized where
Markdown means it: a heading needs its space, a table needs its delimiter row, and unparseable text
falls back to the literal characters the model sent. A truncated reply's unterminated fence still
renders as code. User turns stay literal — a typed asterisk is an asterisk.

Because a reply is now several `Text` views, a drag selects within one block rather than across the
whole reply; ⌘K → Copy Last Reply / Copy Conversation still copies the raw Markdown.

## Interaction

- **↵ or ⌘↵ sends to Spotter AI** and clears the field after the request is accepted; the reply
  appends when it lands. While a reply is in flight the footer pill reads "Thinking…" and a pulsing
  status row sits under the transcript. Those words come from `AIChatEngine.waitingStatus`, the one
  status vocabulary the pill, the transcript row and the background-task row all read.
- **Send to ChatGPT** (⌘K, shown only when the composer holds a draft) opens an encoded `q` query in
  the default browser. Spotter dismisses without appending the prompt to its own transcript; ChatGPT
  owns the new web session, account and request. Like every other row in that menu it is reachable by
  Actions type-ahead, and the draft is sampled when the menu opens — which is exactly when palette
  input freezes, so the search field keeps first responder and the sampled text cannot go stale.
- The transcript keeps the newest content pinned to the bottom, user turns render as right-aligned
  bubbles (`chatBubble` radius, `controlSurface` fill), assistant turns as unadorned leading result
  text without an icon, and everything is text-selectable.
- **⌘K**: Stop Waiting (while in flight), Send to ChatGPT (with a draft), Copy Last Reply, Copy
  Conversation, New Session, Delete Session, a Web Search on/off toggle, and AI Chat Settings… Delete Session uses the shared
  in-palette confirmation card with Cancel selected first.
- **Esc** backs out to the launcher (the standard ladder); the conversation survives, and re-entering
  chat resumes it. An in-flight request appears there as an indeterminate background task **titled
  with the conversation** — `AIChatSession.title`, so an override (a selected-text action) wins and
  everything else derives from the first user turn — and subtitled with its status: `Thinking…` while
  in flight, `Reply ready.` on success, OpenRouter's own message on failure. Several finished AI rows
  are therefore told apart by the questions that made them. A send always appends the user turn
  before the row is titled, so the untitled fallback (`New Session`) is unreachable in practice;
  success or failure remains dismissible while Stop Waiting discards the row. ↑/↓ do nothing — the transcript
  has no row selection.
- `AIChatMode` is a core `PaletteMode` (like Emoji) rather than a `PluginPaletteList` screen: a
  conversation flow is not a filter-a-list interaction, and the emoji grid is the precedent for a
  mode with its own body view while the plugin carries the launcher command and the
  shortcut.

## AI commands

An **AI command** is a name, a prompt, a shortcut and a model choice. The prompt is a template:
`{selection}` — the same single-brace shape a quicklink's `{argument}` uses — is where the selected
text lands. Running one captures the selection through the `AppCore`-owned `SelectedTextCapture`,
renders the prompt, opens a new titled chat session and sends immediately. The rendered prompt *is*
the first user turn, so a follow-up question simply continues the conversation that was actually
sent; that first reply uses the command's own model, later messages use the chat model like any
other conversation, and web search stays off for it.

Substitution (`AICommandEngine.render`, pure) settles the three edge cases explicitly:

- **Several placeholders** — every occurrence is replaced.
- **No placeholder** — the selection is appended after a blank line. This is exactly what the
  pre-AI-Commands prompts did (instructions as a system prompt, selection as the turn), so a
  customization written before this existed keeps working untouched.
- **A selection containing `{selection}`** — the template is split on the token once and the parts
  joined with the selection, so inserted text is never rescanned.

Spotter ships two commands, **Define Selected Text** and **Check Selected Text Grammar**. They are
ordinary records — same launcher entry, same shortcut recorder, same run path as one the user writes
— with a fixed identity: their ids, launcher entry ids (`command:selection-tools:define` /
`:grammar`) and shortcut keys (`KeyboardShortcuts_plugin.selection-tools.*`) are the ones they have
always had, which is why an existing binding, favorite, alias, learned rank or hidden-row choice
survives untouched. Their prompt, model and shortcut are editable and **Reset** restores Spotter's;
their name is not editable and they cannot be deleted, because those ids are what every existing
reference resolves through and a deleted one could not be recovered. A user who wants one gone hides
its launcher row and leaves it unbound.

User commands are added from the **Commands** group, whose **Add…** button rides the trailing edge
of the section header — adding belongs to the group rather than to the list, so it stays put as the
list grows instead of drifting down and reading as a last row. Each row names its command and offers
its way in (**Edit…**, plus **Reset** for a built-in or **Delete** for a user command); the prompt,
the model and the shortcut are that command's own configuration and are set inside its editor sheet
rather than restated on the row. A command that has not been saved yet has no id for a binding to
hang on, so the editor shows the shortcut recorder only when editing an existing command. They are
dynamic launcher entries, the shape
Commands uses for custom shell commands and Quicklinks for links. Each gets a shortcut recorder
because `AppEntry.hotKeyAction` resolves its entry id to `.aiCommand(id:)`; bindings live under
`KeyboardShortcuts_aiCommandHotkey.<uuid>`, are indexed in `boundAICommandIDs` so a deleted
command's shortcut is dropped, and deleting a command also clears its favorite, alias and learned
rank. Names are unique case-insensitively and can't shadow a built-in's.

The key remains the whole gate: with no OpenRouter key, every AI command — shipped or user-written —
reports that instead of capturing anything, and no request can be made. A user-authored prompt is
never a way around it.

Capture and missing-key failures render as chat status rows rather than a separate result list.

## Requests

`AIChatStore.send` appends the user turn, windows the transcript to a character budget
(`AIChatEngine.transcriptWindow`, newest kept, the latest message always surviving), prefixes the
system prompt, and calls the multi-turn `OpenRouterStore.chat(messages:model:)` with the dedicated
`chatModel` (default `anthropic/claude-sonnet-5` — chat carries multi-turn reasoning, so it defaults
a class up from the fast model the shipped AI commands pin; synced as `openRouterChatModel`). Requests carry a
`max_tokens` cap: OpenRouter reserves credits for the whole completion window up front, so an
uncapped request 402s on a small balance even when the reply would cost cents. The key is re-checked
on both sides of the await, replies are non-streaming in this version, and a failure renders as a
status row carrying OpenRouter's own error message, with the sent turn retained. The reply lands in
the session that asked, even if the user switched sessions while waiting; failures also log to
Settings → Diagnostics.

The store permits exactly one request across every session. Switching conversations never makes a
second send eligible: the footer continues to show Thinking, Actions can stop the owning request,
and an empty background session explains how to return to it. Replies and failures stay keyed to the
session that asked, so a background failure is still visible when that session is revisited. A stale
completion cannot clear a newer request, and rejected sends (busy state or missing key) leave the
composer text intact.

## Web search

An optional per-chat capability, off by default: when enabled (Settings → AI Chat & Command, or the ⌘K
toggle), requests carry OpenRouter's Exa-backed `web` plugin (`plugins: [{id: "web"}]`, 5 results),
letting replies cite current information. It rides the same key and the same consented request to
the same provider — no new network surface — but each search adds a small per-message cost, which is
why it ships off. Synced as `openRouterChatWebSearch`.

## Privacy

AI commands — names, prompts and model choices — are user content and ride the trusted v3 backup and
sync snapshot, as does each command's shortcut. Spotter conversations are included in trusted v3
backups and automatic sync, including the selected conversation. Without sync they remain
session-only; with sync, quitting and relaunching restores the latest shared snapshot. Messages go
only to OpenRouter under the user's own key. The ChatGPT handoff does not call a network API from
Spotter; it opens the encoded prompt in the default
browser, where the URL may be retained by normal browser history and ChatGPT processes it under the
browser's signed-in account.
