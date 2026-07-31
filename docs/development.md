# Development

How to build, test, package, and release Spotter.

## Requirements

- macOS 26 or later (Liquid Glass).
- Xcode 26 installed — it provides the SwiftUI macro plugin and SDK used to build.

## First-time setup

Create and back up the `Spotter Self-Signed` code-signing identity once:

```sh
./Tools/setup-signing.sh
```

See [signing.md](signing.md) for the backup location and recovery details.

## Build & run

Use the canonical build/install/run entry point:

```sh
./Tools/run-local.sh Debug
./Tools/run-local.sh Release
```

Both commands build into `build/DerivedData`, validate the bundle identifier and signature, stop any
existing Spotter process, atomically replace `/Applications/Spotter.app`, and launch exactly that
copy. A failed build or validation leaves the currently installed app untouched; the previous
installed app is retained at:

```text
~/Library/Caches/com.spotter.local-install/Spotter.previous.app
```

The wrapper selects `/Applications/Xcode.app/Contents/Developer` unless `DEVELOPER_DIR` is already
set. It also updates xcode-build-server's compilation database when that tool is installed.

`Spotter.xcodeproj` is committed and generated from `project.yml` via
[XcodeGen](https://github.com/yonaskolb/XcodeGen) — after changing project settings in `project.yml`,
run `xcodegen generate` and commit the result.

### One app, one identity

Debug and Release deliberately share all identity-defining values:

- installed path: `/Applications/Spotter.app`
- product and executable: `Spotter`
- bundle identifier: `com.spotter.app`
- signing identity: `Spotter Self-Signed`

The configurations still differ in optimization, debug symbols and debugger entitlements, but they
update the same app and state. The runtime refuses to continue when launched from DerivedData; if the
installed copy exists, it redirects there after the accidental process exits. It also activates an
already-running Spotter and terminates the duplicate.

On the first run after upgrading from the former `Spotter Dev.app`, the installer copies only safe
local state: settings, shortcuts, custom commands, favorites, clipboard/calculator history, launcher
ranking and frequent Emoji. Currency-network consent and its downloaded rate cache are explicitly
not migrated. Because the old bundle/signature was different, grant Accessibility once after this
transition; subsequent signed rebuilds retain the same app identity. After a verified installation,
the wrapper removes the obsolete DerivedData `Spotter Dev.app` so an old build cannot be launched
accidentally.

Do not use Xcode's normal Run action: its executable lives in DerivedData and is intentionally
rejected. Use VS Code F5 for an attached debugger, or use Xcode as an editor and run the wrapper from
its terminal.

### Editor (VS Code) code-intelligence

Autocomplete / go-to-definition come from SourceKit-LSP driven by a `buildServer.json`. Generate it
once (it's machine-specific and git-ignored):

```sh
brew install xcode-build-server
xcode-build-server config -project Spotter.xcodeproj -scheme Spotter \
    --build_root "$PWD/build/DerivedData"
```

`--build_root` matches the wrapper's staging build path. In VS Code, **F5** builds and atomically
installs Spotter, then launches `/Applications/Spotter.app/Contents/MacOS/Spotter` under the Swift
debugger. The default build task performs the same update and launches without attaching.

## Tests

There's no XCTest target. Standalone harnesses:

```sh
swift Tools/fuzz-test.swift                                        # launcher fuzzy matcher
swiftc -swift-version 6 Tinycast/Core/LauncherRankingStore.swift Tools/ranking-test.swift \
    -o /tmp/ranking-test && /tmp/ranking-test                      # learned launcher ranking
swiftc Tinycast/Core/Calculator/*.swift Tools/calc-test.swift \
    -o /tmp/calc-test && /tmp/calc-test                           # calculator engine
swiftc -swift-version 6 Tinycast/Core/ClipboardStore.swift Tools/clipboard-test.swift \
    -o /tmp/clipboard-test && /tmp/clipboard-test                 # clipboard store
swiftc -swift-version 6 Tinycast/Core/SearchScopes.swift Tools/scopes-test.swift \
    -o /tmp/scopes-test && /tmp/scopes-test                       # launcher search scopes
swiftc Tinycast/Core/Emoji/EmojiCatalog.swift Tinycast/Core/Emoji/EmojiGridGeometry.swift \
    Tinycast/Core/Emoji/EmojiData.generated.swift Tools/emoji-test.swift \
    -o /tmp/emoji-test && /tmp/emoji-test                         # emoji catalog + geometry
swiftc -swift-version 6 Tinycast/Core/CustomCommand.swift \
    Tinycast/Core/ShellCommandRunner.swift Tools/custom-command-test.swift \
    -o /tmp/custom-command-test && /tmp/custom-command-test        # custom command store + runner
```

`Tools/fuzz-test.swift` holds a **copy** of `FuzzyMatch` from `Tinycast/Core/AppIndex.swift` —
change the scoring in one and mirror it in the other. The calc harness compiles the real engine
sources, which is why `Tinycast/Core/Calculator/` must stay Foundation-only.

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
node Tools/gen-emoji.js            # -> Tinycast/Core/Emoji/EmojiData.generated.swift
node Tools/gen-currencies.js       # -> Tinycast/Core/Calculator/CurrencyData.generated.swift
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
Apple Developer ID), so macOS quarantines a directly-downloaded DMG. Run
`xattr -dr com.apple.quarantine "…/Spotter.app"` once after copying it to Applications.
Full details in [signing.md](signing.md).

## CI releases

`.github/workflows/release.yml` builds and publishes a DMG from GitHub Actions — no local machine
needed. Run it from the **Actions** tab (`Release` → **Run workflow**) and pick:

- **channel** — `beta` or `stable`. Both build `Spotter.app` / `com.spotter.app`, so installing either
  replaces the same app. Beta gets an auto-incrementing `-beta.N` version suffix (`N` = the Actions
  run number) so re-running never collides; stable ships the version as-is.
- **version** — base semver, e.g. `0.2.0`.

It builds on a `macos-26` runner with Xcode 26 and publishes a GitHub Release tagged
`v<full-version>` with a versioned DMG asset (`Spotter-<full-version>.dmg`), marked prerelease
for beta.

This fork does not publish a Homebrew cask. The upstream tap remains owned by Tinycast and must not
be updated by Spotter releases.

## Website

`website/` is the upstream Tinycast Vite + React + TypeScript site. It is intentionally not part of
the Spotter app rename in this fork.

```sh
cd website && npm install && npm run dev     # local preview
```
