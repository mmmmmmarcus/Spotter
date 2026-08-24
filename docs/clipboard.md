# Clipboard history

Clipboard is a self-contained native plugin under `Spotter/Plugins/Clipboard/`. The directory owns
`ClipboardPlugin`, `ClipboardManager`, `ClipboardStore`, the palette view and its Settings view;
`AppCore` remains the sole owner of the long-lived manager and store instances.

Screenshot writes its captured TIFF directly to the system pasteboard with the same private
`internalType` marker used by Spotter paste actions. It is therefore available to every app without
being re-captured as a duplicate Clipboard-history entry.

## Poll-based capture

`ClipboardManager` runs a 0.5s `Timer` watching `NSPasteboard.general.changeCount`. To avoid
re-capturing Spotter's own writes, every write stamps a private `internalType` marker on the
pasteboard and the poller skips anything carrying it.

Its plugin lifecycle starts this timer only while the plugin is enabled;
disabling it stops capture without deleting existing history, and re-enabling resumes with the
current pasteboard change count so old contents are not re-captured.

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

## Type filter

The trailing edge of the clipboard's search bar carries a filter button — **All Types, Text Only,
Images Only, Screenshots Only, Links Only, Emails Only** — opened by the button or by **⌘P**. It is the same
`PopoverMenu` as ⌘K Actions, just anchored `.topTrailing` under its button and narrower, so the
glass, rows and hover behaviour are shared rather than reimplemented as a second dropdown idiom. The
button states the active filter, and the menu opens highlighting it the way a pop-up button does.

**Screenshots are derived too, off the file name.** Spotter names its own captures
`<App>_SpotterScreenshot_<yyMMddHHmm>.png`, and `ClipboardItem.isScreenshot` looks for that marker in
the file's name — so the filter costs no column, no migration and no backfill, exactly like the text
kinds below. Unlike them it is deliberately *not* exclusive: a capture is an image, so Images Only
keeps it and Screenshots Only is the narrower slice. An image capture reaches history at all because
`AppCore` inserts it directly after a successful capture; the pasteboard copy keeps its internal
marker, which is what stops the poller from recording a second, differently-named copy of the same
pixels. A capture from an app the user excluded from history is excluded here too, and disabling the
Clipboard plugin stops the insert.

**Links and emails are derived, never stored.** `ClipboardItem.Kind` stays `text`/`image` — the two
things capture can actually tell apart — and `ClipboardFilter` reads `ClipboardItem.textForm`
(`plain`/`link`/`email`) off the text on demand. No column, no migration, no backfill: improving the
classifier stays a code change. Because the whole list reclassifies on every render, the classifier is
guarded cheapest-first — over 2048 UTF-8 bytes is prose by definition (`utf8.count` is O(1), `count`
walks graphemes), then whitespace, then a `scheme://` / `mailto:` prefix, an address shape, and last a
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
