# Notes plugin

Notes is a native, local note-taking workspace modeled on the core experience described before the
“Frictionless integrations” section of Raycast Notes: quick floating access, Markdown formatting,
todos and multiple notes. It deliberately does not implement Raycast AI, snippets, quicklinks, cloud
services, export/share targets, a separate preview mode or deleted-note recovery. Optional cross-Mac
sync writes each Note as one Markdown file into a folder the user chooses — normally inside iCloud
Drive, which is what carries the folder between Macs.

## Entry points

The plugin registers two launcher commands and two independently bindable global shortcut actions:

- **Open Notes** focuses the last selected note, and is a toggle: pressing it again closes the
  window. The window floats over everything, so the shortcut that summoned it is the obvious way to
  put it away.
- **New Note** creates an empty note and focuses it immediately. It always opens, never toggles,
  since it has a new note to show.

Both routes call `AppCore.openNotes`, which dismisses the launcher when
needed and opens the shared `AuxWindowController` workspace. The translucent window opts into
resizing, `.floating` level and all-Spaces visibility, but the plugin never creates or retains an
`NSWindow`. The native window backdrop stays clear while its host neutralizes the title-bar safe-area
inset, leaving the clipped Note material as the only rounded surface. The surface and toolbar extend
through one seamless title bar; the window hides its standard buttons entirely, and close is a
toolbar control like the rest — both toolbar controls (close and note color) are interactive Liquid
Glass circles, with close leading and ⌘W bound to it. The toolbar's height centers the circles so
their gap to the top edge equals the row's side padding. New Note and the notes list have no
buttons: ⌘N and ⌘L keep their shortcuts (hidden buttons carry them) and clicking the pagination
dots opens the list — a control that duplicates a shortcut and a click target both would be chrome.
Minimize and zoom controls are hidden. Nothing separates that row from
the editor — the window is one continuous surface, so a rule under the title would be the only hard
edge on it. An empty note shows the current date and time in place of a prompt to start writing: it
is what most notes open with anyway. The workspace opens as a
440-point-wide editor with four matching 20-point continuous corners.
The centered toolbar carries page dots rather than a title — the title is already the first line of
the note directly beneath it, so what the header can add is *where in the stack you are*. One dot per
note in list order, the current one larger, each wearing its note's own tint; past nine notes the
strip slides around the current one. Clicking anywhere on it opens the notes list. The right side
holds only the color control. The list starts hidden and opens as an inset material card
over the editor, temporarily growing the window vertically rather than changing its width. Selecting
a row returns to the single-note editor. The card holds its search field and the rows and nothing
else: a "Notes" heading over a list of notes says nothing, and the count is already the number of
dots in the toolbar. The toolbar row is a sibling *above* the animated container
holding the editor and that card, never inside it: within it, toggling the list ran the title and its
buttons through the same animated relayout as the list and they visibly drifted. The title is also
centred against the full toolbar width rather than its own measured width, so nothing beside it can
re-centre it. The shared window owner keeps the top edge anchored while the
editor grows from three visible lines to a maximum of twenty, after which the native overlay scroller
takes over. Every auto-sized height is `NoteEditorMetrics.editorHeight(forTextHeight:)`: the text's
own height, the symmetric 20-point text inset, and `trailingRoom` on top of it. The extra room below
exists because the window is not symmetric — the toolbar sits above the text and nothing sits below
it — so without it the last line ends a hair under its own descender.

Tab nests the caret's list line and Shift-Tab un-nests it, wherever the caret sits in the line (a
selection moves every list line it touches together); on prose the keys fall through to a plain tab.
A nesting level is two spaces in the source (`NoteEngine.listIndentUnit`, harness-covered), and list
lines render a raw legacy tab at that same width instead of the 28-point default stop, so nesting
reads as a step rather than a gulf. Delete with the caret immediately after a list marker removes
the whole prefix — indentation and marker together — in one press, so a todo never degrades through
`- [ ]`, `- [` and out the other side as plain text; `NoteEngine.listMarkerDeletion` decides it and
`NoteTextView.deleteBackward` is the hook, beside `insertTab`/`insertBacktab`. The indentation goes
with the marker rather than one level at a time because Shift-Tab is already the outdent key: an
outdenting Delete would duplicate it and cost a press per level before the item could stop being
one, and two levels of leftover indentation is four leading spaces, which Markdown reads as an
indented code block rather than the ordinary paragraph the press is meant to leave. Every other
caret is untouched — mid-text, at the line's start, inside the marker or holding a selection, Delete
does exactly what it always did — and a composition stands the rule down like every other write.
Restyling after an edit is synchronous, not debounced — a
deferred pass left a frame where a new line's dash was plain text and the discs below the edit drew
from stale ranges, a visible list blink on Return and delete; only caret-only moves keep the
debounce. Typing-driven height changes resize immediately from the anchored top edge, so the text
viewport never passes through intermediate heights or scrolls the content while catching up. The
vertical scroller remains disabled until content genuinely exceeds the twenty-line cap, preventing
the transient scrollbar flash that an about-to-grow viewport would otherwise produce. Explicit UI
transitions such as opening the notes list still interpolate real window frames.
Closing the window flushes the latest in-memory snapshot.

While the editor is focused, **Command-[** selects the previous Note and **Command-]** selects the
next one. Navigation follows the same newest-first order as the notes list and wraps at either end.

## Model and persistence

`NoteStore` is `@MainActor` and owned once by `AppCore`. It keeps the ordered note list and active
selection in memory; the first line is always the note title and later meaningful lines supply the
list excerpt, so neither is stored as a duplicated field. Creating, editing and deleting notes
mutate that one store. List-row deletion is immediate rather than confirmation-gated. When the Notes
window closes, whitespace-only Notes are removed in one batch and recorded as normal deletion
tombstones; any Note containing text is preserved.

## Tints and window appearance

Each Note can carry one tint from a fixed nine-color ramp, chosen from the toolbar's `paintbrush.fill`
button left of the notes-list button. That button keeps its own color: a control that wore the note's
tint would read as a swatch, and an untinted note would leave nothing to point at. The ramp is fixed rather than a free color well because a tint has to
follow the system appearance: `Theme.Colors.noteTintAccent` and `noteTintWash` give every tint its
own pair of stops, since a hue that reads right over the dark window material turns muddy over the
light one. Raw strings key the ramp, so reordering `NoteTint` can never repaint existing Notes, and
an unrecognized tint written by a newer build decodes as untinted rather than failing the archive.

The tint shows as a wash over the window surface, laid above `panelScrim`, and the caret and text
selection wear the same color — a system-blue caret on a red note reads as another app's text field.
The wash is deliberately *not* attenuated by Window Transparency: a tint that dissolved with the
slider would leave the most see-through windows the least identifiable. Editor text and controls are
untouched. In the notes list a tinted Note shows a small dot beside its title.

The same popover is the **only** place either control lives: it carries the Window Transparency
slider and the Auto Window Sizing switch, and Notes Settings duplicated neither since Sep 2026 (owner
decision — the controls belong next to the window they change). Both settings themselves are
unchanged. Transparency fades exactly one
layer: the adaptive `panelScrim` over the window's frost. The `.hudWindow` material stays at full
strength at every setting and the tint film keeps its color, so the desktop shows through the scrim's
absence rather than through a hole in the window — the frost is what makes a Note read as glass, and
a tint that thinned with the slider would make the most see-through notes the hardest to tell apart
(owner decision, Sep 2026).

The range stops at 90% rather than 100%: a window with no surface left is invisible *and* passes
clicks through to whatever is under it, leaving nothing to grab to undo the setting.

There is no frost control. `NSVisualEffectView` publishes a named material, never a blur radius, so
the only thing Spotter could move is frost *coverage* — the material's own alpha — and the material
at alpha 1 is the whole of what the public API offers, which is where the window permanently sits. A
Window Blur slider that slid the material's alpha down as transparency rose shipped in 1.5.25–1.5.26 and was
removed (owner decision, Sep 2026); its `note.window-blur` default is inert and unread, and no
migration clears it. Going further than the material would mean either snapping between heavier
`NSVisualEffectView.Material` values, which changes the window's tint as well as its weight, or the
private `CGSSetWindowBackgroundBlurRadius` route to a true radius; neither is in the build, and both
are owner decisions.

**Auto Window Sizing** (on by default, `note.auto-window-sizing`) is what lets the window follow the
note. `NoteView.fitWindow` is the one place the height is set, and it returns immediately when the
preference is off — a new note, a longer note or the list opening then leaves a hand-sized window
exactly where its edge was dragged, and the editor fills that height instead of the measured one.
The editor's scroller answers to the window's own clip height in that mode rather than to the
twenty-line ceiling auto sizing grows to.

A tint is a user modification: it bumps `updatedAt`, so it syncs and wins conflicts like any edit.
It deliberately does not bump `contentUpdatedAt`, which is what the newest-first list order is sorted
by — recoloring a Note leaves it exactly where it sits, in this session and after a relaunch. Both
fields are additive and optional, so pre-tint archives and files decode with no tint and
an order that falls back to their edit time; the archive stays v2 and needs no migration.

The archive is versioned JSON at:

```text
~/Library/Application Support/<bundle-id>/Notes/notes.json
```

Using the bundle identifier keeps the local store scoped to Spotter. Archive v2 also retains
content-free deletion tombstones so an offline deletion cannot be resurrected by a later first sync.
Content changes are
debounced for 250 ms, snapshotted as `Sendable` values and written atomically by a serial actor, so
typing never performs filesystem IO on the main actor and newer saves cannot be overtaken by older
ones. Creation and deletion schedule immediate snapshots. Manual Spotter backups include Notes for
recovery, but automatic Settings Sync deliberately excludes them — the Notes folder owns that job.
`applyRemoteSnapshot` is the one way an outside snapshot reaches the store, and it merges rather than
replaces, so only an explicit tombstone can remove a Note.

## Folder sync

Notes replicate through **one folder the user picks**, holding one Markdown file per Note.
`NoteFolderSyncManager` owns it; `AppCore` owns the manager and the Notes plugin starts and stops it.
**Choosing the folder is the consent act** — the same shape Settings Sync uses for its file — so
there is no separate toggle and no consent dialog. Nothing is written anywhere until the user names
a place for it, Spotter opens no network connection of its own, and the folder's path is device-local
state that never travels in a settings snapshot. Disconnecting leaves every local Note and every file
in the folder exactly as they are.

CloudKit is gone from the product but not from the repo: see *Retired CloudKit pipeline* below.

### File format

```markdown
---
spotter-id: 3F2B1C48-8A2A-4A2E-9E4B-2E9B1D0A77C1
created: 2026-09-08T09:14:02.517Z
updated: 2026-09-08T11:02:44.108Z
content-updated: 2026-09-08T11:02:44.108Z
tint: blue
---
# Groceries

- [ ] milk
- [ ] coffee
```

The header is delimited by `---` fences and the body below the closing fence is the user's Markdown,
**appended and returned verbatim** — a write→read cycle is byte-for-byte, which the harness pins with
a body containing its own `---` block, a fenced code block, a stray carriage return, a tab and an
emoji. `tint` is omitted when a Note is untinted. Timestamps are ISO 8601 with milliseconds; the
truncation makes a file's copy marginally older than the live one, which biases every tie toward the
Mac holding the Note rather than toward the file — the direction that keeps content.

A block is Spotter's front matter **only if it carries a parseable `spotter-id`**. Everything else —
no fence, an unclosed fence, a human's own YAML, a malformed identifier — means the whole file is the
body, and it becomes a Note rather than an error. That rule is what makes a hand-written `.md` file
join the folder without losing a byte, and what stops Spotter from stripping a header it did not
write. Unrecognized header lines beside a real `spotter-id` are carried back out on the next
rewrite, minus anything that could close the block. A missing or unparseable date reads as
*just appeared* (the current clock) rather than as ancient, because winning a merge is the branch
that keeps content. An empty or whitespace-only file with no front matter is not a Note at all: it is
left alone, neither adopted nor removed. A blank Note likewise gets no file until it has something in
it.

### Naming, retitles and collisions

The file is named after the Note's title, which is what makes the folder worth having in Finder;
identity lives in the front matter, never in the name. Path separators, control characters and the
Windows-hostile set become spaces, runs of whitespace collapse, leading and trailing spaces and dots
go, a leading `~` is stripped (that prefix belongs to an interrupted rename) and the base is capped
at 60 characters. A blank title falls back to `Untitled Note`.

A **retitle** is therefore a rename, not a delete plus a create: the reconciler emits a move for the
file already carrying that id. The move is performed in two coordinated steps — the file first goes
to `~<uuid>.md`, then to its new name — so two Notes swapping titles cannot clobber one another, and
a crash between the halves leaves a well-formed Note file the next scan simply renames.

**Collisions** resolve deterministically: among Notes competing for one base name the oldest
(`createdAt`, then id) keeps it and the rest take ` 2`, ` 3`. Two Macs resolving the same set
independently therefore choose the same names and never fight. Names already occupied by files
Spotter cannot read are reserved, so a write can never land on top of a file whose contents are
unknown.

### Downloaded, missing, deleted

These are three different things and the reconciler keeps them apart:

- **Not downloaded.** An iCloud placeholder — `URLUbiquitousItemDownloadingStatusKey` other than
  `.current`, or a `.Name.md.icloud` alias — is *present with unknown contents*. It is never parsed,
  never written over, never removed, and its name stays reserved. A download is requested and the
  manager looks again every ten seconds while anything is still pending, since a placeholder becoming
  real produces no coordinated change to observe. An unreadable or non-UTF-8 file is treated
  identically. Unknown always means present.
- **Missing.** A Note with no file is a file to write, never a Note to drop. Spotter writes it back.
- **Deleted.** Deletion needs an explicit signal, and that signal is the tombstone ledger, a hidden
  `.spotter-notes.json` in the folder carrying the same `NoteTombstone` records the local archive
  keeps. A tombstone is the only thing that removes a live Note's file. If the
  ledger itself cannot be read, it is **not rewritten** — overwriting it would erase another Mac's
  deletions — and no deletion is applied that pass. Tombstones are never pruned, and the ledger is
  **append-only**: since a deletion is absorbing (below), the merged tombstone set can only ever
  grow, so no pass can quietly unlearn what another Mac deleted.

Only two removals exist, and both provably keep the content: a file whose id has a winning tombstone,
and a duplicate whose body and tint are byte-identical to the copy that stays. Removed files go to
the **Trash**, not into thin air. The whole folder being unreachable is an error that leaves both the
Notes and the files untouched; it is never read as a folder full of deletions.

### Conflicts

Two Macs editing one Note resolve through `NoteSyncMerge` — the single merge policy in the
codebase, previously used by CloudKit. The newer `updatedAt` wins, and
two Notes tied to the instant fall back to content, then tint, then `createdAt`, then id, so both
Macs converge on the same survivor without talking to each other.

**A deletion is absorbing.** Once an id carries a tombstone it never becomes a Note again, whatever
the two timestamps say — a tombstone is not ranked against an edit, it simply wins. Deletion is the
one act here with no ambiguous reading, while `updatedAt` is a stamp from a clock the other Mac
never agreed with. Ranking the two by time (which is what shipped through 1.5.30) meant a copy that
merely *synced* late outranked the deletion that had already beaten it, and — worse — the beaten
tombstone was then dropped from the merged snapshot and rewritten out of the ledger, so the Note
could never be deleted again. The user's bytes are not the price: a file removed under a tombstone
goes to the Trash, and restoring a manual backup clears tombstones for the Notes it carries, so an
intentional recovery still works.

**Except on the first pass after a folder is adopted, which keeps both sides instead.** The
reconciler takes a `NoteFolderPass` — `.adoption` or `.steady` — and it has no default, because
neither value is the safe one to forget. *Why the first pass is different* below is the reasoning;
read it before touching either path.

One case the folder adds: an external editor changes a file's body without touching its `updated`
header, which would leave the merge a tie broken by comparing strings — and losing that tie would
rewrite the user's edit away. When a file's body differs from the Note Spotter holds *and* their
timestamps are equal, the file's own modification date settles it in favour of the newer bytes.

Two files claiming one id never lose a version, and in steady state they never *gain* one either.
Identical bodies collapse to one file — provably safe, since the survivor is byte-identical.
**Different** bodies are three different situations, and the reconciler decides between them after
the merge rather than while reading the files:

- **A tombstone won.** Both files go, under that one explicit deletion. The loser is *not* handed a
  fresh identifier — that was the 1.5.29/1.5.30 resurrection bug: a fresh id has no tombstone, so
  deleting a Note while a second file for it was in flight put the deleted text straight back under
  an id nothing could ever delete again.
- **Steady state.** The pair is a filesystem race, not two versions of anything. iCloud delivers a
  retitle as a create and a delete that arrive in either order, and the two-step move publishes its
  `~<uuid>.md` half on the way through, so *every* retitle can be observed as two files under one
  id. Forking there manufactured a Note per title state. The newer file is the Note; the other is
  left exactly where it is — never parsed into a Note, never written over, never removed, its name
  reserved — the same "present, unknown" treatment a placeholder gets. Replication finishes clearing
  it, and if it turns out to be a copy the user made on purpose, their file is still sitting there.
- **The adoption pass.** Still forks, for the reason below: it runs once, over timestamps that were
  never comparable, and a silent winner there is unrecoverable.

### Why the first pass is different

One Note diverged under one id — this Mac's copy and the folder's — is the same-looking situation
whenever it is found, and it has opposite right answers depending on *when*. The asymmetry is
deliberate, and a reader who finds only the rules will read it as a bug, so here is the reasoning.

**The first pass is the upgrade.** It runs exactly once per Mac, at the moment Notes that have never
been reconciled meet a folder for the first time. Someone arriving with Notes already on two Macs —
from the retired CloudKit pipeline, from the older JSON file, or simply from two independent
installs — can hold one Note diverged under a single id, carrying `updatedAt` stamps that were never
comparable across machines to begin with. Picking a winner there discards a version of the user's
writing *invisibly* (nothing says a merge happened) and *unrecoverably* (the losing text was never
in that folder, so there is no file in the Trash to find). One duplicate is a far smaller cost than
that, so the loser is kept under a fresh identifier — the same fork the reconciler performs on that
one pass for two divergent *files* — and both end up with a file.

**Steady state is not that.** By then both sides are live, recent and observable: the user is
editing on one Mac while the other syncs within seconds, and the losing text is on screen somewhere.
Forking every ordinary edit collision would bury a working folder in near-identical Notes. So every
pass after the first merges by `NoteSyncMerge` alone and forks nothing at all, exactly as described
above — a fresh identifier is minted in steady state only for a file that carries no `spotter-id`,
which is a file a human dropped in, not a Note Spotter is keeping track of.

Three things bound the first pass so it cannot manufacture noise. Only **text** is grounds for a
fork — a tint that loses is visible and one click to restore. A loser whose text is blank is not
kept, since there is nothing to lose. And a text already held by some other Note in the merged
result is not copied again, which is also what stops a *retried* adoption (one whose file work
failed last time) from forking the same divergence twice.

An **explicit deletion still wins**, on either pass: a tombstoned id is never forked back to life,
because a fresh identifier carries no tombstone and would launder the deletion permanently. And an empty folder has no divergence at all, so both passes plan
exactly the same thing — the harness compares the two plans whole.

**Detecting "first".** `NoteFolderAdoption` (in `NoteFolderIO.swift`, the Foundation-not-pure tier)
owns one device-local `UserDefaults` flag, `note.folder-sync.adoption-pending`. `connect(to:)` sets
it — *every* choice is an adoption, including re-picking a folder this Mac has seen before — and
`runSyncPass` clears it only past `io.apply`, so a pass that threw, or a quit or crash between
picking the folder and the first pass that finished, still gets the adoption treatment on the next
attempt. Disconnecting clears it. Nothing here consults whether the user ever had CloudKit on: that
is unknowable on a fresh install and irrelevant to the risk, which is only ever "two copies, one id,
timestamps you cannot trust". The flag is per-Mac and never travels in a snapshot, like the folder
path itself.

### Pipeline

`NoteFolderIO` is an actor and does every read, write, move and delete through `NSFileCoordinator`;
writes are atomic, so a half-written file can never be read as a truncated Note. The folder is
watched the way `SettingsSyncManager` watches its file: an `NSFilePresenter` on the folder (which
also receives `presentedSubitemDidChange`) plus a dispatch source on the directory, catching
uncoordinated editors and atomic replacement. Local edits debounce for 400 ms.

Spotter's own writes do cause a notification, and the guard against a feedback loop is that
reconciliation is a fixpoint: a pass over a folder Spotter just wrote produces no file work and no
change to the store, so nothing further is scheduled. A pass that lands while another is running sets
a flag and runs once more afterwards rather than interleaving.

The former user-selected Notes JSON pipeline keeps its one bounded decode-only migration, now owned
by this manager. If that trusted file was active, the first upgraded start decodes it and **merges**
it into the local store — it can add Notes, never delete them — then clears the obsolete path and
toggle without ever touching the user's file.

## Retired CloudKit pipeline

`NoteSyncManager` and `NoteCloudSyncEngine` remain in the repository, whole and compiling, but the
product cannot reach them (owner decision, Sep 2026). Settings has no switch and no consent sheet,
`AppCore` constructs the manager and never calls `start()`, and a trusted v3 backup carrying the old
`iCloudSyncEnabled: true` no longer does anything: the field is neither written nor read, so the key
is ignored on decode and cannot start CloudKit. Reconnecting the feature means restoring an entry
point — a Settings switch and a `start()` call — not rewriting the engine. The CloudKit
entitlement/provisioning arrangement (Developer ID profiles for `iCloud.com.spotter.app`, the
self-signed Debug build's lack of an entitlement, `scripts/install-cloud-dev.sh`) is release plumbing
and is left alone.

## Editor

`NoteMarkdownEditor` wraps one native `NSTextView` with overlay scrolling, undo and Find support.
The persisted source is ordinary Markdown.

**Styling lives in the text storage's attributes, never in `NSLayoutManager` temporary attributes.**
Temporary attributes are drawing-only — a temporary largeTitle font leaves the line fragment at the
body's 16 points while painting 26-point glyphs, so headings rendered big with a body-height line box
and a body-height caret. Storage attributes are not characters: `textView.string`, and therefore
everything persisted, is still exactly the Markdown the user typed. Each pass resets the whole
document to the base font and label color, then re-applies heading, bold, italic,
strikethrough, inline-code, link, list and completed-task presentation. The first line supplies the note's
title in the list but receives no implicit editor font, so converting a Heading 1 paragraph to Text
restores the true body size. Inline and heading syntax
markers always collapse to no width, including while the formatted content is selected or edited;
the workspace behaves like a visual editor while the stored string remains Markdown. A leading `- `
is rendered as a bullet: the dash is cleared and `NoteLayoutManager` draws a disc in the slot it
leaves behind, sized to be read — the font's own `bullet` glyph, which the editor used to substitute,
comes out barely larger than a period.

**Every list marker occupies one fixed cell** (`NoteListMarker`), so a note mixing todos, bullets and
numbers has a single content edge instead of three. A todo, a bullet and an ordered marker have three
different natural widths — measured at the 13-point body size: 18.75, 9.64 and 24.11 points — and the
cell is the widest common marker, `1. ` in the monospaced font an ordered marker keeps (24.11), never
narrower than a decoration and its gap. The marker's last character is kerned out to fill the rest of
the cell, so all three now start their text at 24.11 points; nesting steps by one indent unit (7.16
points for the two-space level, and a legacy tab is measured as the same step), giving 24.11 / 31.27 /
38.43 rather than the five different offsets the same document produced before. An ordered marker is
the only one that can outgrow the cell, so a `10. ` anywhere in the note raises the cell for every
list line in it — item ten costs the note a reflow, not its content edge. The dash and the todo's
state character are each kerned to exactly one `decorationSide` square, and `NoteLayoutManager`
derives both the disc and the box from that one `decorationBox`, so the two decorations are the same
size in the same place; the disc is inscribed in that square rather than filling it, because a disc
the diameter of a todo box reads as a blob beside 13-point text. Wrapped list lines hang at that same
cell, so a continuation aligns with the first line's content whatever kind of list it belongs to.
None of this reaches the source: kerning and paragraph style are attributes, so `textView.string` is
still exactly the Markdown the user typed.

Headings carry a real hierarchy that the line box follows: `#` is largeTitle (a 32-point line), `##`
title1 (26), `###` title3 (20, only just above the body's 16), and deeper levels take weight instead
of more size. The regex allows an empty body, so typing `# ` immediately hides the marker and turns
the insertion point into Heading 1 before any text follows.

A `- [ ] ` or `- [x] ` marker renders as a real checkbox. The syntax either side of the state
character is collapsed and the state character itself is kerned out to a square, which
`NoteLayoutManager` draws a rounded box into — filled with a checkmark in the accent color when done.
Clicking the box toggles it through `shouldChangeText`, so the change is undoable and the source
stays `[ ]`/`[x]`. The rendered box stays visible while its line is edited because it is a control,
not decoration.

Three input rules fire from `shouldChangeTextIn`, each keyed to one typed character:

- **Return** continues bulleted, numbered and checklist items; Return on an empty item exits the list.
  Exiting deletes the line, so "empty" may only ever mean the ASCII spaces and tabs Markdown pads
  with: `CharacterSet.whitespaces` counts the ideographic space an input method types in full-width
  mode — and a non-breaking space — as blank, and ending the list on one silently deleted a
  character the user had typed. `NoteEngine.listContinuation` judges it with its own ASCII test.
  A Return typed at the visual end of a bold or italic run first steps the caret over the run's
  hidden closing marker: without that the newline lands *inside* `**bold**`, splitting the run across
  two lines and exposing the syntax the editor exists to hide.
- **Space** after bare `[]` or `【】` becomes `- [ ] `, the one list marker Markdown makes awkward to
  type. Closing `【 】` does the same, including a full-width interior space, and the full-width
  `［］` an IME produces in full-width mode is accepted in all three of those shapes. The rule works
  at any indentation and replaces an existing bullet rather than nesting inside it.
- **`-`, `*` or `_`** completing a `---` rule also opens the line beneath it. A rule divides what
  follows from what came before, so the caret belongs under it, never stranded on top of it.
- **`=`** after an arithmetic expression appends the answer, so `129+92=` finishes itself.
  `NoteEngine.arithmeticExpression` finds the expression and stays pure; the editor evaluates it
  through `CalcEngine`, which keeps arithmetic in its single owner. A list or numbered marker is
  stripped first, since `-` and `.` are also operators, and digits glued to a word (`rev2+3`) are an
  identifier rather than a sum. CJK is written without spaces, so a Chinese character or a
  full-width mark ends that word the way a space does — `总计：12+3=` answers exactly as
  `Total: 12+3=` does — and the full-width `＝` triggers and separates an answer like the ASCII one,
  echoed back in the width the user typed. Typing `=` after anything else still just types an `=` — but a line that *is* a formula and
  cannot be answered gets `(?)` rather than nothing, so a broken sum is visibly broken.

  An answered line then *stays* answered: editing the sum rewrites the number after the `=`, and a
  formula that stops resolving shows `(?)` rather than leaving a stale answer standing. Only the line
  the caret is on is rewritten, and only while the caret sits left of the answer — the answer itself
  is the user's to edit.

**An uncommitted composition owns the text view, and every path that writes to it stands down.**
A Chinese, Japanese or Korean input method puts its marked text into the storage before the user has
chosen anything, so `hasMarkedText()` gates the input rules, the arithmetic refresh, the restyling
pass, the checkbox click, Tab and the ⌘B/⌘I/⌘K and block-format commands. The editor receives a
stable Note ID: a refresh of the same Note must leave marked text and its selection untouched,
even when the binding still contains the pre-composition body. AppKit need not send `textDidChange`
for marked-text updates, so publishing from that callback alone cannot keep the binding current.
Only an actual Note switch may discard a composition before replacing the document. A committed
edit reaches the binding normally; external changes still apply when no composition is active.
The restyling pass matters most: it
resets attributes across the whole document, which would strip the marked run's underline, and its
concealed ranges collapse to no width, which would hide pinyin still being chosen — and it ran on
every marked-text update, several per committed character. The pass is deferred instead, and the
commit's own text and selection changes are what run it, so a note is styled the moment its
characters are real. Smart insert/delete is off with the other automatic substitutions: pasted
Markdown has to land verbatim, and the space it would add belongs to neither syntax nor a script
that writes without spaces.

Standing the pass down leaves its *findings* behind, though, and a list line is made of them.
`NoteLayoutManager` overrides `processEditing` and moves every stored decoration onto the text as it
stands now — `NoteEngine.adjusting(_:forEdit:changeInLength:documentLength:)`, pure and
harness-covered, applies the text storage's own rule for its attributes: a range before the edit is
untouched, one after it shifts, one the edit happened strictly inside grows, and one the edit ran
through is dropped until the next pass rebuilds it. Without that, a composition on a list line moved
every disc and box below the caret onto the user's own glyphs while the markers they belong to —
cleared to `NSColor.clear` by the same pass — were drawn nowhere at all: the bullets vanish and
stray discs appear in the text, which is what reads as characters going missing. Nothing about it
touches the source string. The two other places a previous pass's ranges are read now check them
against the current text as well: the checkbox click refuses a marker that is no longer a state
character, and the caret only steps over a concealed closing marker that still fits the document.

Block constructs are found by `NoteEngine.blockSpans`, a pure line scan returning UTF-16 ranges for
fenced code, blockquotes, horizontal rules and pipe tables. A fenced block shadows everything inside
it, so a rule, table or `# ` written in an example stays literal text and its `- ` keeps its dash
rather than becoming a bullet. Code and table lines are set monospaced — a table's own pipes are what
align its columns — an ordered list's `1. ` marker is monospaced for the same reason, so `9.` and
`10.` line up under one another while the prose after the marker stays in the body font — a quote is indented and secondary, and a rule's dashes stay hidden behind its
drawn hairline.

The fills those blocks imply are *drawn*, not inserted: `NoteLayoutManager` overrides background
drawing to paint the code panel, the quote bar and the rule hairline behind the text. That is the
whole reason the editor builds its TextKit 1 stack by hand. Nothing about it reaches the note's
source string, so the file on disk stays the Markdown the user typed.

The minimal toolbar only exposes the color panel, the notes-list toggle and New Note. Formatting stays in the
writing flow: Command-B applies visual bold, Command-I applies visual italic and Command-K inserts a
visual link; their Markdown delimiters are persisted but never shown. Ordinary Markdown markers
cover strikethrough, inline code, headings, bulleted lists, numbered lists
and checklists. Selecting text also replaces the generic editor menu with a native contextual menu
for Copy, Paste, Bold and Italic. Its visible Format section contains Text, Heading 1, Heading 2,
Heading 3, Numbered List and Bulleted List directly rather than nesting them in a submenu. Paragraph
choices are mutually exclusive: the pure engine removes an existing
heading, list or checklist prefix before applying the requested format, while preserving indentation
and keeping numbered lists continuous across nonempty selected lines. The Foundation-only
`NoteEngine` performs shortcut transformations, derives
titles/list excerpts and handles selections as UTF-16 `NSRange`s so AppKit and the pure tests use
identical behavior. There is no separate title field, preview surface, formatting palette,
word/character counter or save-status footer; persistence remains automatic in the background.

Auto Window Sizing and the 0–90% Window Transparency slider live only in the toolbar's color
popover; Notes Settings carries no Appearance card (owner decision, Sep 2026).
Transparency fades the adaptive `panelScrim` and nothing else: the `.hudWindow` material and the tint
film hold their strength, and editor content and controls remain fully opaque throughout. Both values
are bundle-scoped and ride in trusted Settings backup/sync state, while the system material continues
to honor macOS appearance and accessibility.

## Testing

Run the pure harness independently:

```sh
swiftc -swift-version 6 Spotter/Plugins/Note/NoteEngine.swift Spotter/Plugins/Note/NoteStore.swift \
    Spotter/Plugins/Note/NoteSyncDocument.swift Spotter/Plugins/Note/NoteFolderDocument.swift \
    Spotter/Plugins/Note/NoteFolderIO.swift \
    Tools/note-test.swift -o /tmp/note-test && /tmp/note-test
```

The harness uses an injected temporary archive and defaults suite, checks archive-v2 tombstones,
H1/H2/H3/Text block-format replacement, empty-Note cleanup, transparency persistence,
deterministic Note/deletion merges, the whole-marker Delete rule (every marker kind, indented and
not, an empty item, a caret elsewhere on the line, at the line's start, inside the marker, holding a
selection and inside a fence) and the former sync
document's decode bridge; it never opens the floating window, contacts CloudKit or reads real
application data.
deterministic Note/deletion merges and the former sync document's decode bridge.

Folder sync is covered twice over. Purely, through `NoteFolderDocument`/`NoteFolderReconciler`:
byte-for-byte round trips of a hostile body, a file with no front matter, an unclosed fence, a
human's own YAML header, a malformed identifier, an empty file, an unknown tint, a header with no
dates, foreign header lines, the naming and collision rules, an undownloaded placeholder, a missing
file, a ledger deletion, a tombstone an edit tried to beat, an unreadable ledger, a retitle,
identical and divergent duplicate ids, and an outside edit — with an assertion that every removal the
reconciler can emit is one of the two safe kinds.

The 1.5.29/1.5.30 resurrection has its own block, pinned from both ends: a deletion that beats a
contested pair takes both files and forks neither, on the steady *and* the adoption pass; a
tombstoned Note whose file reappears from the other Mac is removed again rather than revived; a
retitle observed mid-move — in the `~<uuid>.md` shape and the both-names shape — stays one Note and
asks for no file work; an edit made after the deletion elsewhere does not outlive it and does not
erase its tombstone; and an ordinary two-Mac edit collision still merges to one Note.

The two passes are pinned against the same fixture, which is the point: one local Note and one file
sharing an id but not their text produce **two** Notes under `.adoption` and **one** under
`.steady`, with the loser forked either way round (the folder newer, or this Mac newer, in which
case the winning file stays put and the fork gets a file of its own). The first pass is also checked
for what it must *not* do: no duplicate when the two texts are identical, no file work in that case,
the same plan as a steady pass over an empty folder (compared whole), and no Note forked back to
life when a tombstone beats both sides.

And against a real temporary directory through `NoteFolderIO`: writing a
Note out and reading it back unchanged, a second pass finding nothing to do, a retitle leaving
exactly one file, a hand-dropped file becoming a Note, a deletion removing its file and writing the
ledger, a second Mac applying that deletion without resurrecting the Note, an in-flight retitle
making no second Note and leaving the file it did not choose alone, deleting that contested Note
taking both its files and staying deleted across the next pass, an offline Mac returning with its
own edited copy applying the deletion instead of undoing it, and an unreachable folder
failing loudly. The adoption flag's whole lifecycle runs there too, over a real `UserDefaults` suite:
unset reads as steady, `begin()` makes it an adoption, a second reader over the same suite (a
relaunch) still sees the adoption, a pass whose `io.apply` throws because the folder vanished leaves
it pending, and the retry — which must not fork the same divergence a second time — clears it for
good. It never opens the floating window, contacts CloudKit, or reads real application data
or a real iCloud Drive folder.

`Tools/note-editor-test.swift` exercises the real AppKit editor and TextKit stack without opening a
window or reading user data. It updates marked pinyin between model refreshes in prose, lists and
bold text, verifies text/marked-range/selection preservation and commits Chinese characters. It also
checks document switching and external updates. Run it through `scripts/test-all.sh`; only the
app-wide selection-capture identifier is stubbed.
