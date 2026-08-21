# File Search

Find files and folders by name from the palette. **Search Files** is a launcher command with a
bindable shortcut, and its results open a dedicated plugin palette screen.

Spotter builds, persists and watches **no file index of its own** — it reads the Spotlight index
macOS already keeps. Nothing in this feature is allocated until a search actually runs, so the
launch and idle cost is zero.

## Files

`Spotter/Plugins/FileSearch/`

- `FileSearchTypes.swift` — the result, scope, query and exclusion policy. Foundation-only and pure,
  compiled standalone by `Tools/file-search-test.swift` together with the real
  `Core/SearchRelevance.swift` it ranks with.
- `FileSearchService.swift` — the one Spotlight read (`MDQuery`, CoreServices).
- `FileSearchSession.swift` — debounce, serialization, publication.
- `FileSearchPlugin.swift` / `FileSearchSettingsView.swift` — registration and its Settings pane.

## Query path

A keystroke does not start a search. `FileSearchSession` observes the palette's own `$query` while
the screen is open, and each change becomes **one pending request** with a 120 ms earliest-start
stamp. A single worker drains that pending slot:

- Typing faster than Spotlight answers **coalesces** onto the newest query rather than accumulating
  concurrent searches — the worker loops back and takes the newer request instead.
- Every request carries a revision. A finished search publishes only if its revision and query are
  still current, so a superseded, cleared or closed search can never land stale rows.
- `MDQueryExecute` is **synchronous and cannot be stopped mid-flight**, which is why it runs on a
  detached user-initiated task and why a result it has outlived is discarded rather than cancelled.

`MDQuery` is used instead of `NSMetadataQuery` for one reason: it exposes `MDQuerySetMaxCount`, so
Spotlight is capped at 1,000 candidates *before* execution. That cap is a feature invariant, not a
tuning knob — an uncapped `mdfind` for a one-letter query takes tens of seconds. Those candidates are
then ranked by the launcher's own `FuzzyMatch` scorer (whole-query score first, per-term sum as the
tiebreak, then name and path) and at most 200 rows are published.

The measured cost on a warm developer home is roughly 0.6–0.7 s per search plus the debounce. The UI
keeps the previous rows visible and shows the searching state instead of blanking the list, since
blanking on every keystroke reads as breakage.

## What is searched

- Visible top-level home folders, and the direct visible home items themselves — a home folder is a
  result too, and Spotlight never returns the scope root it was handed, so those are matched in
  memory.
- iCloud Drive and whatever providers exist under `~/Library/CloudStorage`.

`~/Library` is **never** admitted as a general scope; the two cloud paths above are named
individually because they are user documents that only happen to live there. Hidden paths and the
interiors of `.app` bundles are excluded structurally, along with `node_modules`, `DerivedData`,
`build`, `dist`, `target` and `Pods` — build output and vendored code are numerous enough to fill the
candidate cap on their own. A package (an `.rtfd`, an Xcode project) is a *result* but never a
directory to search inside.

Matching is on **filenames only**. File contents and metadata descriptions are never inspected.

## Permissions and privacy

File Search is deliberately **not** consent-gated, and the contrast with the networked features is
the point: reading the existing Spotlight index needs no TCC grant and no entitlement, installs no
monitor, persists nothing and sends nothing, so there is no ongoing access for a switch to withdraw.
The structural exclusions above are what keep it that way — staying out of hidden paths and bundle
interiors is what makes this a plain read of an index the system already maintains rather than a
crawl of everything the user owns. Results inherit Spotlight's freshness and its file-permission
omissions.

## Actions

↵ opens the item, ⌘↵ reveals it in Finder, and the ⌘K menu adds **Copy Path**. ⌘↵ reaches the screen
through `PluginPaletteScreenRegistration.performSecondaryAction`, which exists for exactly this shape
— a screen whose rows have one obvious secondary. Screens without one leave ⌘↵ inert rather than
aliasing it onto the primary.

## The launcher's Search Files row

The launcher appends a **Search Files** fallback row to every non-empty query
(`Core/LauncherFallback.swift`). With this plugin enabled that row opens this screen with the query
already typed; with it disabled the row keeps its original behaviour and hands the query to Finder.
One row, one name, and what it does follows the plugin switch.
