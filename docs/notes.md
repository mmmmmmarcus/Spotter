# Notes plugin

Notes is a native, local note-taking workspace modeled on the core experience described before the
“Frictionless integrations” section of Raycast Notes: quick floating access, Markdown formatting,
todos and multiple notes. It deliberately does not implement Raycast AI, snippets, quicklinks, cloud
sync, export/share targets or deleted-note recovery.

## Entry points

The plugin registers two launcher commands and two independently bindable global shortcut actions:

- **Open Notes** focuses the last selected note.
- **New Note** creates an empty note and focuses it immediately.

Both routes call `AppCore.openNotes`, which guards plugin enablement, dismisses the launcher when
needed and opens the shared `AuxWindowController` workspace. The window opts into resizing,
`.floating` level and all-Spaces visibility, but the plugin never creates or retains an `NSWindow`.
Disabling the plugin closes the window and flushes the latest in-memory snapshot.

## Model and persistence

`NoteStore` is `@MainActor` and owned once by `AppCore`. It keeps the ordered note list and active
selection in memory; titles and sidebar previews are derived from the first meaningful Markdown
lines rather than duplicated fields. Creating, editing and deleting notes mutate that one store.

The archive is versioned JSON at:

```text
~/Library/Application Support/<bundle-id>/Notes/notes.json
```

Using the bundle identifier keeps Debug, beta and stable channels isolated. Content changes are
debounced for 250 ms, snapshotted as `Sendable` values and written atomically by a serial actor, so
typing never performs filesystem IO on the main actor and newer saves cannot be overtaken by older
ones. Creation and deletion schedule immediate snapshots. Notes are local-only and require no macOS
permission or network consent.

## Editor

`NoteMarkdownEditor` wraps one native `NSTextView` with overlay scrolling, undo and Find support.
The persisted source is ordinary Markdown. Temporary TextKit attributes provide live heading, bold,
italic, inline-code, link and completed-task feedback without changing the source string.

The toolbar and keyboard shortcuts apply transformations through the Foundation-only `NoteEngine`:
bold, italic, strikethrough, inline code, link, heading, bulleted list, numbered list and checklist.
The same engine derives titles/previews and handles selections as UTF-16 `NSRange`s so AppKit and the
pure tests use identical behavior. Preview mode renders the Markdown through Foundation's
`AttributedString` parser.

## Testing

Run the pure harness independently:

```sh
swiftc -swift-version 6 Spotter/Plugins/Note/NoteEngine.swift Spotter/Plugins/Note/NoteStore.swift \
    Tools/note-test.swift -o /tmp/note-test && /tmp/note-test
```

The harness uses an injected temporary archive and defaults suite; it never opens the floating window
or reads real application data.
