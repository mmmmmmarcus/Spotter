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

### Local builds install as the one Spotter.app

There is no separate dev channel. Debug builds produce **`Spotter.app`**, bundle id
`com.spotter.app` — the same identity as the installed app — so a rebuild keeps every persisted
thing, all keyed by bundle id: `~/Library/Preferences/<id>.plist` (settings + hotkey bindings),
`~/Library/Caches/<id>/` (clipboard history, calculator history, exchange rates, frequent emoji),
`~/Library/Application Support/<id>/` (the onboarding marker and Notes data), the `SMAppService`
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
    Spotter/Plugins/WorldClock/WorldClockEngine.swift \
    Spotter/Plugins/WorldClock/WorldClockStore.swift Tools/world-clock-test.swift \
    -o /tmp/world-clock-test && /tmp/world-clock-test              # world-clock engine + store
swiftc -swift-version 6 Spotter/Plugins/KillProcess/KillProcessEngine.swift \
    Tools/kill-process-test.swift -o /tmp/kill-process-test && /tmp/kill-process-test
swiftc -swift-version 6 Spotter/Plugins/ChangeCase/ChangeCaseEngine.swift \
    Tools/change-case-test.swift -o /tmp/change-case-test && /tmp/change-case-test
swiftc -swift-version 6 \
    Spotter/Plugins/SelectionTools/SelectionToolsTypes.swift \
    Spotter/Plugins/SelectionTools/SearchURLBuilder.swift \
    Spotter/Plugins/SelectionTools/SelectionLLM.swift Tools/selection-tools-test.swift \
    -o /tmp/selection-tools-test && /tmp/selection-tools-test
swiftc -swift-version 6 -framework AppKit -framework CoreImage -framework ImageIO -framework Vision \
    Spotter/Plugins/ImageModification/ImageModificationTypes.swift \
    Spotter/Plugins/ImageModification/ImageModificationEngine.swift Tools/image-modification-test.swift \
    -o /tmp/image-modification-test && /tmp/image-modification-test
swiftc -swift-version 6 Spotter/Plugins/QuickTime/QuickTimeRunner.swift \
    Tools/quicktime-test.swift -o /tmp/quicktime-test && /tmp/quicktime-test
swiftc -swift-version 6 Spotter/Plugins/Note/NoteEngine.swift Spotter/Plugins/Note/NoteStore.swift \
    Tools/note-test.swift -o /tmp/note-test && /tmp/note-test
swiftc -swift-version 6 Spotter/Plugins/TextReplacement/TextReplacementEngine.swift \
    Spotter/Plugins/TextReplacement/TextReplacementStore.swift Tools/text-replacement-test.swift \
    -o /tmp/text-replacement-test && /tmp/text-replacement-test
swiftc -swift-version 6 Spotter/Core/Backup/SettingsSyncFile.swift \
    Tools/settings-sync-test.swift -o /tmp/settings-sync-test && /tmp/settings-sync-test
swiftc -swift-version 6 Spotter/Core/UpdateFeed.swift Tools/update-test.swift \
    -o /tmp/update-test && /tmp/update-test                       # updater feed + semver
```

`Tools/fuzz-test.swift` compiles the real `Spotter/Core/SearchRelevance.swift`, so that file must
stay Foundation-only and pure — there is no copy of the scorer to keep in sync. The calc harness compiles the real engine
sources, which is why `Spotter/Core/Calculator/` and the parser/data sources in
`Spotter/Plugins/CurrencyConversion/` must stay Foundation-only.

The World Clock harness compiles the real Foundation-only engine and Foundation + Combine store. It
injects a fixed date, calendar, local time zone and isolated `UserDefaults` suite, so daylight-saving,
formatting and saved-city checks never depend on the wall clock or the user's preferences.

Kill Process tests parse a fixed `ps` fixture and never signal a real process. Change Case tests the
real Foundation-only transformer. Selection Tools tests URLComponents encoding, request
generation/cancellation and the pure LLM prompt/response logic without opening a browser or sending
text over the network.
Image Modification creates and resizes real temporary pixels through
Core Image/ImageIO, then deletes its fixture directory. QuickTime tests only the generated AppleScript
strings and never opens QuickTime.

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

For a local signed DMG:

```sh
./build-dmg.sh            # -> build/Spotter-<version>.dmg (version from project.yml)
./build-dmg.sh 0.5.7      # -> build/Spotter-0.5.7.dmg
```

It builds a Release `Spotter.app` signed with `Spotter Self-Signed` and packs it (with an
`/Applications` symlink). Official per-channel releases (beta/stable) are built by CI — see
below and [`.github/workflows/release.yml`](../.github/workflows/release.yml).

## Signing & Gatekeeper

Both local builds and CI releases sign with the same stable `Spotter Self-Signed` identity (not an
Apple Developer ID), so macOS quarantines a directly-downloaded DMG — the Homebrew cask strips that
automatically, and direct downloaders run `xattr -dr com.apple.quarantine "…/Spotter.app"` once.
Full details in [signing.md](signing.md).

## In-app updates

`Core/UpdateStore.swift` checks the GitHub Releases feed (daily behind an explicit consent toggle;
Check for Updates in Settings → General is itself the user action) and installs in place: download
the release's `Spotter-<version>.zip`, unpack with `ditto`, verify the new bundle satisfies the
running app's **designated requirement** (the `Spotter Self-Signed` certificate — a hijacked asset
fails here), stage beside `/Applications/Spotter.app`, remove-and-rename, relaunch. The working
install is never deleted before its replacement is fully staged. `URLSession` downloads carry no
quarantine flag, so an updated app launches without a Gatekeeper prompt. Releases published before
the zip asset existed fall back to a "View release" button. `Core/UpdateFeed.swift` (semver +
feed selection) is Foundation-only and pure for `Tools/update-test.swift`.

## CI releases

`.github/workflows/release.yml` builds and publishes a DMG from GitHub Actions — no local machine
needed. Run it from the **Actions** tab (`Release` → **Run workflow**) and pick:

- **channel** — `beta` or `stable`. Each builds a distinct app
  (`Spotter Beta.app` / `Spotter.app`) with its own bundle id, alongside the local
  `Spotter Dev.app` (above).
  Beta gets an auto-incrementing `-beta.N` suffix (`N` = the Actions run number)
  so re-running never collides; stable ships the version as-is.
- **version** — base semver, e.g. `0.2.0`.

It builds on a `macos-26` runner with Xcode 26 and publishes a GitHub Release tagged
`v<full-version>` with a versioned DMG asset (`Spotter-<full-version>.dmg`), marked prerelease
for beta. On success it also bumps the matching cask in the tap (below).

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
