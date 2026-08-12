# Settings sync

Settings → Backup can attach Spotter to one user-selected JSON file. Creating a file writes the live
state; choosing an existing file validates and applies it before the path is persisted. Manual
backup and automatic sync share the human-readable `SettingsBackup` format.

The path can be anywhere. When it is inside iCloud Drive, macOS transports it to the user's other
Macs; Spotter itself uses no network service or CloudKit container. Synchronization can be paused or
disconnected without deleting the file.

## Coverage

Format v3 mirrors the complete user-owned Spotter state:

- General and system-feature settings, plugin enable states and preferences, including every network
  consent toggle.
- OpenRouter and Google Cloud Translation API keys and all associated model options.
- Every shortcut. Empty binding maps are authoritative, so unbinding a shortcut propagates.
- Custom commands, favorites, hidden launcher items, Quicklinks, World Clock cities and Text
  Replacement rules.
- Notes and selected note, text and image clipboard history, pinned clipboard state, calculator
  history, AI conversations and current conversation, background-task rows, frequent emoji and
  learned launcher ranking.

Clipboard image bytes are embedded in the JSON and rebuilt under each Mac's own bundle-scoped cache;
absolute cache paths never cross devices. Because v3 files can contain credentials and private
content, the Backup pane and trust dialogs tell the user to keep them in a private location.

The only user-owned state deliberately excluded is device-bound: the palette's concrete screen
coordinates, macOS privacy grants, and the synchronization file's own path/enabled state. The
“remember position” preference itself does sync. Runtime executors, provider response caches,
temporary files and system-derived data are not backup state.

Older v1/v2 files remain importable. Missing fields are preserved during a manual import, while an
automatic v3 snapshot is authoritative: arrays, credentials and shortcuts can therefore propagate
deletions and cleared values.

## Live pipeline

`AppCore` owns one `SettingsSyncManager`. It observes every store represented by `SettingsBackup`,
debounces local changes, gathers canonical sorted JSON and writes it through `NSFileCoordinator`.
An `NSFilePresenter` receives coordinated iCloud updates, while a parent-directory dispatch source
also catches uncoordinated editors and atomic file replacement. Reads and writes pass through one
actor so they cannot race inside a process; when two Macs write independently, the last file version
delivered by the sync provider becomes the shared snapshot.

External bytes are decoded completely before they touch live state. A different valid snapshot is
applied on the main actor and hot-updates the owning stores. Locally executing AI requests and
background tasks keep their executors so a remote snapshot cannot orphan work in progress. The last
effective JSON bytes suppress Spotter's own write notifications and normalized re-exports, preventing
feedback loops. Malformed or unavailable files leave live state untouched, surface an inline error
and remain watched for recovery.

Connecting a file requires an explicit trust alert because future changes are applied automatically.
Fresh installs still default every network feature to off; trusting a sync file or manually importing
a backup is the consent act that may restore its saved toggles and keys. Requests continue to re-check
their owning consent flag around every network call and use private cacheless sessions.
