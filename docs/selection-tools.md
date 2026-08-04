# Selection Tools plugin

Selection Tools is one native plugin with three independently bindable actions and matching launcher
commands:

- **Search Selected Text** builds a Google Search URL and hands it to the default browser.
- **Translate Selected Text** uses the macOS Translation framework and displays the result in the
  shared Spotter palette.
- **Check Selected Text Grammar** uses the local macOS spelling and grammar service and displays the
  corrected text plus each reported issue in the shared palette.

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

## Translation and grammar providers

Translation uses `TranslationSession(installedSource:target:)`, available on macOS 26 for non-UI
contexts. `NaturalLanguage` identifies the source; the target is chosen from the user's preferred
system languages. The installed-source initializer cannot request downloads, so Spotter uses only
language assets already installed by macOS. Translation runs asynchronously and selected content is
processed on-device. A missing language asset is reported explicitly; Spotter does not add an external
provider, API key, network consent or fabricated fallback.

Grammar uses `NSSpellChecker.requestChecking` with the grammar checking type. The system completion is
decoded immediately into Sendable ranges, descriptions and corrections. A pure response mapper applies
the first available correction from the end of the string toward the beginning, preserving valid
UTF-16 ranges, and retains issues without an automatic correction for display.

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
