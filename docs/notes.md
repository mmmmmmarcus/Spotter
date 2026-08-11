# Notes plugin

Notes is a native, local note-taking workspace modeled on the core experience described before the
“Frictionless integrations” section of Raycast Notes: quick floating access, Markdown formatting,
todos and multiple notes. It deliberately does not implement Raycast AI, snippets, quicklinks, cloud
sync, export/share targets, a separate preview mode or deleted-note recovery.

## Entry points

The plugin registers two launcher commands and two independently bindable global shortcut actions:

- **Open Notes** focuses the last selected note.
- **New Note** creates an empty note and focuses it immediately.

Both routes call `AppCore.openNotes`, which guards plugin enablement, dismisses the launcher when
needed and opens the shared `AuxWindowController` workspace. The translucent window opts into
resizing, `.floating` level and all-Spaces visibility, but the plugin never creates or retains an
`NSWindow`. The native window backdrop stays clear while its host neutralizes the title-bar safe-area
inset, leaving the clipped Note material as the only rounded surface. The surface and toolbar extend
through one seamless title bar, with the lone close button directly left of the centered note title
in the same native-height row; minimize and zoom controls are hidden. The workspace opens as a
440-point-wide editor with four matching continuous corners.
Its centered toolbar title is derived from the selected note's first line; the right side contains
only the notes-list and New Note actions. The list starts hidden and opens as an inset material card
over the editor, temporarily growing the window vertically rather than changing its width. Selecting
a row returns to the single-note editor. The shared window owner keeps the top edge anchored while the
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

Using the bundle identifier keeps Debug, beta and stable channels isolated. Content changes are
debounced for 250 ms, snapshotted as `Sendable` values and written atomically by a serial actor, so
typing never performs filesystem IO on the main actor and newer saves cannot be overtaken by older
ones. Creation and deletion schedule immediate snapshots. Notes and the selected note enter trusted
v3 backups and automatic sync; the feature itself requires no macOS permission or network consent.

## Editor

`NoteMarkdownEditor` wraps one native `NSTextView` with overlay scrolling, undo and Find support.
The persisted source is ordinary Markdown. Temporary TextKit attributes provide live first-line
title, heading, bold, italic, inline-code, link, list and completed-task presentation without changing
the source string. Syntax markers collapse when the caret is outside their span, and a leading `- `
is rendered as a bullet. Return continues bulleted, numbered and checklist items; Return on an empty
item exits the list.

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
    Tools/note-test.swift -o /tmp/note-test && /tmp/note-test
```

The harness uses an injected temporary archive and defaults suite; it never opens the floating window
or reads real application data.
