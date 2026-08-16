# Mole

A launcher front end for the [Mole](https://github.com/tw93/mole) CLI (`mole` / `mo`). Read-only
screens and previews stay inside Spotter's palette; confirmed mutations return to the normal
launcher and continue as background tasks instead of handing off to Terminal.

Enabled by default, but idle until the Mole CLI is actually installed — every screen reports the
missing binary rather than failing silently. Files live in `Spotter/Plugins/Mole/`.

## Files

| File | Role |
| --- | --- |
| `MoleTypes.swift` | Foundation-only, pure: the command catalog, screens, actions, and every output parser. |
| `MoleProcessRunner.swift` | Foundation process runner: applies preview-only environment and propagates task cancellation to Mole. |
| `MoleManager.swift` | Locates the binary, runs Mole off-main, owns screen state, streamed run progress and the Analyze navigation trail. |
| `MolePlugin.swift` | Registration, palette snapshots, ⌘K menus, the confirmation dialog, and the `AppCore` entry points. |
| `MoleSettingsView.swift` | Enable switch, binary path override, per-screen shortcuts. |

`Tools/mole-test.swift` compiles `MoleTypes.swift` directly, so it must stay free of AppKit and
SwiftUI, and its parsers must stay pure. The harness never executes Mole.

## Finding the binary

`/opt/homebrew/bin/mole`, `/usr/local/bin/mole`, then the `mo` aliases — or an explicit path saved
under `mole.binary-path` in Settings (synced through `SettingsBackup.PluginPrefs.Mole`; harmless on a
machine where the path isn't executable, since the locator falls back to the search list). With
nothing found, every screen reports it rather than failing silently.

## Screens

`Mole` opens the hub listing every command; each is also its own launcher entry and can take a global
shortcut. The section header names the screen, and the placeholder changes with it through
`livePlaceholder`.

| Screen | Reads | Rows |
| --- | --- | --- |
| **Menu** | nothing | Every Mole destination, without a self-referential hub row |
| **System Status** | `mole status` | Health score, CPU, memory, disks, trash, uptime, hardware |
| **Clean** | `mole clean --dry-run` | A run row, then every reclaimable cache with its size |
| **Optimize** | `mole optimize --dry-run` | A run row, then every maintenance item |
| **Purge** | `mole purge --dry-run` | A run row, then every build-artifact directory with its size |
| **Uninstall** | `mole uninstall --list` + local Homebrew ownership JSON | Every safely targetable installed app with its icon, path and size |
| **Analyze Disk** | `mole analyze -json <dir>` | Folder contents by size; ↵ descends, a Back row climbs out. Roots at the home folder on every open |
| **Cleanup History** | `mole history --json` | Past sessions with item counts and reclaimed size |
| **Installer Files** | nothing — Spotter's own scan | Every installer file with icon, folder and size; ↵ moves it to the Trash |

Every read-only pass runs with stdin on `/dev/null`, stdout on a pipe and `MO_NO_OPLOG=1`. This makes
Mole take its non-interactive path without turning a preview into thousands of operation-log writes:
no TUI, no sudo prompt, nothing waiting on a keystroke. Nothing hands off to Terminal — the whole
plugin lives in the launcher.

Mole 1.50's Homebrew-cask probe can terminate `uninstall --list` halfway through its JSON under the
system Bash 3.2. Spotter obtains that read-only app inventory with Homebrew removed from the child
`PATH`, then independently reads `brew info --json=v2 --installed --cask` locally. A Homebrew cask is
reveal-only because asking Mole to remove it as a normal app would leave Homebrew's installed receipt
inconsistent. Copies that Mole cannot uniquely address by display name or bundle filename are also
reveal-only, so selecting one can never delete a different copy.

Clean is an intrinsically broad disk scan in Mole. Spotter keeps it from multiplying that cost:
cancelling, closing or refreshing interrupts the old subprocess; reopening the same completed screen
within 30 seconds reuses its preview; a real run never overlaps another preview; and a run that
finishes while the palette is hidden does not start a second scan in the background. Refresh remains
an explicit way to discard the short-lived preview and scan again. During the first full scan,
completed Clean sections stream into the palette immediately; the run row remains disabled and shows
the partial item count until the preview is complete.

**Installer Files never invokes Mole at all.** Mole's selector is TUI-only (and truncates long
names), so `MoleManager` walks the same folders with the same rules — `MoleInstallerScan` mirrors
`INSTALLER_SCAN_PATHS`, the depth-2 limit, the `.dmg/.pkg/.mpkg/.iso/.xip` extensions, and the
"a zip counts only when its `zipinfo` listing contains an installer" test. Deleting one is a native
`FileManager.trashItem` — recoverable, confirmed in-palette, reported through the HUD — and it
works even with the Mole binary missing. The walk never descends below depth 2 and cancellation is
propagated to its background task when the screen closes. Large roots stream the folder currently
being visited and any installer rows already found, so the palette remains informative throughout.

## Running commands

`MoleAction` is the whole state-changing surface — `clean`, `optimize`, `purge` and
`uninstall(name:permanent:)`. Everything funnels through `AppCore.runMoleAction`, so no path can skip
the confirmation:

- The confirmation is the shared **in-palette card**, never a system dialog. It names the action,
  says exactly what it removes, and its highlight starts on Cancel — a destructive row is one ↵ away
  in the palette, and a reflexive second ↵ must not wipe a build folder.
- Uninstall moves the app to the Trash by default; **Delete Permanently** is a separate ⌘K entry.
- Admin-only system caches are skipped: Mole asks for sudo on a TTY, and there isn't one.
- After Spotter's confirmation, only Uninstall receives Mole's required `y` line on stdin. Every
  other run keeps stdin closed. The process runner checks the real exit status, retains stderr and
  reports a failed or partial command as Failed instead of treating non-empty output as success.

After confirmation, Spotter creates a launcher background task and returns to a fresh launcher root.
The task sits below Widgets and above Favorites, then stays above searched results while
Mole runs, even if the palette is closed or the query changes.
Clean, Optimize and Purge use the preview item count as a progress estimate; Uninstall stays
indeterminate and reports its latest streamed status rather than inventing a percentage. Closing the
palette cancels and interrupts a *preview* but never a run — a half-cleaned machine is worse than a
wasted read. Done and Failed rows remain until selected and dismissed with Return. See
[background-tasks.md](background-tasks.md).

Beyond the per-row actions, every screen's ⌘K menu carries Refresh (⌘R), All Mole Commands, and Mole
Settings…; app rows add Move to Trash / Delete Permanently / Reveal in Finder / Copy Bundle ID, and
path-backed rows add Reveal in Finder / Copy Path. All Mole Commands clears the current screen's
filter before returning to the hub.

## Launcher hand-off

An app row's ⌘K menu in the launcher offers **Uninstall with Mole** (apps only, never Spotter
itself, only while Mole is installed and the plugin enabled). It opens the Mole inventory filtered
to that app, rather than passing an unverified display name directly; selecting the resolved row then
uses the same `runMoleAction` confirmation and returns to the launcher with an Uninstalling
background-task row.

## Parsing

Only `status`, `history`, `uninstall --list` and `analyze -json` emit JSON. `clean`, `optimize` and
`purge` emit colored, repainted text, so `MoleParser` strips ANSI (treating `\r` as a line break,
since Mole redraws lines in place) and then reads the structure:

- `➤ Section` headers, plus bare all-caps lines, start a section.
- `→`, `✓` and `⊙` mark items; ` · ` splits an item from its size or count.
- A fixed set of closing prefixes (`Potential space:`, `Tracked cleanup:`, `Free space:`,
  `Dry run complete`, `Skipped while active:`, …) becomes the summary shown on the run row.
- Everything else — banners, whitelist echoes, file-list hints — is dropped.

`mole purge` prints `✓ [DRY RUN] <path>, <size>`; the size is taken from the **last** comma, because
project paths contain commas.
