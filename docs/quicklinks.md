# Quicklinks

A quicklink is a named destination — a URL, a deep link or a file path — that appears in the launcher
like any other entry. Templates may contain `{argument}` placeholders, which Spotter collects one at a
time before opening the result.

Enabled by default. Files live in `Spotter/Plugins/Quicklinks/`.

## Files

| File | Role |
| --- | --- |
| `QuicklinkTypes.swift` | Foundation-only, pure: the `Quicklink` model, `QuicklinkDestination` detection, and `QuicklinkTemplate` parsing/filling. |
| `QuicklinkStore.swift` | Foundation + Combine: versioned JSON persistence and the single sort order. |
| `QuicklinkManager.swift` | Palette-screen state (list vs. argument entry), the in-flight run, icon resolution, and the one side effect — opening the resolved destination. |
| `QuicklinksPlugin.swift` | Registration, palette snapshots, ⌘K menu, and the `AppCore` entry points. |
| `QuicklinksSettingsView.swift` | Enable switch, saved-link list, and the add/edit sheet. |

`Tools/quicklink-test.swift` compiles `QuicklinkTypes.swift` and `QuicklinkStore.swift` directly, so
both must stay free of AppKit and SwiftUI.

## Storage

`~/Library/Application Support/<bundle-id>/Quicklinks/quicklinks.json`, a versioned archive written
atomically. The file is deliberately readable and hand-editable: `Quicklink`'s decoder requires only
`name` and `link` and synthesizes everything else, so a partial entry still loads.

Quicklinks are included in `SettingsBackup` (and therefore in settings sync) under the `quicklinks`
key. An import replaces the list wholesale, dropping entries with a blank name or link.

## Templates

`{argument}` marks a value the user supplies at open time. Two attributes are recognized:

```
https://github.com/search?q={argument name="Query"}
https://weather.example/{argument name="City"}/{argument name="Range" options="day,week,month"}
```

- `name="…"` labels the prompt. Unnamed placeholders become `Argument 1`, `Argument 2`, … in order.
- `options="a,b,c"` offers fixed choices as selectable rows instead of free text.

Anything else inside braces is left alone — a URL fragment such as `#{anchor}` is not an argument.
Tokens are filled right to left so an earlier substitution can't shift a later token's range.

## Destinations and encoding

`QuicklinkDestination.detect` reads the **template**, before substitution, so a typed value can never
change what kind of destination a link is:

| Template starts with | Destination | Argument values |
| --- | --- | --- |
| `http://`, `https://`, or a bare domain | `.web` | percent-encoded |
| any other `scheme://` | `.deeplink` | percent-encoded |
| `/`, `~`, or `file:` | `.file` | inserted verbatim |

Web and deep-link values are encoded with `urlQueryAllowed` minus `& + = ? #`, so a value containing
`a&b=c` becomes one parameter rather than silently splitting the query. File paths are never encoded —
a path is not a URL — and `~` is expanded when the URL is built.

`openWithBundleID` sends the resolved URL to a specific app; without it macOS picks the default
handler. The Settings picker lists every app `AppIndex` knows about — the same Search Scopes the
launcher itself uses — so anything you can launch by name you can also open a link with.

## Icons

A quicklink has no icon of its own: it borrows the icon of the app that will open it.
`QuicklinkManager.openerBundlePath` resolves that bundle — the `openWithBundleID` app, or whatever
Launch Services would hand the link to, with placeholders filled as empty so the scheme or extension
still resolves. Nothing claiming it falls back to a `link` symbol.

The lookup is memoized per (app, template) pair, since the palette re-snapshots on every keystroke,
and the cache is dropped whenever the list changes. Launcher entries carry the bundle through
`PluginCommandRegistration.iconFilePath`, which is why a command row can draw a real app icon
instead of an SF Symbol tile.

## Palette flow

`Search Quicklinks` (or a bound shortcut) opens the plugin screen listing every saved link, pinned
first then alphabetical; `Create Quicklink` is a second launcher command that jumps straight to the
Settings pane. Rows carry a "Pinned" pill and an "N arguments" pill as accessories, and the list's
⌘K menu offers Open / Copy Link / Pin–Unpin / Edit in Settings… / Delete. Selecting one:

- **with no arguments** — opens immediately and dismisses the palette;
- **with arguments** — stays open and switches to argument entry.

In argument entry the placeholder becomes `<Quicklink name> — <Argument name>…` via
`livePlaceholder`. Each step shows either the declared options or a single row echoing what was typed,
with a subtitle previewing the resolved link so far. ↵ accepts the step; `AppCore` clears the search
field so the next prompt starts empty. ⌘K offers **Back** to undo one step. Closing the screen — Esc,
or switching modes — abandons a half-filled run.

The screen's primary action only receives an item id, so the manager records the live query on every
`snapshot(query:)` and free-text submission reads `palette.query`.

Each saved quicklink is also published straight into launcher search through
`dynamicLauncherCommands`, so it is reachable by name without opening the plugin screen first.
Selecting one there enters the same flow.
