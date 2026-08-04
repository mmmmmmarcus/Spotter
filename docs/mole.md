# Mole plugin

A front end for the [Mole](https://github.com/tw93/mole) CLI (`brew install mole`), which deep-cleans
and reports on a Mac. Ships **disabled** — it does nothing until Mole is installed and the plugin is
turned on.

## The split: rendered vs handed off

Mole's commands fall into two groups, and the plugin treats them differently on purpose.

`mole status` and `mole history --json` **emit JSON when stdout isn't a TTY**, so Spotter runs them
itself and renders the result as ordinary `PluginPaletteList` rows — health score, CPU, memory, disk,
trash, uptime, and past cleanup sessions. Enter copies a row's value. This is what closes the loop:
the common "how is my Mac doing" question never leaves the launcher.

Everything else — `clean`, `uninstall`, `optimize`, `analyze`, `purge`, `installer`, and the main
menu — is an interactive TUI that **deletes files behind its own confirmations**. Those are handed to
Terminal via AppleScript rather than run silently from a launcher; a palette has nowhere to show a
TUI, and running a destructive command with no visible confirmation would be the wrong default. They
ship `defaultVisible: false` so the launcher stays compact, and are revealable in System → Shortcuts.

## Layout

- `MoleTypes.swift` — the command catalog plus the two JSON parsers. Foundation-only and pure, so
  `Tools/mole-test.swift` compiles the real logic (`swiftc -swift-version 6
  Spotter/Plugins/Mole/MoleTypes.swift Tools/mole-test.swift`).
- `MoleManager.swift` — `AppCore`-owned state: binary discovery, off-main process runs, Terminal
  hand-off. A screen switch mid-flight discards the older response rather than letting it overwrite
  the newer screen.
- `MolePlugin.swift` — registration, palette-screen snapshot mapping, `AppCore` entry points.
- `MoleSettingsView.swift` — enable switch, binary path override, shortcut recorders.

## Finding the binary

Homebrew's Apple-silicon and Intel prefixes are checked for both `mole` and its `mo` alias; a manual
install is handled by the path override in Settings (`mole.binary-path`). When nothing is found the
palette says so instead of failing silently, and the settings pane shows an install hint.
