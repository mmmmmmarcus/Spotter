# Selection Tools plugin

Selection Tools owns two selected-text actions — **Search Selected Text** and **Translate Selected
Text** — plus **Translate Text**, an enterable page for text that is not selected anywhere. Search
opens Google Search in the default browser. Translate calls Google Cloud Translation Basic and
presents one row per configured target language, **translations first and the original last**: the
translation is what the user asked for, and the original is the input they already had. Every
completed row copies its own text with Enter, and rows carry no line limit — a translation the user
cannot read in full is not a translation.

The actions retain the stable `selection-tools.search` / `selection-tools.translate` shortcut IDs
and `command:selection-tools:*` launcher command IDs. Existing Hyper + T bindings survive the move
back from AI Chat because the translation action also keeps its original
`KeyboardShortcuts_plugin.selection-tools.translate` defaults key. Translate Text is a third action
(`selection-tools.translate-text`, `command:selection-tools:translate-text`) that resolves its
recorder through `AppEntry.hotKeyAction` like the other two. New installs ship all three unbound;
Settings recommends Hyper + S and Hyper + T.

## Selection capture

`AppCore` owns the shared `SelectedTextCapture` in `Core/SelectedTextCapture.swift`. Selection Tools
and AI Chat both use it. The Notes editor explicitly opts its native `NSTextView` into local capture,
so a selection inside Spotter Notes is read directly without Accessibility or the pasteboard; other
Spotter fields remain excluded. The selection is snapshotted before the palette takes focus, which
keeps launcher commands as well as global shortcuts working from Notes. External-app capture
snapshots `NSWorkspace.shared.frontmostApplication` synchronously before the first `await`, then
captures in tiers:

1. `SelectedTextReader` reads the focused control through Accessibility.
2. Chromium accessibility attributes are enabled temporarily and retried while its tree appears.
3. A guarded synthetic ⌘C snapshots and restores the pasteboard when canvas or web surfaces expose
   no Accessibility selection.

The fallback is suppressed from clipboard history for its whole lifetime and stamps the restored
pasteboard with Spotter's internal marker. Captured snapshots keep only the selected text, source
PID, app name, bundle identifier and capture time; the selected text is never logged.

Launcher commands first hide the palette through the existing focus-restoration path, then retry
only transient missing-frontmost-app states. `previousApplication` remains a focus destination,
never a source of selection data.

## Search

`SearchURLBuilder` stays Foundation-only. It trims only outer whitespace and creates an HTTPS Google
Search URL with `URLComponents` and one `q` query item. Spotter does not request Google itself;
`NSWorkspace` hands the URL to the default browser.

Capture, URL construction and browser-open failures render on the plugin's shared palette screen.

## Translation

`SelectionToolsManager` owns the Google translation configuration, request lifecycle and result
state.

**The API key is the gate.** There is no separate consent toggle: with no key no request can be
made and neither Translate Selected Text nor the Translate page can send anything, so entering a key — or syncing a settings file that
carries one — is the consent act. This mirrors `OpenRouterStore` and is recorded in `AGENTS.md` as a
deliberate owner decision, not a shape to copy for new networked features. The Settings key row names
Google Cloud Translation Basic, what is sent and the per-target billing; the manager re-checks the
current key after every request returns.

The key and the target list live in bundle-scoped `UserDefaults` and enter the trusted
`SettingsBackup` v3 snapshot, so clearing the key or editing targets propagates through sync. The
retired `googleTranslationEnabled` field stays in the Codable struct as decode-only, so an older
backup still opens. Requests use a private ephemeral `URLSession` with no URL cache and a fixed HTTPS
Cloud Translation Basic v2 endpoint.

### Targets and source detection

`TranslationLanguages.all` is a compile-time table of the languages Settings can offer — a language
menu is not worth a network round trip, and Settings has to render offline. Targets default to
`zh-CN` and `en`, and Settings adds them from a menu and removes them from the list. Each target gets
its own concurrent request and its own result row.

The source language is detected **on this Mac**, by `NLLanguageRecognizer`, before anything is sent.
When detection is inconclusive the selection is treated as English. Any target the selection is
already written in is dropped before the requests go out, so it costs neither a billable request nor
a row to skip past — an English selection with English among the targets simply has no English row.
Comparison is on the primary subtag, except for Chinese, where Simplified and Traditional are real
translations of each other and only an exact match counts. When *every* target is filtered out the
palette says so and points at Settings rather than showing an empty result.

The palette switches immediately to a loading snapshot of one pending row per target followed by the
original, so the original remains visible while the answers fill in. `SelectionToolsResults` owns
that ordering — targets-in-order, then the original — which is the flat selection index's visible
order. The shared `PluginPaletteList` owns selection, filtering, scrolling and Enter activation; the
plugin creates no custom window or list. Failures replace the rows with the provider or capture
error.

`Tools/selection-tools-test.swift` compiles the real `SelectionToolsResults` and pins the order for
both the loading and the finished snapshot, so a flip back would fail the harness rather than the eye.

## The Translate page

Translate Text opens the plugin's one palette screen in its **compose** state. There is no second
window, no text field of its own and no list chrome: the palette's own search field *is* the text
being translated, the way Kill Process filters with it and Quicklinks takes an argument in it.
`SelectionToolsManager.screen` says which surface the shared screen shows, is set only by the entry
point that opened it (`AppCore.openTranslateText`, or any of the selection flows), and publishes, so
switching surfaces invalidates the palette through the registration's normal observation.

**↵ is the only trigger.** While text is typed and nothing has been translated for it, the page shows
exactly one row — `Translate`, subtitled with the configured targets — and activating it is what
spends a request. Nothing is debounced because nothing fires on its own: a paid provider must not
bill a keystroke, so there is no timer to tune and no in-flight request to cancel on the next
character. Editing the text hands the action row back rather than leaving a finished translation
sitting under input that no longer produced it, and a run whose text has been superseded never
claims the newly typed text either. A failure keeps the row and moves the provider's message into its
subtitle with a Try Again title, so the retry is one ↵ away.

The page reuses everything the selection flow already owns: the same `translate(_:)` entry point, the
same on-device `NLLanguageRecognizer` detection (so a target the typed text is already written in
costs no request), the same configured target list, and the same copy-on-Enter rows. It shows no
`Original` row — the text is already on screen in the search field.

**The key is still the only gate.** With no key the page opens and says so, using the same
`GoogleTranslationError.missingAPIKey` message the rest of the plugin uses, and offers no row at all,
so there is nothing to activate and nothing can be sent; an empty target list reads the same way.
`SelectionToolsResults.snapshot` defaults `hasAPIKey` to `false`, so a caller that forgets to pass it
renders the blocked page rather than a live one. The page adds no preference of its own, so there is
nothing new to persist or to carry in the trusted v3 snapshot — the key and the target list already
ride it.

Clearing the key cancels the active request and clears its in-memory result. Disabling the plugin
cancels its active work, removes all three commands, makes their shortcuts no-ops and returns an
active plugin screen to the launcher.
