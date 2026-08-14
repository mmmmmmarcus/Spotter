# Spotter

A tiny, fully native macOS launcher — the essentials, without the bloat.

<p align="center">
  <a href="https://github.com/mmmmmmarcus/Spotter/releases/latest">
    <img alt="Latest release"
         src="https://img.shields.io/github/v/release/mmmmmmarcus/Spotter?display_name=tag&sort=semver"></a>
  <img alt="macOS 26 or later"
       src="https://img.shields.io/badge/macOS-26%2B-111111?logo=apple">
  <a href="LICENSE">
    <img alt="License: AGPL-3.0"
         src="https://img.shields.io/badge/License-AGPL--3.0-3DA639?style=flat"></a>
</p>

<p align="center">
  <img src="docs/screenshot.png" alt="Spotter command palette" width="720">
</p>

Spotter is a keyboard-first launcher that lives in the menu bar. It is built with SwiftUI and
AppKit, uses around **3 MB on disk** and **under 100 MB of RAM**, and has no Electron runtime,
telemetry or idle background CPU churn. Networked features are optional; the app is offline by
default.

## Install

1. Download the latest `Spotter-<version>.dmg` from
   **[GitHub Releases](https://github.com/mmmmmmarcus/Spotter/releases/latest)**.
2. Open the DMG and drag **Spotter.app** to **Applications**.
3. Launch Spotter and grant Accessibility or Automation only when a feature asks for it.

Public releases are signed with Developer ID, notarized by Apple and checked by Gatekeeper. Do not
remove quarantine attributes or bypass macOS security prompts.

Spotter requires **macOS 26 or later**.

## What it does

### Launch and act

- Fuzzy-search apps, pin favorites, see running state, and quit one app or all apps.
- Assign one global launcher shortcut and per-app toggle shortcuts.
- Run built-in macOS actions and your own shell commands from the same command palette.
- Save parameterized Quicklinks for websites, files and deep links.

### Work with text and content

- Search and paste text or image clipboard history back into the app you were using.
- Keep unlimited local Markdown notes and todos in a keyboard-first floating workspace.
- Expand personal text-replacement triggers without recording arbitrary typing.
- Transform selected text, search it, translate it, define it bilingually or check its grammar.
- Find and insert emoji and symbols from a native grid.

### Calculate and look things up

- Evaluate arithmetic, units and opt-in live currency conversions inline.
- Glance at an analog clock, opt-in weather and your next calendar event on the empty launcher.
- Query world clocks with phrases such as `time in Tokyo`.
- Use AI Chat and selected-text AI actions with your own OpenRouter API key, or hand a prompt to
  ChatGPT on the web with Shift-Tab.

### Control the Mac

- Move and resize windows into halves, quarters, thirds and other layouts.
- Inspect, terminate or restart processes while excluding protected system processes and Spotter.
- Convert, resize, optimize, rotate, pad or remove metadata and backgrounds from images.
- Keep the Mac awake indefinitely, for a duration or while another app runs.
- Use the optional Mole integration for previewed cleanup, health, uninstall and disk analysis.

### Keep it yours

- Enable or disable native built-in plugins independently.
- Synchronize settings through a JSON file you control, including one stored in iCloud Drive.
- Check GitHub Releases manually or opt in to a daily check; installation always requires a click
  and the downloaded app must match Spotter's code-signing identity.

## Getting started

1. Open **Settings → General** and record the global shortcut used to summon Spotter.
2. Press it anywhere, type to filter, and press **Return** to run the selected result.
3. Press **Tab** to send a typed prompt to Spotter AI, **Shift-Tab** to send it to ChatGPT on the web,
   **↑/↓** to move, and **Esc** to back out; with no prompt, Tab cycles Apps → AI Chat → Clipboard.
4. Open **Settings → Shortcuts** to bind apps, built-in actions or custom commands globally.

## Permissions and privacy

- **Accessibility** restores focus and pastes into the previous app, reads selected text only when an
  invoked action needs it, and supports window management and text replacement.
- **Automation** is requested only by commands that ask Finder or another macOS app to act.
- **Network access** is off by default. Currency conversion and automatic update checks require
  explicit opt-in. OpenRouter requests require your own API key, which is the consent gate.

Manage macOS grants under **System Settings → Privacy & Security**. Spotter has no account system,
analytics or telemetry.

## Documentation

- **[Development](docs/development.md)** — toolchain, tests, builds, packaging and releases.
- **[Architecture](docs/architecture.md)** — core ownership, windows and concurrency boundaries.
- **[Plugins](docs/plugins.md)** — built-in module contract and lifecycle.
- **[Updates](docs/updates.md)** — channels, consent, release-feed contract and install safety.
- **[Signing](docs/signing.md)** — Developer ID, notarization and Gatekeeper verification.
- **[UI system](docs/ui.md)** — design tokens, surfaces and interaction rules.

The repository tracks the `spotter-plugin` and `spotter-release` project skills for repeatable
plugin and release work — under `.claude/skills/` for Claude Code and mirrored under
`.codex/skills/` for Codex.

## Contributing

> [!IMPORTANT]
> **Open an issue before writing code.** Agree on the bug or feature first; pull requests without an
> agreed issue are closed. Typo and documentation-only fixes are the exception.

Read **[CONTRIBUTING.md](CONTRIBUTING.md)** before starting. It covers the memory budget, visual
change evidence and pull-request requirements. Security reports go through
**[SECURITY.md](SECURITY.md)** rather than the public issue tracker.

## Contributors

Thank you to everyone who has contributed fixes, ideas and testing.

<p align="center">
  <a href="https://github.com/mmmmmmarcus/Spotter/graphs/contributors">
    <img alt="Spotter contributors"
         src="https://contrib.rocks/image?repo=mmmmmmarcus/Spotter&max=28&columns=28">
  </a>
</p>

## Credits

Spotter began as a fork of **[Tinycast](https://github.com/abue-ammar/tinycast)** by
[Abue Ammar](https://github.com/abue-ammar). Its launcher, palette, calculator and clipboard
foundations came from that work; Spotter has since developed independently while retaining the
original copyright and license.

## License

[AGPL-3.0](LICENSE) · Spotter © 2026 Marcus Fei · portions © 2026 Abue Ammar (Tinycast)
