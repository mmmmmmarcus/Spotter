# Settings sync

Settings → Backup can attach Spotter to one user-selected JSON file. Creating a file writes the live
configuration; choosing an existing file validates and applies it before the path is persisted. The
same file remains a normal, human-readable `SettingsBackup`, so manual export/import and automatic
sync do not create competing formats.

The path can be anywhere. When it is inside iCloud Drive, macOS transports it to the user's other
Macs; Spotter itself uses no network service or CloudKit container. The Settings pane shows whether
the selected item is an iCloud ubiquitous item and allows synchronization to be paused or disconnected
without deleting the file.

## Live pipeline

`AppCore` owns one `SettingsSyncManager`. It observes the stores represented by `SettingsBackup`,
debounces local changes, gathers canonical sorted JSON and writes it through `NSFileCoordinator`.
An `NSFilePresenter` receives coordinated iCloud updates, while a parent-directory dispatch source
also catches uncoordinated editors and atomic file replacement. Reads and writes pass through one
actor so they cannot race.

External bytes are decoded completely before they touch live state. A different valid snapshot is
applied on the main actor and immediately updates preferences, shortcuts, commands, favorites,
visibility and safe plugin enable states. The last effective JSON bytes suppress notifications from
Spotter's own writes and normalized re-exports, preventing feedback loops. Malformed or unavailable
files leave live settings untouched, surface an inline error and remain watched for recovery.

Connecting a file requires an explicit trust alert because settings JSON may include custom shell
commands, global shortcuts and the OpenRouter API key. Network-consent states remain excluded — the
plugin flags through the existing `exportsEnabledState` contract and OpenRouter's enable flag by
staying on `OpenRouterStore` — so synchronization cannot grant network access: a synced Mac receives
the key and model but AI features stay off until enabled locally. The key travels in plain JSON, so
the file should live somewhere private (iCloud Drive is fine; a shared folder is not).
