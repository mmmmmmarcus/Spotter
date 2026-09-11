# Translate plugin

Translate owns everything Google-Translate: the **Translate** page, an enterable palette screen whose
search field *is* the text being translated, and **Translate Selected Text**, which reads the
selection in the frontmost app. Both call Google Cloud Translation Basic and present one row per
configured target language. Every completed row copies its own text with Enter, and rows carry no
line limit — a translation the user cannot read in full is not a translation.

Split out of Selection Tools (now [Search](selection-tools.md)) in Sep 2026. The plugin ID is new
(`translate`), but nothing a user already had is: the two actions keep their original
`KeyboardShortcuts_plugin.selection-tools.translate` / `…translate-text` defaults keys, the two
launcher commands keep their `command:selection-tools:translate` / `command:selection-tools:translate-text`
IDs, and the API key and target list keep their `selection-tools.*` preference keys. A bound Hyper + T,
a favorited command, a ranked command and a stored key all survive the move untouched. Both actions
resolve their recorder through `AppEntry.hotKeyAction` like every other plugin command, and new
installs ship both unbound.

## The API key is the whole gate

There is no separate consent toggle. With no key no request can be made and neither surface can send
anything, so entering a key — or syncing a settings file that carries one — is the consent act. This
mirrors `OpenRouterStore` and is recorded in `AGENTS.md` as a deliberate owner decision, not a shape
to copy for new networked features. The Settings key row names Google Cloud Translation Basic, what
is sent, the per-target billing and the live-typing policy below; the manager re-checks the current
key after every request returns.

The key and the target list live in bundle-scoped `UserDefaults` and enter the trusted
`SettingsBackup` v3 snapshot under their existing `googleTranslationAPIKey` /
`googleTranslationTargets` fields, so clearing the key or editing targets propagates through sync.
The retired `googleTranslationEnabled` field stays in the Codable struct as decode-only, so an older
backup still opens. Requests use a private ephemeral `URLSession` with no URL cache and a fixed HTTPS
Cloud Translation Basic v2 endpoint.

## Targets and source detection

`TranslationLanguages.all` is a compile-time table of the languages Settings can offer — a language
menu is not worth a network round trip, and Settings has to render offline. Targets default to
`zh-CN` and `en`, and Settings adds them from a menu and removes them from the list. Each target gets
its own concurrent request and its own result row.

The source language is detected **on this Mac**, by `NLLanguageRecognizer`, before anything is sent.
When detection is inconclusive the text is treated as English. Any target the text is already
written in is dropped before the requests go out, so it costs neither a billable request nor a row to
skip past — an English text with English among the targets simply has no English row. Comparison is
on the primary subtag, except for Chinese, where Simplified and Traditional are real translations of
each other and only an exact match counts. When *every* target is filtered out the palette says so
and points at Settings rather than showing an empty result.

## What live translation costs, and what stops it costing more

The Translate page translates **as you type**. Google bills per request per target language, so the
policy that keeps that affordable is load-bearing, not an optimization:

1. **A pause, not a keystroke.** `TranslateManager.queryChanged` receives every edit and arms a timer
   for `TranslateTiming.typingPause` (1 second, owner decision, Sep 2026). Only silence that
   outlasts it spends anything. That
   constant is the single knob — retune it there and nowhere else. A sentence typed straight through
   costs one round of requests, not one per character.
2. **Nothing is ever paid for twice.** `TranslationMemo` keys a finished result by the exact text and
   the exact ordered target list. Retyping a phrase, backspacing into one already translated, or
   running the same selection again is answered from memory with no request at all. The memo holds
   `TranslationMemo.capacity` (24) entries, lives only in memory, is never written to disk, and is
   emptied when the API key changes — a different key is a different billing account.
3. **Superseded work is abandoned.** An edit that arrives while a request is in flight cancels that
   task, so a fast typist waits on the pause rather than on a queue of dead answers. Cancellation is
   honest about its limit: a request already on the wire may still be billed by Google. The pause is
   what prevents the request; cancellation only prevents the wait and the stale row.
4. **On-device detection still short-circuits.** A target the typed text is already written in is
   dropped before any request, exactly as in the selection flow.
5. **The blocked states send nothing.** With no key, or with no targets, the page opens, says what is
   missing and arms no timer at all.

A failure is the one place the page asks for a request back: it replaces the rows with a single
**Try Again** row carrying the provider's message, so a retry is deliberate rather than automatic.
Editing the text clears that failure instead of retrying it.

`TranslateManager` subscribes to the palette's query only while its screen is on stage
(`onOpen`/`onClose` on the palette-screen registration), so a page that is not open cannot type
anything at Google.

## Screens

`TranslateManager.screen` says which surface the plugin's one palette screen shows, is set only by
the entry point that opened it (`AppCore.openTranslate`, or the selection flow), and publishes, so
switching surfaces invalidates the palette through the registration's normal observation. The shared
`PluginPaletteList` owns selection, scrolling and Enter activation; the plugin creates no window, no
search field of its own and no list chrome.

**Selection.** Translate Selected Text switches immediately to a loading snapshot of one pending row
per target followed by the original, so the original remains visible while the answers fill in. The
finished snapshot puts translations first and the original last: the translation is what the user
asked for, and the original is the input they already had. Here the query *filters* rows. Failures
replace the rows with the provider or capture error.

**Compose.** The Translate page shows no `Original` row — the text is already on screen in the search
field — and the query is the input, never a filter. While the pause has not elapsed, or while a
result belongs to text that has since been edited, the page shows no rows and says
`Pause typing to translate into …` rather than leaving a stale answer under new input.

`TranslateResults` owns both orderings, which are the flat selection index's visible order.
`Tools/translate-test.swift` compiles the real `TranslateResults`, `TranslationMemo` and
`TranslationLanguages`, so a flipped order, a memo that re-bills or a page that renders without a key
fails the harness rather than the eye.

## Selection capture

Translate shares `AppCore`'s `SelectedTextCapture` with Search and AI Chat; see
[search](selection-tools.md#selection-capture) for the capture tiers and their guarantees.

`TranslateResults.snapshot` defaults `hasAPIKey` to `false`, so a caller that forgets to pass it
renders the blocked page rather than a live one. Clearing the key cancels the active request, empties
the memo and clears the in-memory result, and both commands then refuse rather than translating.

The Settings API-key field has a hidden label and an in-field example prompt; the provider disclosure and key persistence behavior are unchanged.
