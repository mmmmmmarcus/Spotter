# Clipboard history

Clipboard is a self-contained native plugin under `Spotter/Plugins/Clipboard/`. The directory owns
`ClipboardPlugin`, `ClipboardManager`, `ClipboardStore`, the palette view, Quick Clipboard History and its Settings view;
`AppCore` remains the sole owner of the long-lived manager and store instances.

Screenshot writes its captured TIFF directly to the system pasteboard with the same private
`internalType` marker used by Spotter paste actions. It is therefore available to every app without
being re-captured as a duplicate Clipboard-history entry.

## Poll-based capture

`ClipboardManager` runs a 0.5s `Timer` watching `NSPasteboard.general.changeCount`. To avoid
re-capturing Spotter's own writes, every write stamps a private `internalType` marker on the
pasteboard and the poller skips anything carrying it.

`ClipboardCapture` snapshots the advertised representations before any background work. A single
copied local image file takes priority over its preview; otherwise valid PNG, TIFF or other ImageIO
image data takes priority over accompanying text. Image decoding and PNG conversion run off-main.
Only when no usable image exists does capture fall back to text or a URL string. Copying an image URL
alone stays a link and never fetches it. Mixed representations produce one history item, not both an
image and its filename. Secret/internal markers and excluded source apps still skip the entire copy.
The history format remains text/image; old entries that only retained text cannot recover discarded pixels.

Its plugin lifecycle starts this timer once, from `onStart`, with the current pasteboard change
count so contents present before launch are not re-captured.

## Store

`Spotter/Plugins/Clipboard/ClipboardStore.swift` is SQLite-backed: rows plus a trigram FTS5 index in
`clipboard.sqlite3`, with image blobs as loose PNG files, all under
`~/Library/Caches/<bundle-id>/`. The newest 1000 rows are mirrored in the `@Published items` window;
FTS search reaches older rows.

A database that won't open is deleted and recreated (worst case the store degrades to session-only
in-memory history).

Image capture (TIFF→PNG re-encode + blob write) runs off the main actor via detached tasks; row
inserts, search, and pruning stay on the main actor.

Trusted v3 backups and automatic sync include the complete text/image history and pin stamps. Image
bytes are embedded in the JSON and written into the destination Mac's own cache, so machine-local
absolute paths never cross devices. A synced deletion replaces the destination history rather than
merging old rows back in.

Sync reads reuse image bytes in an off-main cache capped at 32 MiB, validating each cached file's
inode, modification date and size. Removed or changed files invalidate their cached bytes; oversized
images are read but not retained. Spotter-owned regular files with one link use safe file mapping,
so cached bytes can be reclaimed from the backing file instead of occupying a duplicate dirty heap
allocation. External paths, symlinks and hard links keep owned copies because another writer could
truncate them in place. Existing snapshots remain valid across Spotter's atomic replacements and
unlink operations. Applying an unchanged snapshot performs no SQLite or image writes.
New text normally inserts only the changed rows; a remote recency reorder may rebuild rowids, but
unchanged images retain their original path and inode (including screenshot names). Changed image
bytes are staged separately before the rows are updated, and only unreferenced owned blobs are
removed afterwards. Captures, pin changes and deletions made locally during asynchronous sync win
over that incoming snapshot. The wire format and retention rules are unchanged.

## Type filter

The trailing edge of the clipboard search bar carries a Liquid Glass segmented control for **All Types,
Text Only, Images Only, Screenshots Only, Links Only, Emails Only, Numbers Only**. Each segment
shows its SF Symbol, with a tooltip and accessible name. Clicking a segment keeps the search
field focused, resets selection to the first result and scrolls to the top. **⌘P** cycles forward
and **⇧⌘P** cycles backward; the filter no longer opens a menu. The seven segments share one
interactive glass capsule using `Theme.frosted(in:)`, with an immediate, unanimated selection highlight.
Buttons stay out of keyboard focus traversal and expose their selected state to VoiceOver.

Text rows use `textformat.alt`, links use `link`, numbers use `number.sign`, and email addresses
keep their distinct `at` symbol. Images retain their thumbnails. Numbers must occupy the entire
trimmed entry: signed integers, decimals, correctly grouped thousands, scientific notation and
percentages are accepted. Mixed strings such as `50080C`, expressions and version strings remain
text. The detail pane uses the same classification for its Type label instead of calling every textual payload Text. Persisted kinds remain text/image.

**Screenshots are derived too, off the file name.** Spotter names its own captures
`<App>_SpotterScreenshot_<yyMMddHHmm>.png`, and `ClipboardItem.isScreenshot` looks for that marker in
the file's name — so the filter costs no column, no migration and no backfill, exactly like the text
kinds below. Unlike them it is deliberately *not* exclusive: a capture is an image, so Images Only
keeps it and Screenshots Only is the narrower slice. An image capture reaches history at all because
`AppCore` inserts it directly after a successful capture; the pasteboard copy keeps its internal
marker, which is what stops the poller from recording a second, differently-named copy of the same
pixels. A capture from an app the user excluded from history is excluded here too.

**Links, emails and numbers are derived, never stored.** `ClipboardItem.Kind` stays `text`/`image` — the two
things capture can actually tell apart — and `ClipboardFilter` reads `ClipboardItem.textForm`
(`plain`/`link`/`email`/`number`) off the text on demand. No column, no migration, no backfill: improving the
classifier stays a code change. Because the whole list reclassifies on every render, the classifier is
guarded cheapest-first — over 2048 UTF-8 bytes is prose by definition (`utf8.count` is O(1), `count`
walks graphemes), then whitespace, a complete numeric token, then a `scheme://` / `mailto:` prefix, an address shape, and last a
bare domain. That last step is the only judgement call, since `report.pdf` and `index.html` are
domain-shaped too: a bare domain must be lower case (which is what keeps `Safari.app` out) and end in
one of a compact set of TLDs people actually copy. It is a heuristic whose worst case files a row
under the wrong type.

**The filter joins the search memo's key.** Keying on the query alone would serve stale rows, because
the filter changes without the query moving. Filtering happens *after* the pinned/rest split, so a
matching pin still leads its block in pin order. The FTS `LIMIT 200` still applies *before* the
filter, so a narrow filter over a broad query can show fewer rows than the history holds — pre-existing
in shape, but the filter makes it reachable.

The filter resets to All Types on every summon and on any mode change, chosen over stickiness so a
forgotten filter can never silently hide history. The empty state names the active filter, so one
hiding every entry no longer reads as "Clipboard history is empty".

*Files Only* is deliberately absent: `ClipboardManager` only captures pasteboard strings and PNG/TIFF,
never file URLs, so the row would always be empty.

## Pinned entries

A row's ⌘K Actions menu carries **Pin Entry / Unpin Entry** (⌘.), persisted as a `pinned_at` column
on `items` (added to existing databases by an `ALTER TABLE` migration, alongside `source_app`'s) —
a stamp rather than a flag, because the Pinned section is ordered by *when you pinned*, not by
recency.

Pins change four things:

- **Order.** `search` returns pinned rows first — for the empty query and for FTS hits alike — under
  one "Pinned" section above the date buckets, in pin order with the oldest pin at the top, so a new
  pin joins the end of the section instead of displacing the ones already there. `items` itself stays
  in pure recency order; the display split is memoized next to the search memo and invalidated with
  it. Pinned rows are matched **in memory**
  rather than taken from the FTS result, since the statement's `LIMIT` could otherwise drop one out
  of a busy query's matches — which holds because every pinned row is resident in `items`, however
  old (`load` fetches them all, and neither the window trim nor pruning drops one).
- **Unpinning re-recencies.** An unpinned row rejoins the history as its *newest* entry (Raycast does
  the same) rather than dropping back into the date bucket it came from, which would scroll the list
  out from under the selection. It's the same delete + re-insert `promote` uses.
- **Retention.** Pruning skips pinned rows (`AND pinned_at IS NULL`), so a pin outlives the retention
  window. "Clear History" still deletes everything.
- **Selection.** Pinning lifts a row out of its date bucket, so `AppCore.togglePinnedClip` moves the
  palette selection to the row's new index in the *current* results and bumps `palette.followToken`,
  which is what makes the list scroll the highlight back into view.

Pasting a pinned entry deliberately does **not** promote it: it holds its place in the Pinned
section, so `promote` skips pinned rows instead of rewriting the row and its FTS entry for no
visible change.

Deleting one entry, deleting all entries, and the ⌘Delete shortcut all pass through the shared
in-palette confirmation card. Cancel owns the initial Return highlight, and clearing history names
that pinned entries are included.

`load` reads every pinned row plus the newest 1000 unpinned ones as two indexed branches over a
partial index on `pinned_at` (`Tools/clipboard-test.swift` covers the shape). The single
`pinned_at IS NOT NULL OR rowid >= ?` form reads better but cannot be driven from an index while
holding row order, so it scans the whole table — ~12ms against ~1ms at 200k rows, on the main actor
at launch.

## Quick Clipboard History

`Quick Clipboard History` is a launcher command and an assignable global action in Settings → Shortcuts.
It defaults to **⌃⌘Z** under `KeyboardShortcuts_plugin.clipboard.quick-history`, participating in trusted
shortcut backup/sync. Before hotkeys register, a one-time migration transfers an existing ⌃⌘Z from
Clipboard History if Quick Clipboard History has no binding. Custom bindings stay intact. The migration
marker and existing default-seeding marker preserve later deliberate changes or unbinding; full
Clipboard History remains available from the palette with no shipped default shortcut. The sync
writer’s `pluginActionIDs` catalog distinguishes an unknown new action from an explicit unbind;
older snapshots cannot erase the quick action just by omitting its binding.

The user-requested exception to palette-first interaction is a nonactivating, non-key panel owned by
`AppCore` through `QuickClipboardController`. `AppCore` captures the global AppKit mouse position at
invocation. `QuickClipboardAnchor` prefers the active editable NSTextView's insertion caret, then
reads the target application's focused editable element and zero-length selection bounds through AX. Both application and system-wide focus are checked against the target PID; explicitly editable web elements are accepted even with a nonstandard role. If needed, Chromium accessibility is temporarily requested, with a bounded asynchronous wait for the lazy tree, and its prior flags restored. A Spotter search field never overrides another application's caret.
External AX reads run off-main with bounded messaging timeouts and never prompt, activate an app,
change its selection, or read its text. Missing permission, unsupported caret bounds, nonempty
selections and invalid/offscreen geometry fall back to the captured mouse point. AX coordinates are
converted using the primary display origin, including on other displays. The resolved anchor determines
the display, placement and both animation directions. Caret menus align directly above the caret;
mouse menus prefer above/right. Both flip below/left as necessary and leave 12 points at the anchor
and at least 8 points inside the screen's visible frame.

Up to five recent entries are visible together in one fixed horizontal row with native `NSButton` pills using `.glass` bezel style and `.capsule` border shape, 40 points high,
left aligned and sized to each native button’s content plus 11-point horizontal insets, capped at 120 points,
inside one `NSGlassEffectContainerView`, with 8-point gaps. A final 40-point circular `ellipsis` button opens the complete clipboard history in the shared palette, clearing any old query/filter. It remains available when history is empty. The native button renders its own bezel and interaction feedback on macOS 26+, rather than placing a borderless button inside a generic glass effect. Preview content is a non-interactive child view, leaving hit testing and accessibility on the button. The system owns
appearance, contrast and Reduce Transparency. Symbols use 14-point medium `labelColor`. Selected text has full opacity;
unselected text has 35% opacity and symbols 50%. Text and symbols resolve semantic label colors in the effective drawing appearance, including appearance changes. Symbols keep their native 14-point size and pixel-aligned origins; the opening animation invalidates glyph rendering once it reaches full size. Text previews collapse whitespace and truncate; pastes retain the full payload. Image entries show an aspect-fit thumbnail instead of a filename or text label, up to 24 points high, with 8 points of vertical padding, 11 points of horizontal padding, and 4-point image corners. They reuse the bounded 128-pixel row cache in `ImageThumbnail`, decode off-main, preserve their original colors with full opacity when selected and 50% when unselected, and fall back to a photo symbol for unreadable files.

Material uses the system glass button preset without custom tint, raster shadows or blur overlays. Outer containers do not clip the system-rendered glass edges; only pill content clips to its glass outline.

The panel cannot become key or main, and buttons never request key status. Click or ←/→ then Return
pastes; on the final circle, Return opens full history. Escape or repeating the shortcut cancels. Arrow navigation changes selection only: all entries stay visible and there is no paging state, timer or translation. Bare keys are claimed only while presented,
through `HotKeyManager`'s existing transient Carbon registrations, so the input app keeps focus. Outside
clicks and app switches dismiss without restoring focus. Paste still goes through `Paster` and the
palette's captured target or a local Note insertion snapshot, with the internal marker and promotion.

`QuickClipboardMotion` scales the whole group from 0.20 to 1 using mass 1, stiffness 500, damping 35.78
and a 0.455-second spring. The initial center is `anchor + 0.2 × (finalCenter − anchor)`, with both
position and scale animated together on an independent driver layer. A display link applies its
presentation to the actual menu `frame` with fixed `bounds`; AppKit retains ownership of native
backing-layer anchors and geometry, so glass and clipping stay in the same coordinate space. The
initial small frame and animations are installed before ordering the panel front. Driver opacity
sets **window composition alpha**, never glass or its ancestors, for a 0.145-second ease-out fade. Closing samples presentation scale, position and opacity
and shrinks/fades for 0.20 seconds; a pre-first-frame close uses the analytical spring state as fallback.
Reduce Motion keeps only a 0.12-second fade. Display links exist only during the bounded opening/closing animation, with task
cleanup even when a display link stops producing frames. Input ends immediately on dismissal and the
departing panel ignores mouse events. Screenshot's Hide Spotter path closes these panels immediately.

WindowServer shadow remains disabled. A single Core Animation area shadow follows the visible group: 22% opacity, 14-point radius and a 6-point downward offset. It has an explicit rounded region path and sits above the glass with an even-odd mask removing every visible pill interior. The path and cutouts include the history circle and update together on live width changes. Native buttons still own their material and edges; no per-frame bitmap generation or shadow cache is needed.

Store, mouse and app-activation observers exist only during a session. Same-size updates preserve
selection by ID; entry-count changes keep the current menu geometry until the next summon, and deleting
a displayed entry dismisses it. No new polling, network access, history duplication or persistence is
introduced. `QuickClipboardPresentation` stays pure Foundation + CoreGraphics. The clipboard harness covers content/order/positioning, and the
quick-clipboard harness validates native surface focus/material
invariants, animation setup/reversal fallback and Reduce Motion without visual UI acceptance.
