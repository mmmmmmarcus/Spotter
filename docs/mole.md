# Mole

A launcher front end for the [Mole](https://github.com/tw93/mole) CLI (`mole` / `mo`). Every Mole
command that can run without a terminal runs inside Spotter's palette — reading, previewing and
executing — so the loop closes in the launcher instead of handing off to Terminal.

Disabled by default; the plugin does nothing until Mole is installed and it is switched on. Files
live in `Spotter/Plugins/Mole/`.

## Files

| File | Role |
| --- | --- |
| `MoleTypes.swift` | Foundation-only, pure: the command catalog, screens, actions, and every output parser. |
| `MoleManager.swift` | Locates the binary, runs Mole off-main, owns screen state and the Analyze navigation trail. |
| `MolePlugin.swift` | Registration, palette snapshots, ⌘K menus, the confirmation dialog, and the `AppCore` entry points. |
| `MoleSettingsView.swift` | Enable switch, binary path override, per-screen shortcuts. |

`Tools/mole-test.swift` compiles `MoleTypes.swift` directly, so it must stay free of AppKit and
SwiftUI, and its parsers must stay pure. The harness never executes Mole.

## Finding the binary

`/opt/homebrew/bin/mole`, `/usr/local/bin/mole`, then the `mo` aliases — or an explicit path saved
under `mole.binary-path` in Settings. With nothing found, every screen reports it rather than failing
silently.

## Screens

`Mole` opens the hub listing every command; each is also its own launcher entry and can take a global
shortcut. The section header names the screen, and the placeholder changes with it through
`livePlaceholder`.

| Screen | Reads | Rows |
| --- | --- | --- |
| **Menu** | nothing | Every Mole command, opening its screen |
| **System Status** | `mole status` | Health score, CPU, memory, disks, trash, uptime, hardware |
| **Clean** | `mole clean --dry-run` | A run row, then every reclaimable cache with its size |
| **Optimize** | `mole optimize --dry-run` | A run row, then every maintenance item |
| **Purge** | `mole purge --dry-run` | A run row, then every build-artifact directory with its size |
| **Uninstall** | `mole uninstall --list` | Every installed app with its icon, path and size |
| **Analyze Disk** | `mole analyze -json <dir>` | Folder contents by size; ↵ descends, a Back row climbs out |
| **Cleanup History** | `mole history --json` | Past sessions with item counts and reclaimed size |

Every read-only pass runs with stdin on `/dev/null` and stdout on a pipe, which is what makes Mole
take its non-interactive path: no TUI, no sudo prompt, nothing waiting on a keystroke.

**Remove Installers is the one exception.** It always draws a full-screen selector and reads raw
keystrokes, so it can't be rendered; it ships hidden from the launcher and opens in Terminal.

## Running commands

`MoleAction` is the whole state-changing surface — `clean`, `optimize`, `purge` and
`uninstall(name:permanent:)`. Everything funnels through `AppCore.runMoleAction`, so no path can skip
the confirmation:

- The dialog names the action and says exactly what it removes.
- On the irreversible ones — Purge, and Delete Permanently — **Return is bound to Cancel**, because a
  destructive row is one ↵ away in the palette and a reflexive second ↵ must not wipe a build folder.
- Uninstall moves the app to the Trash by default; **Delete Permanently** is a separate ⌘K entry.
- Admin-only system caches are skipped: Mole asks for sudo on a TTY, and there isn't one.

The palette deliberately stays open while a run is in flight. The run row reports progress, and the
preview underneath re-reads itself when the run finishes so what's left is what's shown. Closing the
palette cancels a *preview* but never a run — a half-cleaned machine is worse than a wasted read.

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
