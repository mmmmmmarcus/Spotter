# Spotter

A tiny, fully native macOS launcher — forked from Tinycast and renamed for this project.

<p align="center">
  <a href="https://discord.gg/v2Eeb4QQy3">
    <img alt="Join the upstream Tinycast Discord"
         src="https://img.shields.io/badge/Discord-Join%20the%20community-5865F2?style=flat&logo=discord&logoColor=white"></a>
  <a href="mailto:iabueammar@gmail.com?subject=Hiring%20enquiry">
    <img alt="Hire me — iabueammar@gmail.com"
         src="https://img.shields.io/badge/Hire%20me-Let's%20talk-111111?style=flat&logo=gmail&logoColor=white"></a>
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
- **Starter commands** — editable presets sleep the display or toggle macOS between Dark and Light Mode.
- **Calculator** — do math, unit and live currency conversions inline, right in the palette.
- **Clipboard history** — text and images, searchable, pasted back into the app you were using.
- **Global hotkey** — one shortcut summons the palette from anywhere.
- **Per-app hotkeys** — bind a key to an app; press it to toggle (focus/hide).

## Build & run Spotter

```sh
xcodegen generate
./Tools/setup-signing.sh       # once
./Tools/run-local.sh Debug
```

Every local Debug or Release run atomically updates and launches the same
`/Applications/Spotter.app` (`com.spotter.app`). The stable signing identity makes macOS recognize
rebuilds as updates, and the app refuses to run from DerivedData or alongside a second copy.
This fork is not published as a Homebrew cask.

## Permissions

**Accessibility** — needed only so Spotter can paste a clipboard item back into the app you
came from. You're prompted the first time you paste; grant it in **System Settings → Privacy &
Security → Accessibility**.

**Automation** — macOS may ask once for permission to control System Events when you first run the
starter command that toggles Dark / Light Mode. The display-sleep command needs no extra grant.

## Using it

1. Open **Settings → General** and record a global shortcut to summon Spotter.
2. Press it anywhere → the palette floats in. Type to filter, **↵** to launch.
3. **Tab** switches between Apps and Clipboard; **↑/↓** move, **Esc** dismisses.
4. **Settings → Shortcuts** — search an app or custom command and record a global shortcut.

## Building from source

See **[docs/development.md](docs/development.md)** for the toolchain, build, packaging, release,
and website workflows, and **[docs/ui.md](docs/ui.md)** for the UI design system.

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

Spotter builds on Tinycast and keeps its upstream contributors and AGPL-3.0 license acknowledged
below.

<p align="center">
  <a href="https://github.com/abue-ammar/tinycast/graphs/contributors">
    <img alt="Tinycast contributors"
         src="https://contrib.rocks/image?repo=abue-ammar/tinycast&max=28&columns=28">
  </a>
</p>

## License

[AGPL-3.0](LICENSE)
