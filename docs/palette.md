# Palette

The command palette is a borderless floating `NSPanel` hosting SwiftUI; see
[architecture.md](architecture.md) for window ownership.

## State flow

`PaletteViewModel` (mode / query / selection / `focusToken`) is the bridge between the panel and
`AppCore`. Showing the palette calls `prepare(mode:)`, which resets state and bumps `focusToken` (a
UUID) so the SwiftUI search field re-focuses. Every `focusToken` bump also snaps the list scroll to
the top — a reopen that preserved its state (Pop to Root Search's timeout) still starts reading from
the top rather than wherever it was left. `RootPaletteView` switches its content on `mode`:

- `.launcher` → `LauncherList`
- `.clipboard` → `ClipboardList` + preview
- `.calculatorHistory` → `CalculatorHistoryList`
- `.emoji` → the emoji grid
- `.aiChat` → the AI Chat transcript ([ai-chat.md](ai-chat.md)); the shared search field is the composer
- `.updates` → the Software Update status and install flow
- `.plugin(id)` → registry snapshot rendered by the shared `PluginPaletteList`

**Tab cycles empty root surfaces, Shift-Tab cycles them backward** — Apps → AI Chat → Clipboard →
Emoji → Apps. `PaletteMode.cycle(isPluginEnabled:)` is the single source of truth for the stop list,
read by both the key handling and the header glyph so the affordance can't promise a loop the keys
don't perform. Apps and AI Chat are system features and always present; Clipboard and Emoji drop out
when their plugins are disabled. Walking in both directions keeps every stop at most one press away
in some direction. Each hop goes through `prepare`, so the arriving surface starts with a cleared
query and selection — every surface has its own row order, and a selection carried across would
point at the wrong row.

With a typed launcher query, Tab instead enters a fresh AI Chat session and sends through Spotter's
OpenRouter-backed default. With a typed AI Chat draft, Tab sends in the current Spotter session.
Hyper-C (⌃⌥⌘C) sends a typed draft from either Apps or AI Chat to `https://chatgpt.com/?q=…` in the
default browser; Shift-Tab is always the plain backward cycle. Only the launcher's query
follows into chat — a clipboard or emoji filter string is dropped rather than sent as a message
nobody typed.

Every mode outside the cycle (Calculator History, Software Update, plugin screens) is a sub-screen
reached from the launcher by a command or a hotkey; Tab from one exits back to the launcher rather
than joining the cycle.

**Esc backs out one layer, matching Raycast.** An open confirmation cancels first, then an open
footer menu closes; then any non-launcher mode — cycle stop or sub-screen alike (clipboard, emoji,
chat, history, any plugin screen) — pops to a fresh launcher root; then a typed query
clears; only Esc at the empty launcher root hides the palette. Backspace in an already-empty search
is the same back gesture. Esc always means "out", never "previous stop": the cycle is Tab's, and
mixing the two would leave no way back to the root from the middle of it.

**Confirmations are in-palette.** Any destructive flow asks through `AppCore.confirmInPalette`,
which renders `ConfirmationCard` as a centered glass overlay: ←/→/Tab move the highlight, ↵
activates it, Esc cancels, and the highlight always starts on Cancel so a reflexive second ↵ is
never the confirmation. While the card is up, typing is frozen through the same channel as an open
footer menu. A confirmation requested with the palette hidden (a global hotkey) shows the palette
first and forces the compact bar to expand. There are no system confirmation dialogs in palette
flows; the one deliberate exception is Image Modification's Replace Original alert, which belongs to
its own workspace window.

Plugin palette screens reuse the same header search field, flat selection, keyboard navigation,
section/row grammar, edge dissolve, bottom action group and ⌘K overlay. The plugin supplies immutable
row snapshots plus primary/menu actions; it does not supply a view. A screen may also supply a
`livePlaceholder` (a prompt that changes per step — Quicklinks' argument entry) and an `adjustHours`
hook (←/→ hour scrubbing on an empty query — World Clock, whose screen also adds and removes cities
in place). Registry observation invalidates
the palette when the plugin's `AppCore`-owned manager changes. Kill Process is the reference screen.

The empty-query launcher can also host the single registered `launcherDashboard`. It appears above
the normal launcher sections inside the same scroll view, has no selectable rows, and disappears as
soon as the user types or enters another palette mode. Its visible lifecycle controls any refresh
work, so closing the palette leaves no minute timer or EventKit fetch running.

The flat `selection` index is the single source of truth for highlight / activation and **must always
match the visible selectable-row order**. The empty-query dashboard is non-selectable and renders
above background tasks; tasks still occupy the first indices, followed by the optional inline
calculator/plugin card, then app and command results. Every non-empty launcher query appends four
destination rows as the final result slice: AI Chat, ChatGPT web, Terminal and Finder file search.
See
[background-tasks.md](background-tasks.md) and [calculator.md](calculator.md).

In launcher mode an enabled plugin query provider may claim the inline card instead. The registry
returns the first claim in catalog order; otherwise the calculator is the fallback. There is still at
most one inline card; it follows any background-task rows. World Clock is the reference
provider (`SF time now`), implemented in `Spotter/Plugins/WorldClock/`. Its result adds a third local
system-time column. While that card is selected, → advances and ← rewinds the represented instant by
one hour (taking those keys from the field editor's caret in that state); ↑/↓ keep moving the flat
selection, and changing the query resets the offset.

World Clock also registers a normal plugin palette screen. Launching its command shows the saved city
rows through `PluginPaletteList`, with London, Shanghai and San Francisco as the first-run defaults.
Image Modification uses the same shared screen as the second level of Convert Image: choosing the
command shows writable target formats, and choosing a format is the action that starts conversion.

## Window placement

`PaletteWindowController` resolves an anchor (left edge + top edge) **once per summon** and reuses it
for every compact↔expanded resize, so only the height changes and the top edge never drifts. The
anchor is dropped on hide, so the next summon re-resolves for wherever the user is then.

Which display it anchors to depends on the **Follow the cursor across displays** setting
(`AppSettings.openOnCursorScreen`, on by default):

- **On** — the screen holding `NSEvent.mouseLocation`, i.e. the display under the pointer.
- **Off** — `NSScreen.main`.

`NSScreen.main` alone can't implement the follow-the-cursor case: it is documented as the *key window's*
screen, and an accessory app driving a non-activating panel has no key window on the display the user is
looking at, so `main` resolves to the menu-bar display regardless of where the pointer is.

The hit test is `NSMouseInRect(mouse, screen.frame, false)`, **not** `CGRect.contains`. A mouse location
is the CoreGraphics cursor position flipped about the primary display's height, so a screen's rows land
in the half-open interval `(minY, maxY]`: the topmost row is exactly `maxY`, which `contains` excludes,
while that same value is the `minY` of the display stacked above. `contains` would therefore hand a
pointer parked at the top of one display to its neighbour. `NSMouseInRect` exists for precisely this.

The panel is deliberately **not** movable by its background (`isMovableByWindowBackground = false`):
AppKit's background drag raced SwiftUI's `.draggable` widget cards, so grabbing a card to reorder the
strip would move the whole window instead. The only move affordance is a grab pill in a transparent
26pt strip across the top of the panel frame (`Core/PaletteDragHandle.swift`): the frame is one strip
taller than the visible glass, `PaletteWindowController`'s anchor names the *glass* top edge, and the
hosting view sits below the strip. The pill fades in when the pointer enters the strip or the glass's
top ~12pt (the latter via `sendEvent`'s `.mouseMoved` funnel) and fades out shortly after it leaves
both. The strip's transparent pixels are click-through at the window server, so the sliver of desktop
above the glass stays clickable while the pill is hidden; only the pill's drawn pixels grab.

Two hard-won invariants keep the pill and the palette grabbable — both trace to the same window-server
behavior: **a window's input region does not reliably follow programmatic moves** (per-step
`setFrameOrigin` drags, `setFrame` jumps on a visible window, even a same-turn orderOut/orderIn
cycle); the window then draws correctly but takes no clicks until the region lazily rebuilds, and the
next click inside it falls through to the window behind and dismisses the palette.

- **The drag is handed to the window server.** Past a 3pt slop, the pill's `mouseDragged` calls
  `performDrag(with:)` on its own window with the real event — the native path
  `isMovableByWindowBackground` uses, which keeps the input region valid throughout. Never move the
  panel with per-step `setFrameOrigin`.
- **The click-to-reset jump repositions the panel while ordered out**, with a runloop hop between the
  order-out and the `setFrame` + re-key (all three in one turn keeps the stale region), guarded by
  `isRepositioningVisiblePanel` so the transient resign-key isn't mistaken for a click-away.
- (And the fade-out must never run while the pointer rests on the strip — checked against the live
  mouse location, since a resting pointer never re-fires `mouseEntered` — or the user's next grab
  would fall through the just-faded pill to the desktop and dismiss the palette.)

A plain click on the pill — under the 3pt slop — forgets the remembered position and re-places the
palette at the computed default for the current screen. A user drag re-anchors the session via
`windowDidMove` (which reads the glass top edge as `frame.maxY` minus the strip), and with
**Remember position** on the anchor persists across summons. Each show also runs `InputSourceLock.selectASCIIKeyboard()` when General → "Lock input
method to English" is on, so the query field always starts in an ASCII layout.

## Menu-open input freeze

While a footer popover menu (⌘K Actions / app menu) is open the search field reads as inert but
**never resigns first responder** — resigning makes the `NSTextField` swap between its field-editor
and cell rendering, shifting the text / placeholder a point or two, so focus stays put. Input is
frozen instead:

- `RootPaletteView` mirrors the open state into `PaletteViewModel.menuOpen`, whose `didSet` fires
  `onMenuOpenChanged`.
- `PalettePanel.sendEvent` then swallows text-editing keystrokes while `menuOpen` (letting ⌘/⌥ chords
  and menu-nav keys through to SwiftUI `onKeyPress`).
- The caret is hidden by clearing SwiftUI's **own** live field editor's `insertionPointColor`. SwiftUI
  force-casts its field editor to a private subclass, so vending a custom one crashes — only the
  existing one can be tuned.

## Chords `onKeyPress` never sees

Some chords never reach SwiftUI's `onKeyPress` because AppKit has already spent them, and the next
silent chord will be one of these cases:

- **⌘.** is macOS's Cancel chord: AppKit binds it to `cancelOperation:` alongside Escape, so the field
  editor consumes it and `onKeyPress(keys: ["."])` never fires. It arrives instead through
  `PalettePanel.sendEvent`, which bumps `PaletteViewModel.pinChordToken`; `RootPaletteView` observes
  that and resolves the row from the same results the list renders, so which row gets pinned still
  comes from one place. The panel only intercepts it in the clipboard — everywhere else ⌘. keeps
  meaning cancel.
- **Shift-Tab** is AppKit's "previous key view" gesture: the field editor turns it into
  `insertBacktab:` and walks the key-view loop, which lands focus on the header's mode-glyph button — so
  `onKeyPress` never fires *and* the search field stops being first responder. `PalettePanel.sendEvent`
  intercepts it outright and bumps `PaletteViewModel.backTabToken`, which `RootPaletteView` observes
  and routes into the same `handleTab(shift:)` that plain Tab uses, so one chord keeps one meaning.
  Nothing in the panel is meant to be reachable by focus-walking, which is also why that button is
  `.focusable(false)`: a focus ring appearing on it mid-typing would be a stray control.
- **Bare Backspace, Return and Escape** are consumed by the field editor before the key-press chain,
  and come back through `onBareBackspace` / `onBareReturn` / `onBareEscape` on the same panel.

## Actions menu type-ahead

The Actions menu is the one place where the frozen keystrokes are reused rather than dropped, so it
matches the type-ahead of a native menu. `menuTypeaheadEnabled` gates this **narrower** than
`menuOpen`: only the Actions menu opts in, so a confirmation card and the app menu still swallow
arbitrary typing and a reflexive keystroke can never drive them.

While it is armed, `PalettePanel.sendEvent` routes unmodified alphanumeric keys into
`PaletteMenuTypeaheadBuffer` instead of the field editor, and Backspace edits that buffer. The live
search field is never touched — the query behind the menu is unchanged when the menu closes.
`RootPaletteView` observes `menuTypeaheadQuery` and moves the menu's highlight to
`PaletteMenuTypeahead.bestMatch`; Return then activates through the normal row path, so type-ahead
selects but never activates on its own.

The buffer restarts after `resetInterval` (0.8s) of inactivity, so a pause begins a new search rather
than appending to a stale one. Matching reuses `FuzzyMatch.score` from `Core/SearchRelevance.swift`
— the same scorer the launcher uses, not a second copy. `PaletteMenuTypeahead.swift` stays
Foundation-only and pure for `Tools/menu-typeahead-test.swift`.

## Focus restoration (load-bearing)

`PaletteWindowController` records `previousApp` (the frontmost app) on show. Paste then targets that
app:

- `Paster.paste` activates it and posts a synthetic ⌘V via `CGEvent`.
- `Paster.pasteInPlace` posts ⌘V straight to the app's PID _without_ activating it, so the palette can
  stay open and frontmost (used by "paste keeping window open").

Both require the Accessibility permission (`Permissions.ensureAccessibility()`).

The same show also mirrors that app into `PaletteViewModel.pasteTarget` (a `PasteTarget`: localized
name + bundle path), so Clipboard and Emoji can name it — the footer pill reads "Paste to Notes" and
the ⌘K paste rows carry the app's icon. Resolved once per summon, never per render, and deliberately
not cleared by `prepare` (pop-to-root resets the screen, not the target).
