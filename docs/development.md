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

The ordinary self-signed Debug channel deliberately omits the restricted CloudKit entitlement, so
Notes' iCloud toggle reports unavailable locally. To exercise the Development CloudKit environment,
use `scripts/install-cloud-dev.sh`; it discovers a matching development profile, builds the same
`Spotter.app` / `com.spotter.app1` dev channel with Apple Development signing, verifies its embedded
profile and entitlements, then safely installs and launches it. The Apple Development signature has a
different designated requirement, so Accessibility and Input Monitoring may need to be granted again.
Release builds instead use the Production environment and their channel-specific Developer ID profile.
Pure Note merge/tombstone coverage remains available without an iCloud account.

One `project.yml` trap worth knowing: the app icon is the Icon Composer bundle `Spotter/spotter.icon`,
which is a *directory*. It must stay excluded from the recursive `sources` walk and added back as a
single `type: file` entry in the resources phase — without that XcodeGen registers its inner files as
loose resources, `actool` never compiles the icon, and the app ships with the generic placeholder
(no `CFBundleIconName` at all). `ASSETCATALOG_COMPILER_APPICON_NAME: spotter` resolves it.

### Local dev builds install as the one Spotter.app

Debug builds are the **dev** channel and report the release base version with a `-dev` suffix (for
example `1.4.9-dev`). Public **stable** builds use the same base version without the suffix. Dev is
never published. Both builds produce **`Spotter.app`**, bundle id `com.spotter.app1`, so a rebuild keeps every persisted
thing, all keyed by bundle id: `~/Library/Preferences/<id>.plist` (settings + hotkey bindings),
`~/Library/Caches/<id>/` (clipboard history, calculator history, exchange rates, frequent emoji),
`~/Library/Application Support/<id>/` (the onboarding marker, Notes data and Quicklinks), the `SMAppService`
login item, and the Accessibility / Input Monitoring (TCC) grants (the stable `Spotter Self-Signed`
identity is what keeps those grants alive across rebuilds).

The first build with this identity migrates from the former `com.spotter.app` domain before
`AppCore` initializes. It copies preferences, Application Support content and caches without deleting
the originals; new-identity values win on collisions. The onboarding marker is deliberately excluded
so Accessibility and Input Monitoring are requested for the new designated requirement. This is a
one-time manual DMG transition; subsequent builds retain `com.spotter.app1` and update normally.

The install contract (see `AGENTS.md`): build into a staging location (e.g.
`build/LocalInstallDerivedData`), and only after the build and its checks succeed, quit the running
Spotter, replace the exact `/Applications/Spotter.app`, and relaunch it. Never delete the working
installed copy before a new build has succeeded. Since old and new builds share one bundle id, they
cannot run side-by-side — replace, don't fork.

For an installed CloudKit-capable dev build, run:

```sh
scripts/install-cloud-dev.sh
```

It requires an unexpired Apple Development identity and a development provisioning profile for team
`SM96W8VVK9`, App ID `com.spotter.app1`, push notifications and `iCloud.com.spotter.app`. It never
changes the ordinary Debug configuration or publishes its Development-environment data.

### Editor (VS Code) code-intelligence

Autocomplete / go-to-definition come from SourceKit-LSP driven by a `buildServer.json`. Generate it
once (it's machine-specific and git-ignored) after installing `xcode-build-server` by your preferred
method:

```sh
xcode-build-server config -project Spotter.xcodeproj -scheme Spotter \
    --build_root "$PWD/build/DerivedData"
```

`--build_root` matches the fixed path the VS Code build task / F5 use, so the editor indexes what you
actually build. Do a build once (⌘⇧B or F5) to populate it. In VS Code, **F5** builds and launches the
app; changes always apply (fixed build path — no need to delete `build/`).

## Tests

There's no XCTest target. Run the complete suite with bounded parallelism:

```sh
scripts/test-all.sh --jobs 4
```

Release preparation runs the same full suite and validates the website only when it has changes
beyond the synchronized version fallback:

```sh
scripts/release.sh prepare <x.y.z>
```

Individual standalone harnesses:

```sh
swiftc -swift-version 6 Spotter/Core/SearchRelevance.swift Tools/fuzz-test.swift \
    -o /tmp/fuzz-test && /tmp/fuzz-test                            # search relevance + fuzzy matcher
swiftc -swift-version 6 Spotter/Core/AppVersion.swift Tools/app-version-test.swift \
    -o /tmp/app-version-test && /tmp/app-version-test              # launcher/About version labels
swiftc -swift-version 6 Spotter/Core/LauncherRankingStore.swift \
    Spotter/Core/SearchRelevance.swift Tools/ranking-test.swift \
    -o /tmp/ranking-test && /tmp/ranking-test                      # learned launcher ranking
swiftc -swift-version 6 Spotter/Core/LauncherFallback.swift \
    Spotter/Core/TerminalCommandRunner.swift Tools/launcher-fallback-test.swift \
    -o /tmp/launcher-fallback-test && /tmp/launcher-fallback-test  # query destinations + safe Terminal argv
swiftc Spotter/Core/Calculator/*.swift \
    Spotter/Plugins/CurrencyConversion/CalcCurrency.swift \
    Spotter/Plugins/CurrencyConversion/CurrencyData.generated.swift Tools/calc-test.swift \
    -o /tmp/calc-test && /tmp/calc-test                           # calculator engine
swiftc -swift-version 6 Spotter/Plugins/Clipboard/ClipboardStore.swift \
    Spotter/Plugins/Clipboard/ClipboardFilter.swift \
    Spotter/Plugins/Screenshot/ScreenshotFileName.swift Tools/clipboard-test.swift \
    -o /tmp/clipboard-test && /tmp/clipboard-test                 # clipboard store
swiftc -swift-version 6 Spotter/Core/SearchScopes.swift Tools/scopes-test.swift \
    -o /tmp/scopes-test && /tmp/scopes-test                       # launcher search scopes
swiftc -swift-version 6 Spotter/Core/SearchRelevance.swift \
    Spotter/Plugins/FileSearch/FileSearchTypes.swift Tools/file-search-test.swift \
    -o /tmp/file-search-test && /tmp/file-search-test             # file search policy
swiftc Spotter/Plugins/EmojiSymbols/EmojiCatalog.swift \
    Spotter/Plugins/EmojiSymbols/EmojiGridGeometry.swift \
    Spotter/Plugins/EmojiSymbols/EmojiData.generated.swift Tools/emoji-test.swift \
    -o /tmp/emoji-test && /tmp/emoji-test                         # emoji catalog + geometry
swiftc -swift-version 6 Spotter/Core/CustomCommand.swift \
    Spotter/Core/ShellCommandRunner.swift Tools/custom-command-test.swift \
    -o /tmp/custom-command-test && /tmp/custom-command-test        # custom command store + runner
swiftc -swift-version 6 Spotter/Core/CommandID.swift \
    Spotter/Plugins/Infrastructure/PluginTypes.swift \
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
    Spotter/Plugins/Infrastructure/PluginTypes.swift \
    Spotter/Plugins/SelectionTools/SelectionToolsTypes.swift \
    Spotter/Plugins/SelectionTools/SearchURLBuilder.swift \
    Spotter/Plugins/SelectionTools/SelectionToolsResults.swift \
    Tools/selection-tools-test.swift \
    -o /tmp/selection-tools-test && /tmp/selection-tools-test
swiftc -swift-version 6 -framework AppKit -framework CoreImage -framework ImageIO -framework Vision \
    Spotter/Plugins/ImageModification/ImageModificationTypes.swift \
    Spotter/Plugins/ImageModification/ImageModificationEngine.swift Tools/image-modification-test.swift \
    -o /tmp/image-modification-test && /tmp/image-modification-test
swiftc -swift-version 6 Spotter/Plugins/Note/NoteEngine.swift Spotter/Plugins/Note/NoteStore.swift \
    Spotter/Plugins/Note/NoteSyncDocument.swift \
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
swiftc -swift-version 6 Spotter/Core/BackgroundTaskStore.swift Tools/background-task-test.swift \
    -o /tmp/background-task-test && /tmp/background-task-test     # task lifetime + dismissal
swiftc -swift-version 6 Spotter/Plugins/Mole/MoleTypes.swift \
    Spotter/Plugins/Mole/MoleProcessRunner.swift Tools/mole-test.swift \
    -o /tmp/mole-test && /tmp/mole-test                           # mole catalog + JSON parsing
swiftc -swift-version 6 Spotter/Plugins/OnePassword/OnePasswordTypes.swift \
    Tools/onepassword-test.swift \
    -o /tmp/onepassword-test && /tmp/onepassword-test             # 1password parsing + argv + actions
swiftc -swift-version 6 Spotter/Plugins/Coffee/CoffeeTypes.swift Tools/coffee-test.swift \
    -o /tmp/coffee-test && /tmp/coffee-test                       # caffeinate args + state
swiftc -swift-version 6 Spotter/Plugins/AIChat/AIChatTypes.swift \
    Spotter/Plugins/AIChat/AIChatMarkdown.swift \
    Spotter/Plugins/AIChat/AIChatSelectionPrompts.swift \
    Spotter/Core/OpenRouterModelCatalog.swift Tools/ai-chat-test.swift \
    -o /tmp/ai-chat-test && /tmp/ai-chat-test                     # transcript + Markdown blocks + ChatGPT web URL + model catalog
swiftc -swift-version 6 Spotter/Plugins/DashboardWidgets/DashboardWidgetsEngine.swift \
    Spotter/Plugins/DashboardWidgets/DashboardWeatherEngine.swift \
    Spotter/Plugins/DashboardWidgets/DashboardMusicEngine.swift \
    Spotter/Plugins/DashboardWidgets/DashboardDeviceBatteryEngine.swift \
    Spotter/Plugins/DashboardWidgets/DashboardFileInfoEngine.swift \
    Tools/dashboard-widgets-test.swift \
    -o /tmp/dashboard-widgets-test && /tmp/dashboard-widgets-test # arrangement, clock hands, weather codes, music parsing, battery scans + merge, Finder selection
swiftc -swift-version 6 Spotter/Plugins/Uptime/UptimeEngine.swift Tools/uptime-test.swift \
    -o /tmp/uptime-test && /tmp/uptime-test                       # session rollover + input tallies
swiftc -swift-version 6 Spotter/Core/Theme.swift Spotter/Plugins/Note/NoteEngine.swift \
    Tools/theme-test.swift \
    -o /tmp/theme-test && /tmp/theme-test                         # light/dark token ramp
swiftc -swift-version 6 Spotter/Plugins/Quicklinks/QuicklinkTypes.swift \
    Spotter/Plugins/Quicklinks/QuicklinkStore.swift Tools/quicklink-test.swift \
    -o /tmp/quicklink-test && /tmp/quicklink-test                 # templates + encoding + store
swiftc -swift-version 6 Spotter/Core/HotKey/DoubleTapDetector.swift \
    Spotter/Core/HotKey/DoubleTapModifier.swift Tools/hotkey-test.swift \
    -o /tmp/hotkey-test && /tmp/hotkey-test                       # double-tap recognition
swiftc -swift-version 6 Spotter/Core/SearchRelevance.swift \
    Spotter/Core/PaletteMenuTypeahead.swift Tools/menu-typeahead-test.swift \
    -o /tmp/menu-typeahead-test && /tmp/menu-typeahead-test       # Actions menu type-ahead
swiftc -swift-version 6 -framework CoreGraphics -framework CoreText -framework ImageIO \
    -framework UniformTypeIdentifiers Spotter/Plugins/Screenshot/ScreenshotWindowPicker.swift \
    Spotter/Plugins/Screenshot/ScreenshotGeometry.swift \
    Spotter/Plugins/Screenshot/ScreenshotImageProcessor.swift \
    Spotter/Plugins/Screenshot/ScreenshotAnnotation.swift \
    Spotter/Plugins/Screenshot/ScreenshotTextLayout.swift \
    Spotter/Plugins/Screenshot/ScreenshotFileName.swift Tools/screenshot-test.swift \
    -o /tmp/screenshot-test && /tmp/screenshot-test             # cursor swap + geometry + annotation pixels
```

`Tools/fuzz-test.swift` compiles the real `Spotter/Core/SearchRelevance.swift`, so that file must
stay Foundation-only and pure — there is no copy of the scorer to keep in sync. The calc harness compiles the real engine
sources, which is why `Spotter/Core/Calculator/` and the parser/data sources in
`Spotter/Plugins/CurrencyConversion/` must stay Foundation-only.

The App Version harness pins the channel-aware Launcher label, full About label and missing-value
fallbacks without depending on the version of the test executable.

The World Clock harness compiles the real Foundation-only engine and Foundation + Combine store. It
injects a fixed date, calendar, local time zone and isolated `UserDefaults` suite, so daylight-saving,
formatting and saved-city checks never depend on the wall clock or the user's preferences.

The Background Tasks harness checks newest-first ordering, progress clamping, terminal-state
retention, sync encoding, relaunch interruption and the invariant that a running task cannot be dismissed.

The Mole harness pins its command catalog, parsers, duplicate-app and Homebrew-cask safety gates,
post-confirmation uninstall input, process exit-status/stderr handling, cancellation and streaming.
It uses shell fixtures for the runner and never executes Mole or changes user data.

The Launcher Fallbacks harness pins the four query destinations and verifies that arbitrary shell
text reaches Terminal as one exact `osascript` argument rather than interpolated AppleScript source.

The Screenshot harness pins drag normalization, display clamping, minimum region size, AppKit to
ScreenCaptureKit display-local conversion, the exact four-pixel radius, transparent TIFF corners
and the square-corner opt-out without requesting Screen Recording access or reading screen pixels.

The Widgets harness compiles the real Foundation-only engine. It pins widget preference
fallbacks, calendar-account/all-day filtering, time-zone resolution and analog-clock hand geometry
without touching EventKit or the user's files.

Kill Process tests parse a fixed `ps` fixture and never signal a real process. Change Case tests the
real Foundation-only transformer. Selection Tools tests URLComponents encoding without opening a
browser; AI Chat tests transcript windowing, its ChatGPT web-query URL, and the selected-text
target-language and prompt logic without sending text over the network or opening a browser.
Image Modification creates and resizes real temporary pixels through
Core Image/ImageIO, then deletes its fixture directory.

The Notes harness compiles the real Foundation-only model, store, merge rules and Markdown transformer.
It validates derived titles/previews, UTF-16 selections, formatting toggles and replacements,
H1/H2/H3/Text conversion, adjacent-note navigation, ASCII and Chinese-bracket checklist input,
empty-Note deletion tombstones, window-transparency persistence,
deterministic CloudKit conflict resolution and atomic persistence against a temporary archive without
opening a window, contacting iCloud or touching the user's notes file.

The Text Replacement harness compiles the real pure matcher and persisted store. It validates
case-insensitive trigger matching, bounded suffix retention, backspace behavior, conflict rejection
and bundle-scoped preference persistence without installing an event tap or observing real input.

The Settings Sync harness exercises the real coordinated JSON reader/writer against a temporary file
and validates the byte revision guard used to suppress self-triggered file notifications.

The clipboard harness likewise compiles the real `ClipboardStore.swift` and `ClipboardFilter.swift`,
including portable text/image sync snapshots and the type filter's derived link/email classifier, so
both files must keep to Foundation (plus SQLite3) and depend on no other app source. Each case drives a store rooted in a
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

The repository includes a project-local skill at `.claude/skills/spotter-plugin/` (Claude Code;
invoke `/spotter-plugin`), mirrored at `.codex/skills/spotter-plugin/` (Codex; invoke
`$spotter-plugin`), to create, modify, migrate, debug, or remove a native plugin consistently. Both
directories are tracked by git, so cloning the repository on another computer brings the skill with
the source.

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

`Core/UpdateStore.swift` checks GitHub Releases and installs a verified update in place. Stable and
beta builds stay on their own channels, automatic checks require explicit consent and re-check it
after the network request, and installation always requires a click. The complete feed, trust,
replacement and failure contracts are documented in [updates.md](updates.md).

## CI releases

`.github/workflows/release.yml` builds and publishes a DMG from GitHub Actions — no local machine
needed. `MARKETING_VERSION` in `project.yml` is the release version's single source of truth. Change
it, run `xcodegen generate`, commit both files, and run the repository's `spotter-release` skill
(`/spotter-release` in Claude Code, `$spotter-release` in Codex) to perform the release preflight.
Its checked-in entry point is:

```sh
scripts/release-preflight.sh --expected <x.y.z>
```

Then use the **Actions** tab (`Release` → **Run workflow**) and pick:

- **channel** — `beta` or `stable`. Beta builds `Spotter Beta.app` with its own bundle id so it can
  run beside stable; stable builds the same `Spotter.app` / `com.spotter.app1` identity a local
  Debug build produces (there is no separate dev app — see "Local builds install as the one
  Spotter.app" above). Beta gets an auto-incrementing `-beta.N` suffix (`N` = the Actions run
  number) so re-running never collides; stable ships the version as-is.

Stable releases are accepted only from the default branch. The workflow reads and validates the
numeric `x.y.z` version from `project.yml` and stops if its target tag already exists. The website's
offline fallback version is kept in sync by the release preflight.

The tracked release orchestrator performs context inspection, publication preflight, safe push,
stable dispatch, job-level waiting and independent downloadable-asset auditing:

```sh
scripts/release.sh context
scripts/release.sh publish <x.y.z>
scripts/release.sh audit <x.y.z>    # read-only audit of an existing stable release
```

It builds on a `macos-26` runner with Xcode 26 and publishes a GitHub Release tagged
`v<full-version>` with two assets: the DMG (`Spotter-<full-version>.dmg`) and the zip
(`Spotter-<full-version>.zip`) that the in-app updater downloads, both marked prerelease for beta.
The GitHub Release is the sole public distribution channel; the workflow does not mutate another
repository or post release announcements to an external service.

Before a release, configure the Developer ID `.p12` and App Store Connect notarization secrets listed
in [signing.md](signing.md). The workflow fails before publishing unless both the app and DMG pass
signature, Hardened Runtime, notarization, stapling and Gatekeeper checks.

## Website

`.github/workflows/website.yml` builds `website/` (Vite + React + TS) and deploys it to GitHub
Pages at `https://mmmmmmarcus.github.io/Spotter/` on every push to `main` that touches
`website/`. Enable it once via **Settings → Pages → Source = GitHub Actions**.

```sh
cd website && npm install && npm run dev     # local preview
```
