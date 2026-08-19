# Commands plugin

Commands combines two command sources in **Settings → Plugins → Commands**:

- 30 read-only built-in macOS actions maintained by Spotter, each with an optional shortcut.
- User-authored shell commands that can be added, edited and deleted.

Both appear in the launcher's Commands section and share normal fuzzy ranking. Built-ins execute
through native system-command routes; only user-authored commands reach the shell runner.

## Ownership and persistence

`CustomCommandStore` is owned by `AppCore` and persists the ordered command array as JSON in
bundle-scoped `UserDefaults`. Each command has a stable UUID. Its launcher entry id is
`custom-command:<uuid>`, and its hotkey uses
`KeyboardShortcuts_customCommandHotkey.<uuid>` plus the `boundCustomCommandIDs` index.

Editing preserves the UUID and therefore its favorite, visibility, and hotkey references. Deleting
goes through `AppCore`, which unregisters the hotkey and clears those references before removing the
command. Native settings backups include both commands and bindings; import warns before accepting
executable content.

`CommandsPlugin` owns the feature registration and Settings view. Disabling it withdraws both the
built-in and custom launcher entries and makes their hotkeys no-op. It leaves the custom-command
store, UUIDs, favorites, visibility, hotkeys and backup data intact. Re-enabling republishes the same
entries. A custom process that was already launched continues under the existing no-timeout
execution contract.

## Launcher integration

`AppIndex` combines applications/System Settings discovered off-main with signed in-process commands
from `CommandRegistry` and enabled registrations. Commands publishes user-authored entries through
`dynamicLauncherCommands`, then calls `reloadDynamicCommands(for: .commands)` when the store changes.
The index publishes one alphabetized command slice after discovered apps. This keeps the visible row
order identical to the flat palette selection while allowing plugin toggles or command edits to
invalidate fuzzy results without rescanning disk.

Built-in commands are native closures registered through `PluginRegistry`; only user-authored custom
commands reach `ShellCommandRunner`.

The command text is deliberately not searchable. Only the user-facing name enters fuzzy matching.

## Execution contract

`ShellCommandRunner` executes asynchronously with:

- `/bin/zsh -lc <command>`, or `/bin/zsh -ilc <command>` when the command's **Load shell
  environment** flag is on
- the user's home directory as the working directory
- standard input and output connected to `/dev/null`
- `SPOTTER=1` added to the inherited environment
- up to 8 KiB of standard error retained for a failure alert

No Terminal window or pseudo-terminal is created. `waitUntilExit` blocks for the whole life of the
command, so it runs on a private concurrent `DispatchQueue` rather than a cooperative-pool thread a
long `brew upgrade` would hold for minutes.

### Load shell environment

zsh reads `~/.zshrc` **only for interactive shells**, so the default `-lc` sees `.zprofile` and
`.zlogin` and nothing else — a user's aliases, functions and `PATH` edits are all absent, and the
command exits **127**. That is the single most common way a custom command fails. The flag switches to
`-ilc`, which sources the rc file.

It is per-command and off by default, because turning it on runs whatever the user's shell startup
does — oh-my-zsh's auto-update (`git pull`, network, seconds), powerlevel10k's `gitstatusd`,
`compinit` rewriting `~/.zcompdump`, or an `exec` that replaces the shell so the command never runs at
all. `SPOTTER=1` exists so an rc file can skip those sections: `[[ -n $SPOTTER ]] && return`.

Measured cost: ~10 ms for `-lc`, ~65 ms for `-ilc` against a real-world `~/.zshrc` (~11 ms against a
minimal one — the interactive shell itself is ~2 ms, the rest is the user's own config).

Interactive prompts still cannot block. Standard input is `/dev/null`, so a `read` gets EOF and
returns non-zero, and a launchd-launched app has no controlling terminal, so `/dev/tty` fails with
`device not configured`. A dev build launched *from a terminal* inherits that terminal's tty, so an rc
file reading `/dev/tty` can hang there but not for real users. There is **no timeout** — Spotter
never kills a running command, and a command outlives Spotter quitting.

Because standard error surfaces only on a non-zero exit and only its last 8 KiB, rc-file startup noise
is dropped while the actual error survives.

### Needs confirmation

`AppCore.runCustomCommand(id:)` is the one funnel both palette activation and the global hotkey reach,
so the gate lives there and neither path can bypass it. Confirmation uses the shared in-palette card,
and ↵ initially belongs to **Cancel**: the command is one ↵ away in the palette, and a reflexive second ↵ must not fire
something the user asked to be warned about. A hotkey invoked while the palette is closed opens that
same confirmation surface, so there is no separate dialog path to drift.

### Reporting

Spotter closes the palette and starts a custom command without creating a background-task row. A zero
exit shows a brief completion HUD; launch failure or non-zero exit activates Spotter to show the
bounded error detail. When the status is 127 and **Load shell environment** is off, the alert adds a
one-line hint and an **Open Settings…** button that lands on the Commands plugin pane — the hint is
gated on the status alone, not on grepping stderr, since 127 is equally a plain typo. The command
string itself is never shown or logged.

### Manual checks

`requiresConfirmation` is enforced in `AppCore` (AppKit, `@MainActor`) and so is out of reach of the
Foundation-only harness. Verify by hand:

1. Activating a gated command opens the in-palette card without shifting the search field.
2. ↵ on the card cancels; selecting **Run** and pressing ↵ runs.
3. A gated command triggered by hotkey with no palette open shows the same card.
4. An rc-file-only alias with the flag off shows the 127 hint, and **Open Settings…** opens the pane.
