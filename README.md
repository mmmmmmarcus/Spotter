# Spotter

A tiny, fully native macOS launcher — the essentials, without the bloat.

<p align="center">
  <a href="https://discord.gg/v2Eeb4QQy3">
    <img alt="Join the Spotter Discord"
         src="https://img.shields.io/badge/Discord-Join%20the%20community-5865F2?style=flat&logo=discord&logoColor=white"></a>
  <a href="LICENSE">
    <img alt="License: AGPL-3.0"
         src="https://img.shields.io/badge/License-AGPL--3.0-3DA639?style=flat"></a>
</p>

<!-- Screenshot placeholder — drop the real image at docs/screenshot.png -->
<p align="center">
  <img src="docs/screenshot.png" alt="Spotter command palette" width="720">
</p>

Around **3 MB on disk** and **under 100 MB of RAM** — no Electron, no telemetry, no background
CPU churn. Just SwiftUI + AppKit with zero dependencies. It's fast because there's nothing to it.

## Features

- **App launcher** — fuzzy-search and launch anything, pin favorites, see what's running, quit an app
  or every app at once.
- **Custom commands** — run named shell commands through fuzzy search or their own global hotkeys.
- **Calculator** — do math, unit and live currency conversions inline, right in the palette.
- **Clipboard history** — text and images, searchable, pasted back into the app you were using.
- **Notes** — capture unlimited local Markdown notes and todos in a floating, keyboard-first window.
- **Quicklinks** — save links, files and deep links as launcher entries, with `{argument}`
  placeholders Spotter asks you to fill before opening.
- **Emoji & symbols** — find and insert emoji from a fast native grid.
- **World clock** — type queries such as `SF time now` or `time in Tokyo` for an inline answer.
- **Kill process** — inspect CPU and memory use, group app helpers, then terminate or restart safely.
- **Change case** — transform selected or copied text through 21 cases, then copy or paste it.
- **Selection tools** — search, translate, or grammar-check text selected in any app via your own
  OpenRouter key.
- **Text replacement** — expand your own prefix+keyword triggers into saved text as you type.
- **Settings sync** — keep one JSON settings file (e.g. in iCloud Drive) applied across your Macs.
- **In-app updates** — check GitHub Releases and update from Settings; signature-verified, and your
  permissions survive.
- **Image modification** — batch-convert, resize, filter, optimize, pad, rotate, remove backgrounds,
  and clear metadata with native macOS frameworks.
- **Window management** — halves, quarters, thirds, sizing and display moves for any window.
- **System commands** — lock, sleep, volume, Bluetooth, trash and more, straight from the launcher.
- **Mole** — drive the Mole CLI without leaving the launcher: health, cleanup, optimize, purge,
  uninstall and disk analysis, each previewed before it runs.
- **Coffee** — keep your Mac awake indefinitely, for a set time, or while an app runs.
- **QuickTime recording** — start a screen, audio, or movie recording directly from the launcher.
- **Native plugins** — independently organized, individually enabled feature modules with shared
  settings, permissions, commands and shortcuts, compiled directly into the app for native speed.
- **Global hotkey** — one shortcut summons the palette from anywhere.
- **Per-app hotkeys** — bind a key to an app; press it to toggle (focus/hide).

## Install

```sh
brew trust --tap mmmmmmarcus/spotter   # required for third-party taps
brew tap mmmmmmarcus/spotter
brew install --cask spotter          # stable
brew install --cask spotter@beta     # beta  (installs side-by-side)
```

Each channel is a separate app (`Spotter.app`, `Spotter Beta.app`) with its own settings and
permissions, so you can run stable next to the beta.

Spotter is self-signed. Installing via Homebrew clears the macOS quarantine flag for you
automatically on every install and update, so there's nothing to run. (If you download the DMG
directly from Releases instead, clear it once: `xattr -dr com.apple.quarantine
"/Applications/Spotter.app"`.)

## Permissions

**Accessibility** — used to paste into the app you came from and to read selected text for plugins
such as Change Case. You're prompted on first use.

**Automation** — used only when a command asks another app to act: QuickTime Recording controls
QuickTime Player, and Image Modification can read Finder's current selection. Manage both grants in
**System Settings → Privacy & Security**.

## Using it

1. Open **Settings → General** and record a global shortcut to summon Spotter.
2. Press it anywhere → the palette floats in. Type to filter, **↵** to launch.
3. **Tab** switches between Apps and Clipboard; **↑/↓** move, **Esc** dismisses.
4. **Settings → Shortcuts** — search an app or custom command and record a global shortcut.

## Building from source

See **[docs/development.md](docs/development.md)** for the toolchain, build, packaging, release,
and website workflows, **[docs/plugins.md](docs/plugins.md)** for the built-in plugin architecture,
and **[docs/ui.md](docs/ui.md)** for the UI design system. The repository also ships the
`$spotter-plugin` Codex skill under `.codex/skills/` for creating, modifying, or removing native
plugin modules.

## Contributing

> [!IMPORTANT]
> **Open an issue before you write code — this is mandatory.** Get the bug or the feature agreed on
> first; discussing it in the issue (or on [Discord](https://discord.gg/v2Eeb4QQy3)) is strongly
> encouraged. A PR with no agreed issue behind it gets closed however good the patch is, and the
> work is wasted. Typo and docs-only fixes are the one exception.

Read **[CONTRIBUTING.md](CONTRIBUTING.md)** first — it covers the memory budget every PR is held to,
the before/after video requirement for visual changes, and why features get declined. Every PR fills
in the **[pull request template](.github/PULL_REQUEST_TEMPLATE.md)**. Security issues go through
[SECURITY.md](SECURITY.md), not the issue tracker.

Questions, ideas, or just want to follow along? **[Join the Discord](https://discord.gg/v2Eeb4QQy3)**.

## Contributors

Thank you to everyone who has put time into Spotter — every fix and idea shows up in something
people use every day.

<p align="center">
  <a href="https://github.com/mmmmmmarcus/Spotter/graphs/contributors">
    <img alt="Spotter contributors"
         src="https://contrib.rocks/image?repo=mmmmmmarcus/Spotter&max=28&columns=28">
  </a>
</p>

## Credits

Spotter began as a fork of **[Tinycast](https://github.com/abue-ammar/tinycast)** by
[Abue Ammar](https://github.com/abue-ammar), and its launcher, palette, calculator and clipboard
foundations come from that work. Spotter has since developed independently — native plugin
architecture, Notes, Selection Tools, settings sync, in-app updates — but the original copyright
stands and this project stays under the same license.

## License

[AGPL-3.0](LICENSE) · Spotter © 2026 Marcus Fei · portions © 2026 Abue Ammar (Tinycast)
