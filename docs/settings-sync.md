# Settings sync

Settings → Backup can attach Spotter to one user-selected JSON file. Creating a file writes the live
configuration; choosing an existing file validates and applies it before the path is persisted. The
same file remains a normal, human-readable `SettingsBackup`, so manual export/import and automatic
sync do not create competing formats.

The path can be anywhere. When it is inside iCloud Drive, macOS transports it to the user's other
Macs; Spotter itself uses no network service or CloudKit container. The Settings pane shows whether
the selected item is an iCloud ubiquitous item and allows synchronization to be paused or disconnected
without deleting the file.

Coverage is deliberately complete for *configuration*: general settings (including
`lockInputToEnglish` and `remembersPalettePosition`), every bound hotkey (including all plugin
actions, keyed `<plugin-id>.<action-id>` so new plugins sync automatically), custom commands,
favorites, visibility, plugin enable states, the OpenRouter key and per-action models, per-plugin
preferences (Change Case, Kill Process, Image Modification, Caffeinate, Window Management, Mole's
binary path), Quicklinks, World Clock's saved cities, and Text Replacement's prefix and rules.
Content and learned state stay local by design: clipboard history, calculator history, notes,
learned launcher ranking and frequent emoji. Two consent flags are deliberately excluded so an
import can never grant network access: Currency Conversion's network consent (via
`exportsEnabledState: false`) and the auto-update check consent on `UpdateStore`.

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
commands, global shortcuts and the OpenRouter API key. Plugin network-consent flags remain excluded
through the existing `exportsEnabledState` contract. The OpenRouter key is the one deliberate
exception (owner decision, Aug 2026): the key itself is the gate, so a synced Mac that receives it
has the AI path active immediately — syncing the key is the consent act. The key travels in plain
JSON, so the file should live somewhere private (iCloud Drive is fine; a shared folder is not).
