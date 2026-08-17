# Notes plugin

Notes is a native, local note-taking workspace modeled on the core experience described before the
“Frictionless integrations” section of Raycast Notes: quick floating access, Markdown formatting,
todos and multiple notes. It deliberately does not implement Raycast AI, snippets, quicklinks, cloud
services, export/share targets, a separate preview mode or deleted-note recovery. Optional cross-Mac
sync replicates each Note and deletion through the user's private Apple CloudKit database.

## Entry points

The plugin registers two launcher commands and two independently bindable global shortcut actions:

- **Open Notes** focuses the last selected note, and is a toggle: pressing it again closes the
  window. The window floats over everything, so the shortcut that summoned it is the obvious way to
  put it away.
- **New Note** creates an empty note and focuses it immediately. It always opens, never toggles,
  since it has a new note to show.

Both routes call `AppCore.openNotes`, which guards plugin enablement, dismisses the launcher when
needed and opens the shared `AuxWindowController` workspace. The translucent window opts into
resizing, `.floating` level and all-Spaces visibility, but the plugin never creates or retains an
`NSWindow`. The native window backdrop stays clear while its host neutralizes the title-bar safe-area
inset, leaving the clipped Note material as the only rounded surface. The surface and toolbar extend
through one seamless title bar, with the lone close button directly left of the centered note title
in the same native-height row; minimize and zoom controls are hidden. Nothing separates that row from
the editor — the window is one continuous surface, so a rule under the title would be the only hard
edge on it. An empty note shows the current date and time in place of a prompt to start writing: it
is what most notes open with anyway. The workspace opens as a
440-point-wide editor with four matching 20-point continuous corners.
Its centered toolbar title is derived from the selected note's first line; the right side contains
only the notes-list and New Note actions. The list starts hidden and opens as an inset material card
over the editor, temporarily growing the window vertically rather than changing its width. Selecting
a row returns to the single-note editor. The toolbar row is a sibling *above* the animated container
holding the editor and that card, never inside it: within it, toggling the list ran the title and its
buttons through the same animated relayout as the list and they visibly drifted. The title is also
centred against the full toolbar width rather than its own measured width, so nothing beside it can
re-centre it. The shared window owner keeps the top edge anchored while the
editor grows from three visible lines to a maximum of twenty, after which the native overlay scroller
takes over. Programmatic height changes interpolate real window frames from the anchored top edge
instead of asking AppKit to scale a cached window image, so the window does not jump and its corner
radius stays constant during the transition.
Disabling the plugin closes the window and flushes the latest in-memory snapshot.

## Model and persistence

`NoteStore` is `@MainActor` and owned once by `AppCore`. It keeps the ordered note list and active
selection in memory; the first line is always the note title and later meaningful lines supply the
list excerpt, so neither is stored as a duplicated field. Creating, editing and deleting notes
mutate that one store.

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
recovery, but automatic Settings Sync deliberately excludes them.

## Independent sync

`NoteSyncManager` is owned by `AppCore` and holds the explicit iCloud consent flag. Fresh installs
ship off. The Settings sheet names Apple CloudKit, the synchronized fields and cadence before the
toggle can turn on; every explicit fetch/send re-checks consent before and after its `await`.
Disabling cancels the engine and deletes its bundle-scoped local state while preserving both local
Notes and the user's private CloudKit records.

`NoteCloudSyncEngine` is an actor-backed `CKSyncEngineDelegate` targeting the private database in
`iCloud.com.spotter.app`. It uses one custom `SpotterNotes` record zone and one encrypted
`SpotterNote` record per UUID. A live Note carries Markdown, creation time and user edit time; a
deletion keeps only its UUID and deletion time. The engine persists its opaque state serialization
and last-known record system fields under the bundle-specific Application Support `Notes` directory.
Edits debounce for 300 ms, then only changed records are sent. CloudKit's subscription-driven fetches
hot-apply remote records, and Settings exposes an immediate fetch/send action.

Conflicts compare the user edit/deletion timestamp rather than upload arrival time. The newer item
wins; a deletion wins an exact timestamp tie, and simultaneous Note edits use a deterministic content
tiebreak so two devices converge. Server-record conflicts retain the newest CKRecord system fields
before retrying a winning local edit. Account sign-out/switch disables sync without deleting local
Notes so content is never silently uploaded to a different iCloud account.

The former user-selected Notes JSON pipeline has one bounded decode-only migration. If that trusted
file was active, the first upgraded start fully decodes and applies it to local `NoteStore`, clears
the obsolete bundle-scoped path/toggle, and never deletes the user's file. It does not grant CloudKit
consent; the user must explicitly enable the new service. Automatic Settings Sync continues to omit
Note content, while its trusted snapshot may carry the CloudKit consent flag.

Developer ID stable and beta builds share the CloudKit container but use provisioning profiles tied
to their separate App IDs. The local self-signed Debug build deliberately has no CloudKit entitlement,
so it exercises local Notes and pure sync tests without contacting iCloud.

## Editor

`NoteMarkdownEditor` wraps one native `NSTextView` with overlay scrolling, undo and Find support.
The persisted source is ordinary Markdown.

**Styling lives in the text storage's attributes, never in `NSLayoutManager` temporary attributes.**
Temporary attributes are drawing-only — a temporary largeTitle font leaves the line fragment at the
body's 16 points while painting 26-point glyphs, so headings rendered big with a body-height line box
and a body-height caret. Storage attributes are not characters: `textView.string`, and therefore
everything persisted, is still exactly the Markdown the user typed. Each pass resets the whole
document to the base font and label color, then re-applies first-line title, heading, bold, italic,
strikethrough, inline-code, link, list and completed-task presentation. Syntax markers collapse when
the caret is outside their span — and now genuinely collapse, taking no width rather than being drawn
small — and a leading `- ` is rendered as a bullet.

Headings carry a real hierarchy that the line box follows: `#` is largeTitle (a 32-point line), `##`
title1 (26), `###` title3 (20, only just above the body's 16), and deeper levels take weight instead
of more size. The regex allows an empty body, so the line and caret grow the moment the marker and
its space are typed, before any text follows.

A `- [ ] ` or `- [x] ` marker renders as a real checkbox. The syntax either side of the state
character is collapsed and the state character itself is kerned out to a square, which
`NoteLayoutManager` draws a rounded box into — filled with a checkmark in the accent color when done.
Clicking the box toggles it through `shouldChangeText`, so the change is undoable and the source
stays `[ ]`/`[x]`. Unlike every other marker the box never hides while the caret is on its line: it is
a control, not decoration.

Three input rules fire from `shouldChangeTextIn`, each keyed to one typed character:

- **Return** continues bulleted, numbered and checklist items; Return on an empty item exits the list.
- **Space** after a bare `[]` becomes `- [ ] `, the one list marker Markdown makes awkward to type.
  It works at any indentation and replaces an existing bullet rather than nesting inside it.
- **`=`** after an arithmetic expression appends the answer, so `129+92=` finishes itself.
  `NoteEngine.arithmeticExpression` finds the expression and stays pure; the editor evaluates it
  through `CalcEngine`, which keeps arithmetic in its single owner. A list or numbered marker is
  stripped first, since `-` and `.` are also operators, and digits glued to a word (`rev2+3`) are an
  identifier rather than a sum. Typing `=` after anything else still just types an `=`.

Block constructs are found by `NoteEngine.blockSpans`, a pure line scan returning UTF-16 ranges for
fenced code, blockquotes, horizontal rules and pipe tables. A fenced block shadows everything inside
it, so a rule, table or `# ` written in an example stays literal text and its `- ` keeps its dash
rather than becoming a bullet. Code and table lines are set monospaced — a table's own pipes are what
align its columns — a quote is indented and secondary, and a rule's dashes are hidden while the caret
is elsewhere.

The fills those blocks imply are *drawn*, not inserted: `NoteLayoutManager` overrides background
drawing to paint the code panel, the quote bar and the rule hairline behind the text. That is the
whole reason the editor builds its TextKit 1 stack by hand. Nothing about it reaches the note's
source string, so the file on disk stays the Markdown the user typed.

The minimal toolbar only exposes New Note and the notes-list toggle. Formatting stays in the
writing flow: Command-B applies bold, Command-I applies italic and Command-K inserts a link, while
ordinary Markdown markers cover strikethrough, inline code, headings, bulleted lists, numbered lists
and checklists. The Foundation-only `NoteEngine` performs shortcut transformations, derives
titles/list excerpts and handles selections as UTF-16 `NSRange`s so AppKit and the pure tests use
identical behavior. There is no separate title field, preview surface, formatting palette,
word/character counter or save-status footer; persistence remains automatic in the background.

## Testing

Run the pure harness independently:

```sh
swiftc -swift-version 6 Spotter/Plugins/Note/NoteEngine.swift Spotter/Plugins/Note/NoteStore.swift \
    Spotter/Plugins/Note/NoteSyncDocument.swift \
    Tools/note-test.swift -o /tmp/note-test && /tmp/note-test
```

The harness uses an injected temporary archive and defaults suite, checks archive-v2 tombstones,
deterministic Note/deletion merges and the former sync document's decode bridge; it never opens the
floating window, contacts CloudKit or reads real application data.
