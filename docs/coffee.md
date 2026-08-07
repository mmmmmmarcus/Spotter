# Caffeinate plugin (directory `Coffee/`)

Keeps the Mac awake without touching Energy Saver, mirroring the
[Raycast Coffee extension](https://www.raycast.com/mooxl/coffee)'s command set. Ships **enabled**.
Display-renamed from Coffee (Aug 2026); `PluginID` stays `coffee` and the source directory stays
`Plugins/Coffee/` so persisted enable state and `KeyboardShortcuts_plugin.coffee.*` bindings survive.
The Toggle Caffeination command was dropped — Caffeinate / Decaffeinate are the pair, and the status
row's primary action still toggles.

## Commands

| Command | Behavior |
| --- | --- |
| Caffeinate | Stay awake until stopped |
| Decaffeinate | Release the assertion |
| Toggle Caffeination | Flip between the two |
| Caffeinate For… | Palette screen of durations (15m → 8h) |
| Caffeinate While App Runs… | Palette screen of running apps; ends when that app quits |
| Caffeination Status | Current state, with a live countdown for a timed session |

Each has its own bindable shortcut, so ⌘⌘-style double-taps work here too.

## How it holds the assertion

The state **is** a `/usr/bin/caffeinate` child process: it holds a power assertion for exactly as long
as it runs. That choice has two consequences worth keeping:

- Stopping means terminating the process, so there is no flag to get out of sync with reality.
- The assertion dies with Spotter. A crash — or quitting — can never leave a Mac permanently awake,
  which a manually-managed `IOPMAssertion` could.

`caffeinate` needs at least one assertion flag or it does nothing, so `-i` (idle sleep) is always
passed. `-d` (display) is on by default and `-m` (disk) is opt-in, both in Settings; changing either
restarts an active session, since flags only apply to a new process. `-t` implements durations and
`-w` implements the app-scoped mode — `caffeinate` exits on its own when the watched PID does, and
the termination handler folds that back into the UI so a finished session never shows a stale "on".

Disabling the plugin decaffeinates first: leaving the assertion held after the user switched the
feature off would be a lie about what's running.

## Layout

- `CoffeeTypes.swift` — durations, options→argument mapping, state and countdown formatting.
  Foundation-only and pure for `Tools/coffee-test.swift`.
- `CoffeeManager.swift` — the single `AppCore`-owned process owner, with `isolated deinit` teardown.
- `CoffeePlugin.swift` — registration, the three palette screens, `AppCore` entry points.
- `CoffeeSettingsView.swift` — enable switch, assertion options, shortcut recorders.
