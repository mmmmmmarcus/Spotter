# Spotter Notes for iOS

`SpotterNotes` is a second application target in `Spotter.xcodeproj`: an iPhone and iPad app that
carries **only Notes**, synced with the Mac. Nothing else from Spotter is in it — no launcher,
clipboard, hotkeys, AI, plugin registry or settings backup.

| | |
| --- | --- |
| Target / scheme | `SpotterNotes` |
| Bundle identifier | `com.spotter.app1.ios` |
| Display name | Spotter |
| Deployment target | iOS 26.0, iPhone and iPad |
| Sources | `SpotterNotes/` plus the shared files listed below |

## Sync is the Mac's folder, unchanged

iOS joins the **same folder of Markdown files** the Mac uses ([notes.md](notes.md) → *Folder sync*):
one `<UUID>.md` per Note plus the hidden `.spotter-notes.json` tombstone ledger. The user picks that
folder in the system folder picker — normally iCloud Drive ▸ Spotter ▸ Note — and choosing it is the
consent act, exactly as on the Mac. There is no CloudKit, no iCloud entitlement, no container and no
network code in the target; iCloud Drive itself is what moves the files. `NoteSyncManager` and
`NoteCloudSyncEngine` are not compiled into it.

### What is shared

These are the same files the Mac target compiles — never copies — so the file format, the merge, the
reconciler and every rule of *a missing Note file is never a deletion* hold on iOS because they are
one implementation:

- `Spotter/Plugins/Note/NoteEngine.swift`, `NoteSyncDocument.swift`, `NoteFolderDocument.swift`,
  `NoteStore.swift`, `NoteFolderIO.swift`, `NoteFolderSyncManager.swift`
- `Spotter/Core/AppLog.swift`, `Spotter/Core/Backup/SettingsSyncFile.swift` (`CoordinatedFileIO`,
  `CoordinatedFileWatcher`)
- `Spotter/Core/Calculator/` with `CalcCurrency.swift` and `CurrencyData.generated.swift`, so
  `12+3=` answers through the same engine as on the Mac. Currency stays `.off`: no request is made.

All of them compiled for iOS as they were. The only edits are the three seams below.

### What is iOS-only (`SpotterNotes/`)

- `SpotterNotesApp.swift`, `NotesModel.swift` — the app and its single owner (the store, the sync
  manager, the lifecycle), the role `AppCore` plays on the Mac.
- `NotesRootView.swift`, `NoteTopBar.swift`, `NoteSearchView.swift`, `SyncViews.swift` — SwiftUI: the
  one screen, its marker strip and options menu, the search sheet, and the sync banner and sheet.
- `NoteTextEditor.swift`, `NoteEditorStyler.swift`, `NoteLayoutManager.swift`,
  `NoteAccessoryBar.swift` — the `UITextView` editor.
- `NoteInputRules.swift` — the editor's input rules and accessory commands, Foundation-only and
  pure, composed from `NoteEngine`.
- `NotesTheme.swift` — the one place iOS colours, fonts and metrics live.
- `Info.plist`, `PrivacyInfo.xcprivacy`.

## The seams in the shared files

Each is an injected dependency whose default is the Mac's existing behaviour, so the Mac's persisted
keys and on-disk formats are unchanged. `Tools/note-test.swift` pins all three.

1. **`NoteFolderLocation`** (`NoteFolderIO.swift`) — how the chosen folder is remembered and how
   access to it is held. `.path` is the Mac: the standardized path under `note.folder-sync.path`,
   and an access token that does nothing. `.bookmark` is iOS: bookmark data under
   `note.folder-sync.bookmark`, resolved again on every start, with
   `startAccessingSecurityScopedResource()` held from `start()` to `stop()`. Its `load()` has three
   answers — none, a folder, or **unresolvable** — and the third is never read as "no folder":
   `NoteFolderSyncManager.isFolderUnavailable` is set, the status says the folder can't be found,
   and a banner under the top bar offers to choose it again. The bookmark is *kept* while it does not
   resolve, so an iCloud Drive that is not ready at launch resolves on a later activation; only a
   new choice or Disconnect forgets it. A stale bookmark is refreshed in place.
2. **`NoteFolderIO.TrashUnavailable`** — see *Deletion* below.
3. **`device`** — `NoteFolderStatus.text` is the manager's status wording as a pure function; the
   Mac passes "this Mac" (the default) and iOS "this iPhone" / "this iPad". No Mac string changed.

## Lifecycle

`NotesModel.activate()` runs when the scene becomes active: the manager re-resolves the bookmark,
opens the security scope, installs the folder watcher and runs a pass. `suspend()` runs when it goes
to the background, under a `UIApplication` background task: the store is flushed, one last pass
writes pending edits to the folder, then the watcher is removed — iOS requires file presenters gone
while suspended — and the security scope is released. A return to the foreground before that
finishes simply cancels the stop.

Notes written before a folder is chosen, or while it is unreachable, live in the local archive
(`Application Support/com.spotter.app1.ios/Notes/notes.json`) exactly as on the Mac, and the first
pass after a folder is chosen is the same **adoption** pass.

Whitespace-only Notes are deleted (as ordinary tombstoned deletions, as the Mac does when the Notes
window closes) once nothing is showing them: at launch and whenever the open Note changes.

## Navigation

There is no Notes list (owner decision, Nov 2026). The app opens straight into the editor, on the
Note that was open last — the shared store's `note.selected-id`, which on iOS is this app's own
defaults domain — or the most recent one, and iPhone and iPad share the one single-column layout.

The top bar carries the Mac's marker strip ([notes.md](notes.md)), from the same shared sources: one
marker per Note in `NoteStore.notes` order, newest first, drawn from `SpotterNote.titleEmoji` — a
title's first complete Emoji — or a tint-aware dot. Selection changes opacity only on an Emoji; a dot
also grows, as on the Mac. A marker's glyph is 22 points in a 40 × 44-point tap target, labelled for
VoiceOver with `SpotterNote.displayTitle` (the title, or "Untitled Note" while the heading is empty).
A strip that fits is centred in the bar; one that does not takes the width left of the buttons,
scrolls, and brings the open Note's marker into view after a switch, a new Note, a deletion or the
reorder an edit causes. Tapping a marker switches the one editor to that Note in place. It leaves the
keyboard as it was: up if it was up, down if it was down.

Right of the strip sit **New Note**, which selects the new draft and focuses its title, and the
**options menu**: Note Color and Delete Note for the open Note, Search Notes, and Sync, whose row
carries the manager's status line. Delete asks first, and afterwards the store selects the Note that takes the
deleted one's place — the last one when there is none — or nothing.

Sync that needs the user is not left inside a menu. While no folder is chosen, the folder cannot be
found, or a pass has failed, a banner sits between the bar and the editor with the same
`NoteFolderStatus.text` line, a Choose Folder button in the first two cases, and the Sync sheet a
tap away. The sheet is unchanged: folder, status, files not downloaded yet, retained deletions, Sync
Now, choosing another folder, looking again for a lost one, and Disconnect.

With no Notes the strip is empty and the editor's place is taken by an empty state with a New Note
button. A fresh install is that state under the "no folder chosen" banner.

A marker cannot say what a Note contains, so the list's search was kept: **Search Notes** opens a
sheet with the same case-insensitive match over every Note's text. It shows results only for a
query — it is a search, never a second way to browse — and choosing one opens that Note. The list's
swipe-to-delete went with the list: deleting always goes through the open Note's menu.

## Deletion

The invariant is unchanged: an explicit deletion goes to the Trash, and a Trash failure **never**
falls back to permanent deletion.

`FileManager.trashItem` on iOS depends on where the folder lives (measured in the iOS 18.2 simulator
runtime; the Foundation call is the same one the app makes):

- In a File Provider location — "On My iPhone" was tested, and iCloud Drive is a file provider of the
  same kind — it **succeeds**: the file moves to that provider's `.Trash`, which Files shows as
  Recently Deleted.
- On a volume with no Trash it throws `NSFeatureUnsupportedError` (Cocoa 3328), "couldn't be moved
  to the trash because the volume doesn't have one".

Left alone, the second case made the whole pass throw on every attempt: the removal precedes the
writes, so the device could never sync an edit again until some Mac removed the file.

So iOS injects a `trash` that maps exactly that one error to `NoteFolderIO.TrashUnavailable`, and
the IO treats it as "this folder has no Trash" rather than "the Trash failed":

- The **tombstone has already reached the ledger** (it is written before any removal), so the
  deletion is real on every device, and the Note is gone from the iOS app.
- The **file is left untouched**, byte for byte. Nothing is removed outright.
- The pass **carries on** and completes; the manager is not left in an error state.
- The IO remembers the file by name and contents and does not coordinate another attempt until it
  changes — a coordinated deletion that removes nothing would still notify the folder's watcher, and
  the pass would never reach its fixpoint.
- `retainedDeletions` reports the count, and the Sync sheet says the files are still in the folder
  and that the Mac removes them.

The reconciler is not involved and its semantics are unchanged: it plans the removal every pass, as
before. A Mac that syncs the folder sees the tombstone and moves its copy to the Mac's Trash, and
the file leaves iOS with it. Every other Trash error is still a hard failure, on both platforms, and
the Mac's own `trash` never throws `TrashUnavailable`, so its behaviour is exactly what it was.

What remains: in a folder with no Trash and no Mac syncing it, files of deleted Notes accumulate.
They are never resurrected — a tombstone is absorbing.

## Files that are not downloaded

The scan is the shared one. A file whose `URLUbiquitousItemDownloadingStatusKey` is not `.current`
is "present, unknown": never parsed, never written over, never removed, its name reserved, and
`startDownloadingUbiquitousItem` is called for it (and for the ledger). The manager looks again every
ten seconds while anything is pending, and the Sync sheet shows the count. An item of another file
provider is not ubiquitous, so it is simply read; a read that fails is the same "present, unknown".

The legacy `.Name.md.icloud` alias branch reserves the name but requests no download. iOS 26 presents
undownloaded iCloud items as dataless files under their real names, which the branch above handles.

## Editor

A `UITextView` on a hand-built TextKit 1 stack, as on the Mac: the string is the raw Markdown, all
styling is storage attributes, and `NoteLayoutManager` draws todo boxes, bullet discs, the code
panel, the quote bar and the rule behind the text. `NoteEditorStyler` is the Mac pass ported to
UIKit — same expressions, same single marker cell, same concealed syntax.

Every edit goes through `NoteInputRules.decision`, which composes the shared engine the way the Mac
coordinator does: the protected `# ` title marker, Return refused in an untitled Note, list and todo
continuation, the hidden-closing-marker step, `[]` → todo, `---` completion, arithmetic answers and
their refresh, whole-marker Backspace, and the list paste rule. A composition (marked text) stands
every rule, the publish and the restyle down.

Touch-specific choices:

- A todo box toggles on tap, with a tap target grown past its drawn size.
- The keyboard accessory bar offers Checklist, Bulleted List, Numbered List, a paragraph-style menu
  (Text, Heading 1–3), an inline-format menu (Bold, Italic, Strikethrough, Code, Link) and
  Decrease / Increase Indent. A blank line is where a list or heading starts; tapping the list a line
  already belongs to takes the marker off; the title line refuses block formats.
- A hardware keyboard gets Tab / Shift-Tab, ⌘B / ⌘I / ⌘K, and ⌘[ / ⌘] for the previous and next
  Note in strip order, wrapping at either end through the shared `NoteStore.selectAdjacent`.
- Headings use `title1` / `title2` / `title3` in bold rather than the Mac's sizes.

Switching replaces the document of the one text view rather than building another editor. Every
committed edit has already reached the store by then, so there is nothing to flush; an uncommitted
composition is the one thing a switch discards, and it is committed with publishing stood down so it
cannot be written into the Note that replaces it.

Mac-only and deliberately absent: the Note window's transparency, tint popover and frame, the
160 ms switch animation and the Palette paste target. A Note's tint is kept — it syncs in the front
matter — as a wash behind the whole screen, the caret and selection colour, and its marker's dot.

## Appearance

The app follows the system appearance. `Core/Theme.swift` imports AppKit and is not compiled here;
`SpotterNotes/NotesTheme.swift` is this target's only token file, and its tint ramp repeats
`Theme.Colors.noteTintAccent` / `noteTintWash` stop for stop. A change to the Mac ramp has to be made
in both.

The icon is the Mac's: `Spotter/spotter.icon` is added to the target as a single file reference and
`actool` compiles it, producing opaque 1024 × 1024 renditions for iPhone and iPad.

## Build and run

```sh
xcodegen generate

# Simulator (needs an installed iOS 26+ simulator runtime)
xcodebuild -project Spotter.xcodeproj -scheme SpotterNotes -configuration Debug \
    -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
    -derivedDataPath build/DerivedData build

# Without a matching runtime, compile for any simulator
xcodebuild -project Spotter.xcodeproj -scheme SpotterNotes -configuration Debug \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData build

# Release, unsigned — proves the archive configuration compiles
xcodebuild -project Spotter.xcodeproj -scheme SpotterNotes -configuration Release \
    -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData \
    CODE_SIGNING_ALLOWED=NO build
```

The project signs manually with Developer ID, which cannot sign an iOS app, so the target overrides
both configurations: `CODE_SIGN_STYLE = Automatic`, `CODE_SIGN_IDENTITY = Apple Development`, team
`Q9MD524YL5`, no `--timestamp` flag, no hardened runtime, no entitlements file. A device build or an
archive therefore needs that team signed in to Xcode. The `Build Local Embedding Helper` script
belongs to the Mac target alone, and the `Spotter` scheme still builds only the Mac app.

`MARKETING_VERSION` is the project's; `CURRENT_PROJECT_VERSION` is the target's own, so a TestFlight
build number moves without touching the Mac. The Info.plist declares
`ITSAppUsesNonExemptEncryption = false`, and `PrivacyInfo.xcprivacy` declares no tracking, no
collected data, and the two required-reason APIs in use: `UserDefaults` (CA92.1) and file timestamps
of files the user granted access to (3B52.1).

## Tests

```sh
scripts/test-all.sh --jobs 4
```

- `note` (`Tools/note-test.swift`) pins what the strip draws — the marker rule (a leading or trailing
  Emoji, a joined sequence, a flag, a skin tone and a keycap each as one marker, none without an
  Emoji), the label of an untitled draft, newest-first order, an edit moving its Note to the front,
  wrap-around navigation, the open Note remembered across launches and which Note is selected after
  a deletion — and the seams: both `NoteFolderLocation` shapes over a real
  defaults suite and temporary folders (what each persists, a bookmark following a renamed folder, a
  deleted folder reading as unresolvable with its bookmark kept), the status wording for the Mac and
  for iOS, and a folder with no Trash (the file kept byte for byte, the tombstone in the ledger, the
  rest of the pass written, no second attempt until the file changes, any other error still fatal).
- `note-ios` (`Tools/note-ios-test.swift`) runs `NoteInputRules` on macOS with the real engine and
  calculator: every input rule and every accessory command.

Neither opens the app, a simulator or a real iCloud Drive folder. The editor's UIKit layer and the
SwiftUI screens have no harness.
