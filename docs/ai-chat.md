# AI Chat

AI Chat uses Quick AI Chat as its only conversation surface. The launcher commands, ⌥Space,
AI commands, running-task rows and the launcher's Ask AI fallback all open the floating panel.
⌘↵ with a typed launcher query opens a new conversation and sends it. The main Palette no longer
contains a chat mode, composer, history list or chat actions menu; Tab cycles Apps, Clipboard and Emoji.
The launcher's Send to ChatGPT fallback remains a separate browser handoff.

The compact input has a separate 32-point circular clock button on its right, matching its glass
and vertical gradient. It opens up to ten recent nonempty sessions as a vertical stack of independent
32-point capsules above the input, with 8-point gaps. The picker is as wide as the expanded chat.
Selecting a capsule replaces the picker with its conversation at the same width and grows upward
to the full conversation height. There is no sidebar or date grouping. Short screens scroll the pills.
The expanded header has a draggable area followed by History, New Chat and Close on the right.
Session switching preserves per-session unsent drafts and attachments; the picker retains Copy and
Delete in each capsule's context menu. Opening history never creates a blank session. History remains
in existing backup/sync data, while drafts remain local in-memory state.

AI Chat is an always-available system feature, shown in the Settings sidebar as **AI Chat &
Command**, but remains inert without an OpenRouter API key — the key is the gate and lives on that
same pane's **AI (OpenRouter)** card, moved there from General in 1.6.0 so the gate sits with the
feature it gates (entering or syncing a key is the consent act). The field is titled **Open Router API key**
and carries no example or standing explanatory text. Checking progress and validation results still
appear below it. The key remains included in settings backups and sync. AI Chat also owns **AI commands**, the prompts that run on
selected text; Define Selected Text and Check Selected Text Grammar are the two Spotter ships.
Google-powered translation lives in the [Translate](translate.md) plugin. Its implementation lives in
`Spotter/Plugins/AIChat/` so it can reuse the registry's Settings, command, permission and shortcut
plumbing without being presented as an optional plugin.

## Files

| File | Role |
| --- | --- |
| `AIChatTypes.swift` | Foundation-only, pure: portable message/session models, derived session title, the request status vocabulary, system prompt, transcript windowing and ChatGPT web URL. |
| `AIChatStore.swift` | The conversation, the one in-flight request, and failure state. |
| `AIRoutingTypes.swift` | Pure Foundation categories, preferences, bounded decision input and strict category-to-model mapping. |
| `JevDecisionClient.swift` | Bounded, cacheless OpenRouter Decisions transport for Jev. |
| `AIToolTypes.swift` | Foundation-only JSON values, MCP configuration validation, tool calls and multimodal result conversion. |
| `AIMCPConnection.swift` | Per-request MCP client: stdio processes and cacheless Streamable HTTP/SSE. |
| `AIToolStore.swift` | AppCore-owned configuration, tool discovery, bounded model/tool loop and approval continuations. |
| `AIToolSettingsView.swift` | Individual device-local MCP server editors and per-call confirmation. |
| `AIChatSelectionPrompts.swift` | Foundation-only: the prompts the two shipped AI commands start with. |
| `AICommand.swift` | Foundation-only, pure: the AI command record, built-in identity, `{selection}` substitution and list repair. |
| `AICommandStore.swift` | Foundation + Combine: the saved commands, their validation and the upgrade from the old prompt/model keys. |
| `AIChatLink.swift` | Foundation-only URL policy and Codex file/line reference normalization. |
| `AIChatPlugin.swift` | Registration and floating conversation entry points. |
| `AIChatView.swift` | The floating transcript and message rows. |
| `QuickAIChatController.swift` | AppCore-owned floating chat, composer state, focus and frame changes. |
| `QuickAIChatPanel.swift` | A native Liquid Glass panel with an invisible header drag area. |
| `QuickAIChatView.swift` | Compact composer and expanded conversation using the shared `AIChatTranscriptView`. |
| `QuickAIChatLayout.swift` | Pure Foundation + CoreGraphics placement and bottom-anchored expansion. |
| `AIChatMarkdownView.swift` | Transparent, self-sizing WebKit Markdown view and explicit link/copy bridge. |
| `AIChatSettingsView.swift` | The OpenRouter API key, the chat model and web search, plus the AI command list and its editor sheet. |

`Core/OpenRouterModelCatalog.swift` is Foundation-only and pure too: it turns the `/models` payload
into the brand → model menus.

`Tools/ai-chat-test.swift` compiles `AIChatTypes.swift`,
`AIRoutingTypes.swift`, `AIChatSelectionPrompts.swift`, `AICommand.swift`, `AICommandStore.swift` and
`Core/OpenRouterModelCatalog.swift` standalone, so these stay free of AppKit and SwiftUI. The
network lives in `OpenRouterStore`, never in any pure source.

## Quick AI Chat

**⌥Space** toggles Quick AI Chat, also available as a launcher command and a configurable action in
Settings → Shortcuts. The default is seeded once if unbound and conflict-free; existing shortcuts
and deliberate unbinding are preserved. Older settings snapshots that do not know this action
cannot erase it.

This is an owner-requested independent floating surface, owned by `AppCore` through
`QuickAIChatController`. It opens centered near the bottom of the cursor's display, 20 points above
the visible frame's bottom edge, so a bottom Dock stays clear. One native Regular Liquid Glass
surface contains a roughly 209-point-wide, 32-point-high composer labelled **Ask Spotter** (one-third
of the palette width and half its compact height). Return sends. Expansion has two stages: accepting
the first prompt doubles the width to 418 points and opens a 220-point waiting conversation; the
first nonempty assistant text expands directly to the final 475-point height. Further tokens and
follow-ups scroll without changing the size. New Chat restores the 209-point compact width when history is closed. Closing
and reopening retains the attained stage. Replies for another session cannot resize this window.
After a drag, expansion preserves the current horizontal center and bottom position, clamped to fit
the visible screen. SwiftUI never owns the window frame. Compact glass corners use half-height
circular ends; expanded corners use a 26-point continuous radius. The native WindowServer shadow is
invalidated as the glass resizes. The panel has no extra handle strip. Its Siri-inspired backdrop
fades evenly from black to 35% black opacity from top to bottom while compact; after expansion it
keeps the reading area dark and fades to the same 35% opacity near the bottom. Regular glass gives
the background stronger native blur. `Theme.QuickAI`
maps light system appearance to a black surface with light text, and dark system appearance to a
white surface with dark text, updating an open panel when the system changes. In dark mode the
white gradient ends at 18% opacity, with its expanded 90% stop at 40%; light mode retains the
black gradient’s 35% bottom opacity.

The expanded view uses `AIChatTranscriptView`: user bubbles, Markdown,
streaming line reveal, tool activity, errors and follow-to-bottom behavior. Before the first reply,
the 120-point transcript starts at the submitted prompt without a top fade or automatic bottom scroll. A bottom composer supports
follow-ups and Stop inside a native regular Liquid Glass capsule, with no solid fill or custom border.
History, Close and New Chat use tinted native interactive circular glass, with equal 12-point top and side insets, matching the composer’s outer side and bottom padding. The close button appears to the right of New Chat in expanded mode; the compact
composer has no close button. Escape, ⌘W and the shortcut can hide either state; closing
keeps the conversation and unsent draft in memory for the next summon. It stays visible on click-away,
and the shortcut refocuses it when it is not key. New Chat (⌘N) returns to a fresh input while
keeping the previous conversation in the shared history. The blank header region to the left of History, New Chat and Close uses native window dragging without a visible
handle. The buttons, transcript and composer keep their own click and text-selection behavior. Reduce Motion disables frame animation.

Quick Chat uses `AIChatStore`, OpenRouter settings, the key gate and the single in-flight request gate.
Quick Chat selects the current session in the shared history; every request,
partial reply and failure remains scoped to the session that asked. Rejected sends keep the draft.
Conversations use the existing trusted history backup/sync; window state and unsent drafts are
process-local and are not synced. Closing does not cancel an answer: background tasks can return to
the floating conversation. Screenshot's Hide Spotter path also hides this panel.

MCP/Cua calls retain the Cancel-first palette confirmation. A tool approval hides Quick Chat and
restores its previous input target before opening that confirmation; ⌥Space resumes the floating
conversation afterward. No separate model, connection, permission or automatic tool approval is added.

## Choosing a model

### Automatic selection with Jev

Settings → AI Chat & Command → **Model Selection** shows right-aligned model menus for Everyday,
Professional and Deep Reasoning. Jev classifies the first unpinned turn of each conversation automatically, with no enable
switch. Entering the pane reloads the model catalog; no Chat Model or Reload row remains. The three
rows contain titles and model menus only.

Each category preserves its saved model. Empty legacy mappings are initialized from the previous
Chat Model (or Spotter's shipped default). Jev is available whenever the OpenRouter key exists;
legacy disabled flags are ignored. TypeSafe receives the prompt and bounded recent conversation
through OpenRouter on each classification, adding the decision charge. Model mappings ride trusted
backup/sync, and a legacy file omitting `aiRouting` leaves the receiving Mac's choices intact.

`OpenRouterStore` owns this configuration and checks the key and configuration revision
around the await. `AIChatStore` includes classification within its existing single-request gate;
both the palette and Quick AI share it. Stop cancels classification, and a late decision cannot
dispatch or relabel another request. Changes to routing settings cancel an active classification.

This calls `typesafe/jev-1.13` through `POST https://openrouter.ai/api/alpha/decisions`, not the
provider's automatic Jev Router. Jev receives a Choice question over the three categories, the full
latest user prompt and up to six recent user/assistant turns, capped at 16,000 UTF-8 bytes total.
System instructions, tool results and screenshots are excluded. An over-limit latest prompt skips
classification instead of silently truncating it. The request times out after at most eight seconds
with a 64 KiB response cap and no on-disk URL cache.

Spotter accepts only the three configured category keys, a valid probability distribution and a
choice matching its maximum. The initial conservative routing policy requires top probability at
least 0.6 and a lead of at least 0.2; these are product thresholds, not a claim of calibrated task
accuracy. An uncertain, malformed, unavailable or timed-out decision uses the captured Everyday model
and labels the fallback. Authentication failure, cancellation or withdrawn access never fall back.
Once an answer or tool call starts, failures are preserved rather than rerunning with another model.

In the full Palette, a branch symbol and requested model name appear above routed assistant replies; Quick AI Chat hides this caption. the chosen
category and fallback details are available in its tooltip. This metadata remains with the reply
through streaming, Stop, history and backup. They describe Spotter's selection; choosing
a provider-side router as a target still delegates its final internal model selection to that provider.
Old messages without this optional metadata remain readable. Explicit command model pins skip Jev;
commands set to Default use automatic selection when enabled. Follow-ups reuse the session’s selected model.

API contract: [OpenRouter Jev tutorial](https://openrouter.ai/docs/guides/community/jev-tutorial).

### Manual selection

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
other model. Switching that command back to **Default** is one menu away; Default
uses automatic selection and its menu says **Automatic (Jev)**.

The list is fetched only once a key exists: the key remains the gate, an absent key clears the
catalog, and the request itself is unauthenticated and carries nothing about this Mac or its
conversations — it reads the same public catalog anyone can. It rides the same cacheless session as
every other OpenRouter call.

## Reply formatting

Codex `exec --json` wraps the answer in `item.completed` / `agent_message.text`; Spotter retains
that text verbatim and keeps commentary and tool/command logs out of the reply. Formatting follows
CommonMark plus the tables, task lists, strikethrough and local file links used by Codex's CLI renderer.

`AIChatMarkdownText` uses a transparent, self-sizing `WKWebView` with a nonpersistent data store.
The bundled markdown-it parser handles headings (ATX and setext), nested lists/quotes, task lists,
hard/soft breaks, reference links, bare URLs, inline emphasis/code, escaped pipes, tables and fenced
or indented code. highlight.js renders code syntax; code blocks have language labels and Copy.
KaTeX renders inline/display mathematics and Mermaid renders complete diagram fences after streaming
finishes; invalid diagrams retain readable source. Footnotes link within the containing transcript.
All scripts, styles and fonts are bundled locally, with pinned dependencies and licenses in
`Resources/AIChatMarkdown`; there is no CDN or automatic rendering request.

Links are visibly underlined and dispatched explicitly through the native bridge. HTTP(S) and email
links open the system handler. Codex file references resolve relative to the dedicated CLI workspace,
including `:line[:column]` and `#Lline` suffixes; Xcode/VS Code/Cursor receive line numbers when they
are the associated editor, otherwise Finder reveals the file. Unsupported schemes are not dispatched.
Image Markdown becomes an explicit Open Image link, matching the CLI's text-oriented output without
silently fetching remote resources. Raw HTML is escaped, KaTeX trust is off and Mermaid uses strict
mode; the page CSP disallows network connections, frames and image requests. User turns stay literal.

Streaming updates are throttled to 40 ms with the latest text, and newly added vertical space reveals
over 140 ms unless Reduce Motion is enabled. ResizeObserver reports the actual document height as
text, diagrams, fonts or window width change. A renderer failure falls back to selectable raw text.
Text selection spans the whole answer; code Copy preserves its source, and the history picker can
copy the raw conversation. `Tools/ai-markdown-test.swift` exercises actual bundled assets in WebKit,
including clickable link and copy events, rich blocks, CSP, resizing and incomplete streamed fences.
`Tools/AIChatMarkdown/test.mjs` additionally pins parser edge cases when rebuilding the assets.

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
  Conversation, New Session, Delete Session, and AI Chat Settings… Delete Session uses the shared
  in-palette confirmation card with Cancel selected first.
- **Esc** backs out to the launcher (the standard ladder); the conversation survives, and re-entering
  chat resumes it. An in-flight request appears there as an indeterminate background task **titled
  with the conversation** — `AIChatSession.title`, so an override (a selected-text action) wins and
  everything else derives from the first user turn — and subtitled with its status: `Thinking…` while
  in flight, `Reply ready.` on success, OpenRouter's own message on failure. Several finished AI rows
  are therefore told apart by the questions that made them. A send always appends the user turn
  before the row is titled, so the untitled fallback (`New Session`) is unreachable in practice;
  success or failure remains dismissible while Stop Waiting discards the row. In a transcript ↑/↓
  do nothing because messages are not selectable rows; on the fresh-session History surface they
  navigate conversations.
- `AIChatMode` is a core `PaletteMode` (like Emoji) rather than a `PluginPaletteList` screen: a
  conversation flow is not a filter-a-list interaction, and the emoji grid is the precedent for a
  mode with its own body view while the plugin carries the launcher command and the
  shortcut.

## AI commands

An **AI command** is a name, a prompt, a shortcut and a model choice. The prompt is a template:
`{selection}` — the same single-brace shape a quicklink's `{argument}` uses — is where the selected
text lands. Running one captures the selection through the `AppCore`-owned `SelectedTextCapture`,
renders the prompt, opens a new titled chat session and sends immediately. Commands always open Quick AI Chat. The old surface preference is ignored. Each command has an editable SF Symbol, shown in Settings, launcher results and compact user bubbles; old records keep their existing default icon. Floating command sessions and their
capture/key errors open their owning floating conversation. Opening a command preserves
an unsent floating composer draft.

The rendered prompt remains the first model-facing user turn. Optional `AIChatMessage.commandInput`
metadata snapshots the command name and original selection, so the bubble shows a secondary-colored
`command` SF Symbol beside only the selection. Both chat surfaces share this rendering. Follow-ups
remain normal text bubbles and still send the original full prompt as context. Metadata survives
history and sync; older messages without it retain their existing display. The first reply uses the
command's own model; later messages use the chat model like any
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

User commands are added from the **Commands** group, whose **Add…** button sits below the list
card in a trailing-aligned section footer. Each row names its command and offers
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

AI Chat and AI commands request OpenRouter SSE streaming. A stable assistant message reveals complete visual lines; a transient draft is committed once on completion, Stop, or failure, preserving partial text. Session changes never redirect an active reply. SSE framing handles UTF-8, comments, multiline data, usage frames and provider errors; EOF without [DONE] is a failure. The 1 MiB event bound includes the newline separators between data lines, including empty fields. Transport is cancelled on Stop and late delivery checks the exact request key.

The bundled Markdown renderer follows actual WebKit document height at the current width; streaming reveals new vertical space without hiding existing text. Completion, Stop and failure render all received text. Reduce Motion disables the reveal.

History rows show the session's source icon: translation, definition, grammar check, or chat.
AI commands capture their own symbol when creating a session, including a failed start, and the
optional `sourceSystemImage` travels with the session in backup/sync. Earlier sessions without this
field recover the three shipped selection-action icons from their fixed `titleOverride` values;
ordinary message text never determines the icon. The Sessions menu uses the same source icons,
with the current session still marked by a check.


## MCP and Cua experiment

Settings → AI Chat & Command → **MCP** lists servers individually with Add Server, Edit and Delete. Editors expose local executable/arguments/environment or HTTP URL/headers. Servers are active once saved. The OpenRouter key and per-call confirmation still apply. Persistence uses the common `mcpServers` JSON shape:

```json
{
  "mcpServers": {
    "local": { "command": "/absolute/path/to/server", "args": ["--stdio"], "env": {} },
    "remote": { "url": "https://example.com/mcp", "headers": { "Authorization": "Bearer …" } }
  }
}
```

Only Streamable HTTP is supported for remote servers; legacy standalone SSE and OAuth discovery
are not implemented. Only tools are exposed to the model; resources, prompts, sampling and elicitation
are not implemented. Bounded initialization notes are supplied as untrusted reference context. HTTPS is required except on localhost. HTTP redirects are refused so configured
credentials cannot be forwarded to another endpoint. Local commands use argv without a shell, a
small explicit environment, and the user's home as working directory. Commands execute as the user:
only trusted servers belong in this configuration. Header/environment secrets are stored with local
settings, not in Keychain. `ai-chat.mcp-configuration` lives in the app's bundle defaults domain and is excluded from backup
and sync. Configured servers are always available during chat requests; the old
`ai-chat.tools-consent` flag is ignored. Saving configuration cancels active work and clears tool
activity; new servers become available on the next request. No servers means ordinary streaming.

A one-time default migration inserts a `cua` server first in the list with the installed `cua-driver` executable and `["mcp"]` arguments.
Deleting this default is permanent across relaunches. Install [Cua Driver](https://cua.ai/docs/how-to-guides/driver/connect-your-agent) separately; Spotter
does not bundle or auto-update it. CuaDriver.app owns its Accessibility and Screen Recording grants;
Spotter never grants them or treats Spotter's grants as Cua's. This preset operates the current Mac,
not a VM. Driver installation and a model that supports both tools and images are required for the
complete Computer Use flow. Tool discovery is isolated per server: a missing executable, failed
connection or invalid catalog removes only that server from the request. No partial catalog or usage
instructions from a failed server reach the model. Discovery details remain in the collapsible local
tool activity, while healthy servers stay usable. If no tools remain (including an empty configuration),
chat uses the ordinary streaming transport with the same selected model and web-search setting. The
model receives an explicit capability limit and is instructed to mention unavailable tools only when
the request needs them; local executable paths and connection errors stay out of that model context.
Actual tool execution failures, denied approvals, model errors, cancellation and changed configuration do
not trigger fallback. There is no fallback to another computer-use implementation.

Enabling tools explains that configured processes/servers are contacted during chat requests only,
and their descriptions, arguments, results and Cua screenshots may reach OpenRouter and the selected
model provider. The OpenRouter key gate also applies. No MCP connection is opened at launch or from
merely editing configuration. Define/Grammar and other selected-text commands retain ordinary chat
for their first answer; they do not execute tools. Normal chat remains streaming. In tool mode, each
model round returns a complete message before requesting a tool; up to 12 rounds and 128 discovered
tools are supported, with one tool call per round.

Every tool call displays its server, tool name and JSON arguments through `confirmInPalette`.
Cancel is selected initially. Closing that card, dismissing the palette, stopping the background
request, changing the key, changing configuration prevents further calls.
Confirmation hides the palette and restores focus before executing Cua. Stop cancels network work
and closes the per-request MCP processes; an action already dispatched to an external server cannot
be rolled back. Connections and the key are checked on both sides of every asynchronous step.

The transcript exposes a collapsible tool activity list and current progress with Stop. Activities
are bounded to 100 in-memory entries and cleared when configuration changes. Text results are bounded;
PNG/JPEG/WebP image blocks go to the model as multimodal observations, with only the newest tool's
images retained. Images, tool arguments, raw results and model reasoning are not added to saved chat
sessions or sync. Follow-up requests start new MCP connections and fresh observations. The system
prompt treats tool, page and screen contents as untrusted data and requires observed targets and
verification rather than guessed coordinates or success claims from dispatch alone.

`Tools/ai-tools-test.swift` compiles the real configuration, transport and tool store against a
scripted model and `Tools/Fixtures/ai-mcp-server.py`. It covers stdio, HTTP JSON/SSE, session headers,
server ping, pagination, RPC errors, redirects, multimodal conversion, approvals, cancellation and
configuration/key changes, missing-driver streaming fallback, mixed healthy/unavailable servers, partial
catalog rollback and revocation during discovery/fallback without contacting a model or reading the desktop.

Live progress reflects actual request stages: choosing a model, waiting for a reply, generating text,
connecting tools, planning a tool round, waiting for confirmation and running a tool. Each stage has
a matching SF Symbol and a left-to-right text highlight, disabled with Reduce Motion. Model captions
show only the branch symbol and selected model name; routing category/fallback details remain in the tooltip.

## Local CLIs, attachments and formulas

The three Jev routing tiers may select `Claude CLI` or `Codex CLI` alongside OpenRouter models.
`LocalAIStore` discovers a usable executable through common package-manager locations and a login
shell, verifies it with `--version`, and passes the bounded conversation through stdin.
Settings → AI Chat → Multiple Providers offers Enter Path for each provider; saving an empty path restores automatic detection.
Explicit paths take precedence without silently falling back when invalid; validation errors remain
visible. Paths are device-local UserDefaults, scoped to the bundle identifier and excluded from
backup/sync. Validation has a three-second timeout and ignores stale discovery results. Both
validation and chat prepend the selected executable directory to PATH for npm/nvm dependencies. Claude runs
in print mode with only WebSearch allowed when Jev selects it; Codex runs `exec --json` in its read-only sandbox. Both use the
bundle-scoped `Application Support/<bundle-id>/AIChat/Workspace` directory, created with owner-only
permissions, rather than the user's home directory. CLI login/configuration locations remain unchanged;
the working directory is not a new filesystem sandbox. Codex replies come only from completed
`agent_message` events after `turn.completed`; diagnostic output, reasoning, tools and prompt echoes
never become the answer. Failed runs display a bounded error, with specific guidance for incompatible
model caches and model-refresh timeouts. See [Codex non-interactive output](https://learn.chatgpt.com/docs/non-interactive-mode).
MCP and Cua remain OpenRouter-only. Web Search follows Jev on OpenRouter, Codex and Claude; unavailable Jev decisions leave search off. A missing or broken CLI fails that request without changing provider.

The paperclip in Quick AI Chat and **Attach Files…** in AI Chat Actions accept up to ten local files.
UTF-8 and BOM-marked UTF-16 documents (including SVG source) and PDF text are read locally; scanned PDFs use Vision. Raster images are downsampled to 1568 pixels and sent as actual PNG images, including images with no text. OpenRouter receives image content blocks; Codex receives temporary image files removed after the request; Claude receives structured image input. Failed files are named explicitly, while accepted files remain attached. A message is limited to 10 files and 20 MB. Inputs and
extracted content are bounded before being included in the user turn. Attachment names render under
the user's bubble and the extracted text becomes part of that turn's saved model context.

Assistant replies recognize display math delimited by `$$…$$` or `\[…\]`. The renderer uses the
system serif face and maps common TeX operators and Greek names to mathematical Unicode while
retaining selectable source and an accessibility label. Unsupported TeX remains visible instead of
loading a network renderer.

Quick AI Chat opens with a 220 ms fade and an 8-point upward settle, and closes with a
140 ms fade. Its two expansion stages use a 300 ms critically damped response without overshoot;
interrupted transitions resume from the current frame. Reduce Motion removes window movement and
keeps the fade. Screenshot cleanup hides the panel immediately. Waiting and tool progress are
text-only with the existing shimmer; failure rows retain their warning symbol.


### Codex CLI model selection

The existing routing-category menus expand Codex CLI into concrete models read locally from
`codex debug models --bundled` when Settings opens. This bundled catalog does not verify account
entitlement; Codex checks availability when invoked. Older CLIs that cannot report the catalog
retain Use CLI Default and any saved selection. Concrete selections are stored as
`local-cli/codex/<slug>` and passed as a separate `--model` argument; the legacy `local-cli/codex`
value continues to use CLI configuration. Opening Settings makes no model-inference request.

Jev runs for the first unpinned turn of a conversation. The selected model is retained on the
session and included in existing history persistence; later turns reuse it. Previously saved
routing metadata supplies the model for older sessions. Changes to category mappings affect new
conversations. Explicit command model selections also pin their conversation.


## AI settings organization and per-turn search

Settings groups are Multiple Providers (OpenRouter key, Claude CLI, Codex CLI), Model Selection
(the three category mappings), Commands, and MCP. There is no surface toggle or Web Search toggle.
Jev receives a separate `web_search` choice on every turn, including explicitly pinned commands and
follow-ups. Follow-ups omit the model-routing question and preserve the session's model. Ambiguous,
missing or unavailable search decisions leave search off. No OpenRouter key means no Jev call.
Quick Chat uses Enter to submit; its paperclip is on the right and the send arrow is removed.

Attachment staging follows Tinycast's approach of named refusals and bounded native images
([upstream reader](https://github.com/abue-ammar/tinycast/blob/71279c8de18fe77c56aa1cfaaeb68bf07748bbdd/Tinycast/Features/AI/UI/ChatAttachmentReader.swift)); SVG source and UTF-16 support are Spotter additions.
Local search arguments follow [Codex Web Search](https://developers.openai.com/codex/web-search)
and [Claude CLI reference](https://code.claude.com/docs/en/cli-reference).

Quick AI Chat animates each successfully submitted user message from the composer's bounds to its
transcript row using a short spring. A temporary overlay crosses the scroll-view boundary while the
real row reserves its layout; history reopening does not replay it. Closing or switching conversations
clears the transient message identity. Reduce Motion uses a brief fade without displacement or scale.

History capsules use the solid Quick AI backdrop token. Selecting a capsule shares its background geometry with the conversation during a short spring, fading in the transcript. Reduce Motion uses only a fade.
