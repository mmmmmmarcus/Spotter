# Settings sync

Settings → Backup groups manual export/import and automatic sync in one **Sync** card: one
**Export & Import** row offers both directions, and the rows beneath it attach Spotter to one
user-selected JSON file. Creating a file writes the live
non-Note state; choosing an existing file validates and applies it before the path is persisted.
Manual backup and automatic sync share the human-readable `SettingsBackup` format, but manual
exports/imports include Notes for disaster recovery while automatic Settings Sync always omits and
ignores Note content. Notes has its own replication — a user-chosen folder of Markdown files, under
Settings → Plugins → Notes — whose path is device-local and never travels here; only the Notes
window-transparency and auto-sizing preferences belong to trusted Settings state.

The path can be anywhere. When it is inside iCloud Drive, macOS transports it to the user's other
Macs; Settings Sync itself uses no network service or CloudKit records. Synchronization can be paused
or disconnected without deleting the file.

## Coverage

Format v3 covers the complete automatic Settings Sync state:

- General, system-feature and plugin preferences, including every network consent flag. There is no
  plugin enable state to carry, and Uptime's tallies stay device-local.
- OpenRouter and Google Cloud Translation API keys and all associated model options.
- Every shortcut — apps, panes, plugin actions, custom commands, quicklinks, AI commands and
  Spotter's own built-in commands. Empty binding maps are authoritative, so unbinding a shortcut
  propagates. A per-item binding is applied only once its item exists, which is why the quicklinks
  and AI commands themselves are restored before the shortcut map is.
- Custom commands, AI commands (names, prompts and per-command model choices), favorites, per-entry
  launcher aliases, hidden launcher items, Quicklinks, World Clock cities and Text Replacement
  rules. A file written before AI commands existed carries the two built-ins' prompts and models in
  their old fields instead, and those are read only when the file has no AI commands of its own.
- Text and image clipboard history, pinned clipboard state, calculator history, AI conversations and
  current conversation, background-task rows, frequent emoji and learned launcher ranking.

Manual backups additionally contain Notes and the selected note. Automatic Settings Sync does not
observe `NoteStore`, so typing never rewrites the larger Settings file and an incoming Settings
snapshot can never replace Notes. See [Notes](notes.md) for its independent folder pipeline.

A file written before Notes moved to a folder carries a `note.iCloudSyncEnabled` flag for the retired
CloudKit pipeline. It is now neither written nor read: the field is gone from the format, so the key
is ignored on decode and trusting such a file can never start CloudKit.

Clipboard image bytes are embedded in the JSON and rebuilt under each Mac's own bundle-scoped cache;
absolute cache paths never cross devices. Because v3 files can contain credentials and private
content, the trust dialog shown when a sync file is connected says so.

Alongside Note content, the other state deliberately excluded from automatic Settings Sync is
device-bound: the palette's concrete screen coordinates, macOS privacy grants, all three
synchronization paths (this file, the Notes folder and the retired CloudKit engine's local state),
and the uptime card's daily key/click tallies. Notes window transparency, Notes auto window sizing
and the “remember position” preference do sync. Runtime executors, provider response caches, temporary files
and system-derived data are not backup state.

Older v1/v2 files remain importable. Missing fields are preserved during a manual import, while an
automatic v3 snapshot is authoritative: arrays, credentials and shortcuts can therefore propagate
deletions and cleared values.

## Live pipeline

`AppCore` owns one `SettingsSyncManager`. It observes every automatic-sync store,
debounces local changes, gathers canonical sorted JSON and writes it through `NSFileCoordinator`.
An `NSFilePresenter` receives coordinated iCloud updates, while a parent-directory dispatch source
also catches uncoordinated editors and atomic file replacement. Reads and writes pass through one
actor so they cannot race inside a process; when two Macs write independently, the last file version
delivered by the sync provider becomes the shared snapshot.

External bytes are decoded completely before they touch live state. A different valid snapshot is
applied on the main actor and hot-updates the owning stores, with any legacy `notes` field ignored.
Locally executing AI requests and background tasks keep their executors so a remote snapshot cannot
orphan work in progress. The last
effective JSON bytes suppress Spotter's own write notifications and normalized re-exports, preventing
feedback loops. Malformed or unavailable files leave live state untouched, surface an inline error
and remain watched for recovery.

Connecting a file requires an explicit trust alert because future changes are applied automatically.
Fresh installs still default every network feature to off; trusting a sync file or manually importing
a backup is the consent act that may restore its saved toggles and keys. Requests continue to re-check
their owning consent flag around every network call and use private cacheless sessions.
