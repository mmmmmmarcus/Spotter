# Selection Tools plugin

Selection Tools is one native plugin with three independently bindable actions and matching launcher
commands:

- **Search Selected Text** builds a Google Search URL and hands it to the default browser.
- **Translate Selected Text** sends the capture to OpenRouter and displays the translation in the
  shared Spotter palette.
- **Check Selected Text Grammar** sends the capture to OpenRouter and displays the corrected text
  plus each reported issue in the shared palette. There is no on-device fallback for either — the
  OpenRouter API key is the gate, and without one both actions report that a key is needed.

The actions use stable `selection-tools.search`, `selection-tools.translate` and
`selection-tools.grammar` IDs. The repository has no default plugin-shortcut seeding mechanism, so all
three ship unbound. Settings recommends Hyper + S/T/G, but the user records them through the standard
shortcut recorder and existing Carbon registration path.

## Selection capture

A shortcut action snapshots `NSWorkspace.shared.frontmostApplication` synchronously — before the
capture's first `await`, so it is always the app the user was in — converts the AppKit object into an
immutable Sendable source snapshot, and then captures in tiers. Only after a non-empty snapshot exists
may Search open the browser or Translate/Grammar activate Spotter's palette.

Capture is tiered, cheapest first:

1. **Accessibility** — the shared stateless `SelectedTextReader` reads the focused control's
   selection (`readAwaitingAccessibilityTree`).
2. **Chromium opt-in with retries** — when the first pass finds nothing, the reader enables both
   Electron's `AXManualAccessibility` and the assistive `AXEnhancedUserInterface` application
   attributes and retries over ~360 ms, because Chromium builds its accessibility tree lazily and an
   immediate retry always misses. A bounded walk from the focused window also checks `AXWebArea`
   elements, whose selection never reports as the focused element. Attributes this capture flipped
   are restored afterwards.
3. **Guarded ⌘C fallback** — canvas surfaces (Figma) and some web views never expose a selection
   through Accessibility at all. `SelectionCopyCapture` snapshots the pasteboard's items, posts a
   synthetic ⌘C to the source PID (mirroring `Paster.postCommandV`), waits up to ~700 ms for the app
   to write, reads the produced plain text, and restores the snapshot. Clipboard-history capture is
   suppressed for the whole window through closures `AppCore.start()` wires to `ClipboardManager`,
   and the restore carries the internal pasteboard marker, so neither the transient copy nor the
   restore ever enters clipboard history. An app that ignores the ⌘C entirely reports the
   empty-selection state; a copy that produces no plain text keeps the Accessibility error.

A launcher command starts while the palette already owns keyboard focus, so reading Accessibility at
that instant would inspect a source app whose focused control has resigned. The command first hides the
palette through its existing focus-restoration path, then re-reads
`NSWorkspace.shared.frontmostApplication` and the AX selection after the source app regains focus.
Transient missing-focus failures are retried briefly without blocking the main actor. The restored
`previousApplication` is only a focus destination; it is never treated as the captured source or used
to supply selection data.

The snapshot retains the exact selected text plus the source PID, app name, bundle identifier and
capture time. It never retains an `NSRunningApplication`, uses `AppCore.previousApplication` as
capture data, or logs the selected text. The ⌘C fallback is the one sanctioned pasteboard use: it
runs only after Accessibility failed, restores the user's pasteboard, and is invisible to clipboard
history. Change Case uses the same reader but keeps its older explicit clipboard-source fallback.

Native controls use `AXSelectedText`; Chromium/WebKit controls may instead provide
`AXSelectedTextMarkerRange`, which is resolved through `AXStringForTextMarkerRange`. The reader may
fall back to the system-wide focused element only when that element's PID still matches the captured
source PID, which prevents a Spotter control or another app from being mistaken for the original
selection.

Accessibility denial, a missing frontmost app, Spotter being frontmost, a missing focused control, an
unsupported selected-text attribute and an empty selection all become explicit shared-palette failure
states. Secure/password fields normally surface the unsupported-attribute state — macOS blocks both
their AX selection and their copy.

## Search

`SearchURLBuilder` is Foundation-only. It trims only leading/trailing whitespace for the query and uses
`URLComponents` with one `URLQueryItem(name: "q", value: text)`; it never hand-escapes characters.
Spotter does not request Google. `NSWorkspace` gives the URL to the default browser, and an invalid URL
or failed open switches to the Selection Tools palette error state instead of opening an empty page.

## AI providers (OpenRouter)

Translate and Check Grammar run exclusively through `Core/OpenRouterStore.swift`; there is no
on-device fallback (owner decision, Aug 2026) — without an API key both actions fail with an
explicit palette message pointing at Settings → General → AI. There is likewise deliberately
**no separate enable toggle**:
the key is the gate, and entering or syncing one is the consent act. Each action has its own model
(Settings → Plugins → Selection Tools), defaulting to `anthropic/claude-haiku-4.5`, chosen for
latency, instruction-following and multilingual quality on short interactive selections.

The store keeps the rest of `CurrencyRateStore`'s network shape: the key is re-checked on both
sides of every `await` (clearing it mid-flight discards the response), and requests run on a
private cacheless `URLSession`. The key and both models mirror into `SettingsBackup`, so a synced
Mac gets a working AI path immediately.

`Plugins/SelectionTools/SelectionLLM.swift` is Foundation-only and pure: target-language choice
(first preferred language; text already in it goes to the next preferred, else English), prompt
construction, code-fence stripping, and grammar-JSON parsing (corrected text plus issues with
left-to-right anchored ranges; a non-JSON reply degrades to "the whole reply is the corrected
text"). `OpenRouterSelectionServices.swift` adapts it to the same
`SelectionTranslationServing`/`SelectionGrammarChecking` protocols the system services implement, so
the manager, state machine and palette are identical on both paths. An OpenRouter failure surfaces
as one explicit palette error naming Settings → General.

## Translation and grammar engines

`OpenRouterSelectionServices.swift` holds both engines. Translation detects the source language
locally with `NaturalLanguage`, picks the target from the user's preferred system languages
(`SelectionLLM.targetLanguage`), and asks the configured translation model for the translation
alone. Grammar asks the configured grammar model for the corrected text plus a JSON issues list;
`SelectionLLM.parseGrammar` anchors each issue's range left-to-right in the original text and
degrades a non-JSON reply to "the whole reply is the corrected text". The former on-device
`TranslationSession`/`NSSpellChecker` services were removed with the fallback path.

## State and palette

`AppCore` solely owns the `@MainActor SelectionToolsManager`. Its Foundation-only state machine assigns
a monotonically increasing generation to each request. Starting another action cancels the previous
Task; completion, failure and cancellation updates must still match the active request, so a stale
Translate result cannot replace a newer Grammar state.

Translate and Grammar set loading before opening `PaletteMode.plugin(.selectionTools)`. The registry's
observer refreshes `PluginPaletteSnapshot` as the manager publishes loading, success or failure. The
screen uses only `PluginPaletteList`: translated/corrected text is the first row and Enter copies it,
the original text remains available, and Grammar adds one row per issue with its explanation and first
suggestion. No plugin window, search field, scrolling model, footer or notification is created.

Disabling the plugin cancels and resets pending work, removes its commands from the launcher, makes its
saved shortcuts no-op and returns an active Selection Tools palette to the launcher. It persists no
content and has no network-consent state.
