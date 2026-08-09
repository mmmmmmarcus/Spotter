# Development

How to build, test, package, and release Spotter.

## Requirements

- macOS 26 or later (Liquid Glass).
- Xcode 26 installed — it provides the SwiftUI macro plugin and SDK used to build.

## First-time setup

Create the `Spotter Self-Signed` code-signing identity once — builds sign with it, which keeps the
macOS Accessibility grant from being forgotten every rebuild. Follow **[signing.md](signing.md) §1**
(a few `openssl`/`security` commands).

## Build & run

Open the project in Xcode and run it:

```sh
open Spotter.xcodeproj    # then press ⌘R
```

Or from the command line:

```sh
xcodebuild -project Spotter.xcodeproj -scheme Spotter -configuration Debug build
```

`xcodebuild` uses whatever `xcode-select` points at; if that's the Command Line Tools rather than
Xcode, prefix with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (the SwiftUI
`@State`/`@FocusState` macros need Xcode's macOS platform).

`Spotter.xcodeproj` is committed and generated from `project.yml` via
[XcodeGen](https://github.com/yonaskolb/XcodeGen) — after changing project settings in `project.yml`,
run `xcodegen generate` and commit the result.

One `project.yml` trap worth knowing: the app icon is the Icon Composer bundle `Spotter/spotter.icon`,
which is a *directory*. It must stay excluded from the recursive `sources` walk and added back as a
single `type: file` entry in the resources phase — without that XcodeGen registers its inner files as
loose resources, `actool` never compiles the icon, and the app ships with the generic placeholder
(no `CFBundleIconName` at all). `ASSETCATALOG_COMPILER_APPICON_NAME: spotter` resolves it.

### Local builds install as the one Spotter.app

There is no separate dev channel. Debug builds produce **`Spotter.app`**, bundle id
`com.spotter.app` — the same identity as the installed app — so a rebuild keeps every persisted
thing, all keyed by bundle id: `~/Library/Preferences/<id>.plist` (settings + hotkey bindings),
`~/Library/Caches/<id>/` (clipboard history, calculator history, exchange rates, frequent emoji),
`~/Library/Application Support/<id>/` (the onboarding marker, Notes data and Quicklinks), the `SMAppService`
login item, and the Accessibility / Input Monitoring (TCC) grants (the stable `Spotter Self-Signed`
identity is what keeps those grants alive across rebuilds).

The install contract (see `AGENTS.md`): build into a staging location (e.g.
`build/LocalInstallDerivedData`), and only after the build and its checks succeed, quit the running
Spotter, replace the exact `/Applications/Spotter.app`, and relaunch it. Never delete the working
installed copy before a new build has succeeded. Since old and new builds share one bundle id, they
cannot run side-by-side — replace, don't fork.

### Editor (VS Code) code-intelligence

Autocomplete / go-to-definition come from SourceKit-LSP driven by a `buildServer.json`. Generate it
once (it's machine-specific and git-ignored):

```sh
brew install xcode-build-server
xcode-build-server config -project Spotter.xcodeproj -scheme Spotter \
    --build_root "$PWD/build/DerivedData"
```

`--build_root` matches the fixed path the VS Code build task / F5 use, so the editor indexes what you
actually build. Do a build once (⌘⇧B or F5) to populate it. In VS Code, **F5** builds and launches the
app; changes always apply (fixed build path — no need to delete `build/`).

## Tests

There's no XCTest target. Standalone harnesses:

```sh
swiftc -swift-version 6 Spotter/Core/SearchRelevance.swift Tools/fuzz-test.swift \
    -o /tmp/fuzz-test && /tmp/fuzz-test                            # search relevance + fuzzy matcher
swiftc -swift-version 6 Spotter/Core/LauncherRankingStore.swift \
    Spotter/Core/SearchRelevance.swift Tools/ranking-test.swift \
    -o /tmp/ranking-test && /tmp/ranking-test                      # learned launcher ranking
swiftc Spotter/Core/Calculator/*.swift \
    Spotter/Plugins/CurrencyConversion/CalcCurrency.swift \
    Spotter/Plugins/CurrencyConversion/CurrencyData.generated.swift Tools/calc-test.swift \
    -o /tmp/calc-test && /tmp/calc-test                           # calculator engine
swiftc -swift-version 6 Spotter/Plugins/Clipboard/ClipboardStore.swift Tools/clipboard-test.swift \
    -o /tmp/clipboard-test && /tmp/clipboard-test                 # clipboard store
swiftc -swift-version 6 Spotter/Core/SearchScopes.swift Tools/scopes-test.swift \
    -o /tmp/scopes-test && /tmp/scopes-test                       # launcher search scopes
swiftc Spotter/Plugins/EmojiSymbols/EmojiCatalog.swift \
    Spotter/Plugins/EmojiSymbols/EmojiGridGeometry.swift \
    Spotter/Plugins/EmojiSymbols/EmojiData.generated.swift Tools/emoji-test.swift \
    -o /tmp/emoji-test && /tmp/emoji-test                         # emoji catalog + geometry
swiftc -swift-version 6 Spotter/Core/CustomCommand.swift \
    Spotter/Core/ShellCommandRunner.swift Tools/custom-command-test.swift \
    -o /tmp/custom-command-test && /tmp/custom-command-test        # custom command store + runner
swiftc -swift-version 6 Spotter/Plugins/Infrastructure/PluginTypes.swift \
    Spotter/Plugins/Commands/SystemCommand.swift Tools/commands-test.swift \
    -o /tmp/commands-test && /tmp/commands-test                    # built-in command catalog + compatibility
swiftc -swift-version 6 Spotter/Plugins/Infrastructure/PluginTypes.swift \
    Spotter/Plugins/WorldClock/WorldClockEngine.swift \
    Spotter/Plugins/WorldClock/WorldClockStore.swift Tools/world-clock-test.swift \
    -o /tmp/world-clock-test && /tmp/world-clock-test              # world-clock engine + store
swiftc -swift-version 6 Spotter/Plugins/KillProcess/KillProcessEngine.swift \
    Tools/kill-process-test.swift -o /tmp/kill-process-test && /tmp/kill-process-test
swiftc -swift-version 6 Spotter/Plugins/ChangeCase/ChangeCaseEngine.swift \
    Tools/change-case-test.swift -o /tmp/change-case-test && /tmp/change-case-test
swiftc -swift-version 6 \
    Spotter/Plugins/SelectionTools/SearchURLBuilder.swift \
    Tools/selection-tools-test.swift \
    -o /tmp/selection-tools-test && /tmp/selection-tools-test
swiftc -swift-version 6 -framework AppKit -framework CoreImage -framework ImageIO -framework Vision \
    Spotter/Plugins/ImageModification/ImageModificationTypes.swift \
    Spotter/Plugins/ImageModification/ImageModificationEngine.swift Tools/image-modification-test.swift \
    -o /tmp/image-modification-test && /tmp/image-modification-test
swiftc -swift-version 6 Spotter/Plugins/Note/NoteEngine.swift Spotter/Plugins/Note/NoteStore.swift \
    Tools/note-test.swift -o /tmp/note-test && /tmp/note-test
swiftc -swift-version 6 Spotter/Plugins/TextReplacement/TextReplacementEngine.swift \
    Spotter/Plugins/TextReplacement/TextReplacementStore.swift Tools/text-replacement-test.swift \
    -o /tmp/text-replacement-test && /tmp/text-replacement-test
swiftc -swift-version 6 Spotter/Core/Backup/SettingsSyncFile.swift \
    Tools/settings-sync-test.swift -o /tmp/settings-sync-test && /tmp/settings-sync-test
swiftc -swift-version 6 Spotter/Core/UpdateFeed.swift Tools/update-test.swift \
    -o /tmp/update-test && /tmp/update-test                       # updater feed + semver
swiftc -swift-version 6 Spotter/Plugins/WindowManagement/WindowCommand.swift \
    Spotter/Plugins/WindowManagement/WindowLayout.swift \
    Spotter/Plugins/WindowManagement/WindowActionMemory.swift Tools/window-command-test.swift \
    -o /tmp/window-command-test && /tmp/window-command-test   # window geometry + cycling
swiftc -swift-version 6 Spotter/Plugins/Mole/MoleTypes.swift Tools/mole-test.swift \
    -o /tmp/mole-test && /tmp/mole-test                           # mole catalog + JSON parsing
swiftc -swift-version 6 Spotter/Plugins/Coffee/CoffeeTypes.swift Tools/coffee-test.swift \
    -o /tmp/coffee-test && /tmp/coffee-test                       # caffeinate args + state
swiftc -swift-version 6 Spotter/Plugins/AIChat/AIChatTypes.swift \
    Spotter/Plugins/AIChat/AIChatSelectionPrompts.swift Tools/ai-chat-test.swift \
    -o /tmp/ai-chat-test && /tmp/ai-chat-test                     # chat transcript windowing
swiftc -swift-version 6 Spotter/Core/Theme.swift Tools/theme-test.swift \
    -o /tmp/theme-test && /tmp/theme-test                         # light/dark token ramp
swiftc -swift-version 6 Spotter/Plugins/Quicklinks/QuicklinkTypes.swift \
    Spotter/Plugins/Quicklinks/QuicklinkStore.swift Tools/quicklink-test.swift \
    -o /tmp/quicklink-test && /tmp/quicklink-test                 # templates + encoding + store
swiftc -swift-version 6 Spotter/Core/HotKey/DoubleTapDetector.swift \
    Spotter/Core/HotKey/DoubleTapModifier.swift Tools/hotkey-test.swift \
    -o /tmp/hotkey-test && /tmp/hotkey-test                       # double-tap recognition
```

`Tools/fuzz-test.swift` compiles the real `Spotter/Core/SearchRelevance.swift`, so that file must
stay Foundation-only and pure — there is no copy of the scorer to keep in sync. The calc harness compiles the real engine
sources, which is why `Spotter/Core/Calculator/` and the parser/data sources in
`Spotter/Plugins/CurrencyConversion/` must stay Foundation-only.

The World Clock harness compiles the real Foundation-only engine and Foundation + Combine store. It
injects a fixed date, calendar, local time zone and isolated `UserDefaults` suite, so daylight-saving,
formatting and saved-city checks never depend on the wall clock or the user's preferences.

Kill Process tests parse a fixed `ps` fixture and never signal a real process. Change Case tests the
real Foundation-only transformer. Selection Tools tests URLComponents encoding without opening a
browser; AI Chat tests transcript windowing plus the selected-text target-language and prompt logic
without sending text over the network.
Image Modification creates and resizes real temporary pixels through
Core Image/ImageIO, then deletes its fixture directory.

The Notes harness compiles the real Foundation-only model, store and Markdown transformer. It validates
derived titles/previews, UTF-16 selections, formatting toggles and atomic persistence against a
temporary archive without opening a window or touching the user's notes file.

The Text Replacement harness compiles the real pure matcher and persisted store. It validates
case-insensitive trigger matching, bounded suffix retention, backspace behavior, conflict rejection
and bundle-scoped preference persistence without installing an event tap or observing real input.

The Settings Sync harness exercises the real coordinated JSON reader/writer against a temporary file
and validates the byte revision guard used to suppress self-triggered file notifications.

The clipboard harness likewise compiles the real `ClipboardStore.swift`, so that file must keep to
Foundation + SQLite3 and depend on no other app source. Each case drives a store rooted in a
throwaway temp directory (`ClipboardStore(directory:)`), so a run can never reach a real history.

The custom-command harness spawns **real `/bin/zsh`** processes. Its shell-environment cases point
`ZDOTDIR` at a throwaway fixture directory (and unset `TERM_PROGRAM`), so a run can never read or write
the developer's own dotfiles. `/etc/zshrc` is still sourced for interactive shells, so the assertions
are relative — the fixture's alias resolves with `-i` and not without — rather than absolute.

## Generated data

Two Swift files are emitted by scripts and must never be hand-edited. Both download their source, so
run them online, then commit the result:

```sh
node Tools/gen-emoji.js            # -> Spotter/Plugins/EmojiSymbols/EmojiData.generated.swift
node Tools/gen-currencies.js       # -> Spotter/Plugins/CurrencyConversion/CurrencyData.generated.swift
```

`gen-currencies.js` joins two sources on the ISO code: **Frankfurter**'s currency list (the same feed
`CurrencyRateStore` fetches rates from, so the table and the rate source can't drift apart) and
**Unicode CLDR**'s `en` currency data, which supplies display names, signs and the singular/plural
noun. It reads the pinned `cldr-json` checkout rather than the host's `Intl`, whose output shifts
with the local ICU version and would make the file unreproducible.

Only unambiguous data is emitted. Anything two currencies claim — `dollars`, `pounds`, `krona` — is
left out and decided by hand in `CalcCurrency.contested`, the one currency table still written by
hand. Re-run the script when a currency is added or retired; nothing breaks in the meantime, since
an unquoted code just reports "no exchange rate".

## Working with a built-in plugin

Plugin-specific code belongs under `Spotter/Plugins/<Name>/`; the shared contract lives in
`Spotter/Plugins/Infrastructure/`. Read [plugins.md](plugins.md) for the registration contract,
performance rules and full checklist.

The repository includes a project-local Codex skill at `.codex/skills/spotter-plugin/`. Invoke
`$spotter-plugin` to create, modify, migrate, debug, or remove a native plugin consistently. The
directory is tracked by git, so cloning the repository on another computer brings the skill with the
source.

## Packaging a DMG

For a local Developer ID-signed and Apple-notarized DMG, first import the Release identity and store
the `spotter-notary` credentials described in [signing.md](signing.md), then run:

```sh
./build-dmg.sh            # -> build/Spotter-<version>.dmg (version from project.yml)
```

It builds a Release `Spotter.app`, verifies its Developer ID signature and Hardened Runtime,
notarizes and staples the app, then signs, notarizes and staples a DMG containing the app and an
`/Applications` symlink. Official per-channel releases (beta/stable) are built by CI — see below and
[`.github/workflows/release.yml`](../.github/workflows/release.yml).

## Signing & Gatekeeper

Debug builds retain the stable `Spotter Self-Signed` identity so contributors can build locally and
keep TCC grants across rebuilds. Release builds use the company Developer ID identity, Hardened
Runtime, a secure timestamp and Apple notarization, so directly downloaded DMGs pass Gatekeeper.
Full credential setup, verification and migration details are in [signing.md](signing.md).

## In-app updates

`Core/UpdateStore.swift` checks the GitHub Releases feed (daily behind an explicit consent toggle;
Check for Updates in Settings → General is itself the user action) and installs in place: download
the release's `Spotter-<version>.zip`, unpack with `ditto`, verify the new bundle satisfies the
running app's **designated requirement**, stage beside `/Applications/Spotter.app`,
remove-and-rename, relaunch. The working install is never deleted before its replacement is fully
staged. The first Developer ID release requires a manual install for users migrating from the old
self-signed identity; subsequent releases share the Developer ID requirement and update normally.
`URLSession` downloads carry no quarantine flag, and the zip contains the same notarized, stapled app
as the DMG. Releases published before the zip asset existed fall back to a "View release" button.
`Core/UpdateFeed.swift` (semver + feed selection) is Foundation-only and pure for
`Tools/update-test.swift`.

## CI releases

`.github/workflows/release.yml` builds and publishes a DMG from GitHub Actions — no local machine
needed. `MARKETING_VERSION` in `project.yml` is the release version's single source of truth. Change
it, run `xcodegen generate`, commit both files, and run the repository's `$spotter-release` skill to
perform the release preflight. Then use the **Actions** tab (`Release` → **Run workflow**) and pick:

- **channel** — `beta` or `stable`. Beta builds `Spotter Beta.app` with its own bundle id so it can
  run beside stable; stable builds the same `Spotter.app` / `com.spotter.app` identity a local
  Debug build produces (there is no separate dev app — see "Local builds install as the one
  Spotter.app" above). Beta gets an auto-incrementing `-beta.N` suffix (`N` = the Actions run
  number) so re-running never collides; stable ships the version as-is.

Stable releases are accepted only from the default branch. The workflow reads and validates the
numeric `x.y.z` version from `project.yml` and stops if its target tag already exists. The website's
offline fallback version is kept in sync by the release preflight.

It builds on a `macos-26` runner with Xcode 26 and publishes a GitHub Release tagged
`v<full-version>` with two assets: the DMG (`Spotter-<full-version>.dmg`) and the zip
(`Spotter-<full-version>.zip`) that the in-app updater downloads, both marked prerelease for beta.
On success it also bumps the matching cask in the tap (below, gated on `HOMEBREW_TAP_TOKEN`) and
posts a Discord announcement (gated on `DISCORD_WEBHOOK_URL`); both steps skip with a warning when
their secret is unset.

Before a release, configure the Developer ID `.p12` and App Store Connect notarization secrets listed
in [signing.md](signing.md). The workflow fails before publishing unless both the app and DMG pass
signature, Hardened Runtime, notarization, stapling and Gatekeeper checks.

### Homebrew tap automation

The release job's final step rewrites the `version` + `sha256` of the channel's cask (`spotter`
or `spotter@beta`) in the
[`homebrew-spotter`](https://github.com/mmmmmmarcus/homebrew-spotter) tap and pushes. It needs a
`HOMEBREW_TAP_TOKEN` repo secret — a fine-grained PAT with **Contents: read/write** on the tap
repo. Without the secret the step logs a warning and skips (the release still publishes).

## Website

`.github/workflows/website.yml` builds `website/` (Vite + React + TS) and deploys it to GitHub
Pages at `https://mmmmmmarcus.github.io/Spotter/` on every push to `main` that touches
`website/`. Enable it once via **Settings → Pages → Source = GitHub Actions**.

```sh
cd website && npm install && npm run dev     # local preview
```
