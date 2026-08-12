# Palette

The command palette is a borderless floating `NSPanel` hosting SwiftUI; see
[architecture.md](architecture.md) for window ownership.

## State flow

`PaletteViewModel` (mode / query / selection / `focusToken`) is the bridge between the panel and
`AppCore`. Showing the palette calls `prepare(mode:)`, which resets state and bumps `focusToken` (a
UUID) so the SwiftUI search field re-focuses. `RootPaletteView` switches its content on `mode`:

- `.launcher` → `LauncherList`
- `.clipboard` → `ClipboardList` + preview
- `.calculatorHistory` → `CalculatorHistoryList`
- `.emoji` → the emoji grid
- `.aiChat` → the AI Chat transcript ([ai-chat.md](ai-chat.md)); the shared search field is the composer
- `.updates` → the Software Update status and install flow
- `.plugin(id)` → registry snapshot rendered by the shared `PluginPaletteList`

**Tab cycles empty root surfaces** — Apps → AI Chat → Clipboard. AI Chat is always included as an
system feature; Clipboard is skipped when its plugin is disabled. With a typed launcher query,
Tab instead enters a fresh AI Chat session and sends through Spotter's OpenRouter-backed default.
With a typed AI Chat draft, Tab sends in the current Spotter session. Shift-Tab sends a typed draft
from either Apps or AI Chat to `https://chatgpt.com/?q=…` in the default browser. Every other mode
(Calculator History, Emoji, Software Update, plugin screens) is a sub-screen reached from the
launcher (a command or a hotkey); Tab from one exits back to the launcher rather than joining the cycle.

**Esc backs out one layer, matching Raycast.** An open confirmation cancels first, then an open
footer menu closes; then a sub-screen
(clipboard, history, emoji, any plugin screen) pops to a fresh launcher root; then a typed query
clears; only Esc at the empty launcher root hides the palette. Backspace in an already-empty search
is the same back gesture for sub-screens.

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

A user drag re-anchors the session, and with **Remember position** on the anchor persists across
summons. Each show also runs `InputSourceLock.selectASCIIKeyboard()` when General → "Lock input
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
