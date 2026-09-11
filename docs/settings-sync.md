# Settings sync

Settings → Backup groups manual export/import and automatic sync in one **Sync** card: one
**Export & Import** row offers both directions, and the rows beneath it attach Spotter to one
settings file. **The user chooses the folder; Spotter owns the file name inside it**
(`Spotter Settings.json`), so there is one control for both directions and the folder's contents
decide which one runs: a settings file already there is validated and applied before the path is
persisted, and a folder that definitively has none gets a fresh one written from the live non-Note
state.

Manual backup and automatic sync share the human-readable `SettingsBackup` format, but manual
exports/imports include Notes for disaster recovery while automatic Settings Sync always omits and
ignores Note content. Notes has its own replication — a user-chosen folder of Markdown files, under
Settings → Plugins → Notes — whose path is device-local and never travels here; only the Notes
window-transparency and auto-sizing preferences belong to trusted Settings state.

The folder can be anywhere. When it is inside iCloud Drive, macOS transports the file to the user's
other Macs; Settings Sync itself uses no network service or CloudKit records.

## Connecting and disconnecting

**Turning Automatic Sync off *is* disconnecting**, so there is no separate Disconnect button. The
switch going off stops the watcher, releases the file presenter and its parent-directory source,
drops the recorded revision and the last-synced time, and removes the stored path — everything the
old Disconnect control did. The file itself is never touched; reconnecting means choosing a folder
again, which is the same trust prompt it always was.

The stored setting is still the full path (`settings-sync.file-path`), which is what makes the move
from a file picker to a folder picker invisible: a Mac that already chose a file keeps that exact
file, with no prompt and no re-selection, and its folder is simply read back off the path it already
holds. Nothing is renamed, moved or re-derived, and the migration touches the filesystem not at all.

**Unreachable is not unconfigured.** When a folder is joined, only a read that fails *because
nothing is there* (`NSFileNoSuchFileError` / `NSFileReadNoSuchFileError`, or `ENOENT`) may create a
file. Every other failure — an unplugged disk, a permissions refusal, an iCloud item that has not
materialized — means the file may well exist and simply cannot be reached, so Spotter reports the
condition and writes nothing; creating over it would destroy it. The same rule holds once a path is
configured: a failed read or write sets an inline error and the watcher keeps trying. **No IO
failure ever clears the stored path.** The only things that drop it are the user turning the switch
off and the user choosing a different folder.

## Format

`Spotter/Core/Backup/SettingsBackupData.swift` holds the two dependency-free halves of the snapshot —
every scalar setting and credential (`settings`) and every per-plugin preference (`pluginPrefs`) — so
`Tools/settings-sync-test.swift` compiles the real format and pins its JSON contract.
`SettingsBackup.swift` holds the rest of the record plus the gather/apply passes that touch the live
stores.

Every field is optional and every `Codable` conformance is synthesized: no `CodingKeys`, no
hand-written `init(from:)`. That is what makes both directions of compatibility work. A field a
writer didn't have is simply absent, and absent means *leave this Mac's value alone* — apply only
ever runs inside `if let`, so a missing field never resets anything and never throws. A field a
reader doesn't know is ignored rather than rejected. Only the `version` integer is checked, and only
to refuse a file from a future format.

## Coverage

Format v3 carries everything below. "Field" is the path inside the JSON.

### General

| Setting | Field |
| --- | --- |
| Clipboard retention | `settings.clipboardRetentionDays` |
| Apps excluded from clipboard history | `settings.clipboardDisabledApps` |
| Launch at login | `settings.launchAtLogin` |
| Hyper Key: physical key, ⇧ inclusion, quick press, glyph collapse | `settings.hyperKey`, `.hyperKeyIncludesShift`, `.hyperKeyQuickPress`, `.hyperKeyReplacesGlyph` |
| Emoji skin tone | `settings.emojiSkinTone` |
| Menu-bar icon / Dock icon | `settings.showInMenuBar`, `.showInDock` |
| Pop to root delay | `settings.popToRootSeconds` |
| Compact mode, favorites in compact mode | `settings.compactMode`, `.showFavoritesInCompactMode` |
| Open on the cursor's screen | `settings.openOnCursorScreen` |
| Remember palette position (the preference, not the point) | `settings.remembersPalettePosition` |
| Lock input to English | `settings.lockInputToEnglish` |
| Preferred terminal | `settings.preferredTerminal` |

### Launcher

| Setting | Field |
| --- | --- |
| Search scopes | `settings.searchScopes` |
| Section order and hidden sections | `settings.launcherSectionOrder`, `.launcherHiddenSections` |
| Favorites | `favoriteApps` |
| Hidden launcher items | `hiddenLauncherItems` |
| Per-entry aliases | `launcherAliases` |
| Learned ranking | `launcherRanking` |

### Shortcuts

Every binding, in `hotkeys`: palette and backup palette (`togglePalette`, `togglePaletteBackup`),
per-app (`apps`), per-settings-pane (`panes`), every plugin action (`pluginActions`, keyed
`<plugin-id>.<action-id>`, so a new plugin syncs with no format change), custom commands
(`customCommands`), quicklinks (`quicklinks`), AI commands (`aiCommands`) and Spotter's own built-in
commands (`builtInCommands`). Empty binding maps are authoritative, so unbinding propagates. A
per-item binding is applied only once its item exists, which is why quicklinks, custom commands and
AI commands are restored before the shortcut map is.

### Credentials and networked features

Restoring one of these *is* the consent act — the file is trusted explicitly before it is applied.

| Setting | Field |
| --- | --- |
| OpenRouter API key (the gate for AI Chat and every AI command) | `settings.openRouterAPIKey` |
| OpenRouter chat model, web search | `settings.openRouterChatModel`, `.openRouterChatWebSearch` |
| Google Cloud Translation API key (the gate for Translate) | `settings.googleTranslationAPIKey` |
| Translate target languages | `settings.googleTranslationTargets` |
| Daily update check consent | `settings.updateAutoCheckEnabled` |
| Currency-conversion consent | `settings.currencyRatesEnabled` |
| Weather consent and unit | `settings.dashboardWidgets.weatherEnabled`, `.weatherUnit` |

A **"have we asked yet" marker never travels**, only the answer. A grant that arrives in a trusted
file counts as answered, so the receiving Mac never re-prompts for a feature that is already on; but
a marker saying "asked" with the feature still off would suppress a dialog on a Mac where the user
has never seen the disclosure, which is exactly the wrong trade. Keep the local marker local and
derive "answered" from the restored grant.

### Plugins and system features

| Setting | Field |
| --- | --- |
| Widget strip order, calendar source, all-day events | `settings.dashboardWidgets.widgetOrder`, `.calendarSourceIdentifier`, `.includesAllDayEvents` |
| Change Case: source, primary action, case/punctuation preservation, exceptions, affixes, pinned, recent, disabled | `pluginPrefs.changeCase.*` |
| Kill Process: sort, grouping, search fields, prioritization, PID/path columns, refresh interval | `pluginPrefs.killProcess.*` |
| Image Modification: output location, format | `pluginPrefs.imageModification.*` |
| Screenshot: rounded corners, capture scale, file format, window shadow, hiding Spotter windows, preview duration | `pluginPrefs.screenshot.*` |
| Caffeinate: keep display / disk awake | `pluginPrefs.caffeinate.*` |
| Window Management: gap, cycle on repeat | `pluginPrefs.windowManagement.*` |
| Mole binary path override | `pluginPrefs.mole.binaryPath` |
| Notes window transparency and auto sizing | `pluginPrefs.note.*` |
| World Clock cities | `worldClockCities` |
| Quicklinks | `quicklinks` |
| Snippets prefix and rules | `textReplacement.prefix`, `.rules` |
| Custom commands | `customCommands` |
| AI commands (names, prompts, per-command models) | `aiCommands` |

A file written before AI commands existed carries the two built-ins' prompts and models in
`pluginPrefs.selectionTools` and `settings.openRouterDefinitionModel` / `.openRouterGrammarModel`
instead; those are read only when the file has no `aiCommands` of its own, and are still written so
an older build reading a new file keeps them.

### Content

`clipboardHistory` (text and image rows, pinned state and image bytes), `calculatorHistory`,
`aiChat` (sessions and the current one), `backgroundTasks`, `frequentEmoji`, `launcherRanking`.
Manual backups additionally contain `notes` and the selected note.

## Deliberately device-local

None of this travels, and each has its own reason.

| State | Why it stays |
| --- | --- |
| Uptime's counts, and any notion of it being enabled | Uptime is always on and has no consent flag, so there is nothing to carry; the tallies measure this Mac rather than configure it. |
| Plugin enable state | There is none — a plugin cannot be disabled. |
| `palettePositionX` / `palettePositionY` | the palette's concrete screen point; display geometry differs per Mac. The *preference* (`remembersPalettePosition`) does sync. |
| `settings-sync.file-path`, `settings-sync.enabled` | the path to this very file, and with it the folder the user chose. A path from another Mac points at nothing, or at the wrong thing. |
| `note.folder-sync.folder-path`, `note.folder-sync.adoption-pending` | the Notes folder is the other synchronization path, and choosing it is its own consent act. Adoption runs once per Mac. |
| Note content and `note.selected-id` | `NoteFolderSyncManager` owns per-Note replication through that folder; typing must never rewrite the larger Settings file, and an incoming snapshot must never replace Notes. Manual backups still include them. |
| `dashboard-widgets.uptime-day`, `-keys`, `-clicks`, `-session-start` | daily key/click tallies are a measurement of *this* Mac, not a setting. The consent flag does sync. |
| The located weather place, and `dashboard-widgets.clock-time-zone` derived from it | a coordinate describes the Mac it was measured on. With manual city entry gone there would be nothing to correct an imported one with, so each Mac locates itself and an unlocatable one keeps its *own* saved zone. Consent and unit do sync. |
| `update.last-check` | when this Mac last asked. Merging it would either suppress a due check or force a redundant one. |
| `background-tasks.owner-id` | identifies rows this process owns, so a synced row is never mistaken for work running here. |
| macOS privacy grants — Accessibility, Input Monitoring, Screen Recording, Automation, Full Disk Access | owned by `tccd` and keyed to this Mac and this signed bundle. Spotter cannot write them, and a "granted" flag that travelled would be a lie. |
| Onboarding marker (`Application Support/<bundle-id>/onboarded`) | per-install first-run state, deliberately a file so an uninstall clears it. |
| `app-identity-migration.*`, `plugin.command.visibility-initialized.*`, `plugin.command.visibility-migrated.*`, `hotkey.default-seeded.*` | one-shot migration and seed markers. Each Mac must run its own once; what they produce — hidden items, bindings — is what syncs. |
| `shortcuts.collapsedGroups` | which groups are folded in the Shortcuts pane. Window state, not a setting. |
| Caches: `currency-rates.json`, `weather.json`, app-icon and thumbnail caches, `Spotter.log` | provider responses and derived data, refetched or rebuilt locally. Clipboard image *bytes* are the exception and do travel, inside `clipboardHistory`. |
| `NSInitialToolTipDelay` | registration-domain default, never a user value. |
| The retired CloudKit Notes engine's local state | the pipeline has no entry point; a v3 file carrying `note.iCloudSyncEnabled` is ignored on decode and can never start it. |

Runtime executors, in-flight requests and temporary files are not backup state either.

Clipboard image bytes are embedded in the JSON and rebuilt under each Mac's own bundle-scoped cache;
absolute cache paths never cross devices. Because v3 files can contain credentials and private
content, the trust dialog shown when a sync file is connected says so.

Older v1/v2 files remain importable. Missing fields are preserved during a manual import, while an
automatic v3 snapshot is authoritative: arrays, credentials and shortcuts can therefore propagate
deletions and cleared values.

## Live pipeline

`AppCore` owns one `SettingsSyncManager`. It observes every automatic-sync store,
debounces local changes, gathers canonical sorted JSON and writes it through `NSFileCoordinator`.
File- and SQLite-backed stores get a publisher each; every defaults-backed store rides the single
`UserDefaults.didChangeNotification` subscription, which is why adding a defaults-backed setting
needs no new observer.
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
and remain watched for recovery — an unavailable file is never read as an absent one.

Connecting a file requires an explicit trust alert because future changes are applied automatically.
Fresh installs still default every network feature to off; trusting a sync file or manually importing
a backup is the consent act that may restore its saved toggles and keys. Requests continue to re-check
their owning consent flag around every network call and use private cacheless sessions.

Settings-originated export, import and folder pickers are attached sheets. Cancelling restores the originating window, including when a floating Note is open. Palette-originated operations retain their modal fallback. Backup explains the content scope and links directly to Notes Settings.
