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

### The dev channel

Debug builds are a separate channel: **`Spotter Dev.app`**, bundle id `com.spotter.app.dev`. Since
every persisted thing is keyed by bundle
id — `~/Library/Preferences/<id>.plist` (settings + hotkey bindings),
`~/Library/Caches/<id>/` (clipboard history, calculator history, exchange rates, frequent emoji),
`~/Library/Application Support/<id>/` (the onboarding marker), the `SMAppService` login item, and the
Accessibility / Input Monitoring (TCC) grants — a build you run locally can't read or clobber the
installed app's state, and both can run side-by-side.

Consequences worth knowing:

- The dev build asks for Accessibility on its own the first time, and starts with **no** hotkeys bound
  and onboarding unseen. Grant + bind once; it persists across rebuilds (the fixed build path and the
  `Spotter Self-Signed` identity keep the TCC grant alive).
- Don't bind the same global hotkey in both — whichever registered first wins.
- The Hyper Key's Caps Lock remap is `hidutil` state, which is **system-wide, not per-bundle**:
  quitting one build clears the remap for the other, which then needs a rebind (or relaunch) to
  restore it.

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
swift Tools/fuzz-test.swift                                        # launcher fuzzy matcher
swiftc -swift-version 6 Spotter/Core/LauncherRankingStore.swift Tools/ranking-test.swift \
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
    Spotter/Plugins/WorldClock/WorldClockEngine.swift Tools/world-clock-test.swift \
    -o /tmp/world-clock-test && /tmp/world-clock-test              # world-clock plugin engine
swiftc -swift-version 6 Spotter/Plugins/KillProcess/KillProcessEngine.swift \
    Tools/kill-process-test.swift -o /tmp/kill-process-test && /tmp/kill-process-test
swiftc -swift-version 6 Spotter/Plugins/ChangeCase/ChangeCaseEngine.swift \
    Tools/change-case-test.swift -o /tmp/change-case-test && /tmp/change-case-test
swiftc -swift-version 6 -framework AppKit -framework CoreImage -framework ImageIO -framework Vision \
    Spotter/Plugins/ImageModification/ImageModificationTypes.swift \
    Spotter/Plugins/ImageModification/ImageModificationEngine.swift Tools/image-modification-test.swift \
    -o /tmp/image-modification-test && /tmp/image-modification-test
swiftc -swift-version 6 Spotter/Plugins/QuickTime/QuickTimeRunner.swift \
    Tools/quicktime-test.swift -o /tmp/quicktime-test && /tmp/quicktime-test
```

`Tools/fuzz-test.swift` holds a **copy** of `FuzzyMatch` from `Spotter/Core/AppIndex.swift` —
change the scoring in one and mirror it in the other. The calc harness compiles the real engine
sources, which is why `Spotter/Core/Calculator/` and the parser/data sources in
`Spotter/Plugins/CurrencyConversion/` must stay Foundation-only.

The World Clock harness likewise compiles the real Foundation-only engine. It injects a fixed date,
calendar and locale, so daylight-saving and formatting checks never depend on the wall clock.

Kill Process tests parse a fixed `ps` fixture and never signal a real process. Change Case tests the
real Foundation-only transformer. Image Modification creates and resizes real temporary pixels through
Core Image/ImageIO, then deletes its fixture directory. QuickTime tests only the generated AppleScript
strings and never opens QuickTime.

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

## Adding a built-in plugin

Plugin-specific code belongs under `Spotter/Plugins/<Name>/`; the shared contract lives in
`Spotter/Plugins/Infrastructure/`. Read [plugins.md](plugins.md) for the registration contract,
performance rules and full checklist.

The repository includes a project-local Codex skill at `.codex/skills/spotter-new-plugin/`. Invoke
`$spotter-new-plugin` to scaffold and integrate a native plugin consistently. The directory is tracked
by git, so cloning the repository on another computer brings the skill with the source.

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
