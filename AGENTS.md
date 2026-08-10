## Project

Spotter is a native macOS menu-bar launcher (a minimal Raycast): fuzzy app launcher, global +
per-app hotkeys, a text/image clipboard history, an inline calculator, and an emoji picker. SwiftUI +
AppKit, runs as an accessory (no Dock icon, `LSUIElement`). Targets **macOS 26+** (Liquid Glass) and
builds with the **Xcode 26** toolchain.

- **Build:** XcodeGen owns the project — `Spotter.xcodeproj` is committed but generated from
  `project.yml`. After editing `project.yml`, run `xcodegen generate` and commit. There is **no**
  `Package.swift` / SwiftPM. Full build/test/sign/release steps: [`docs/development.md`](docs/development.md),
  [`docs/signing.md`](docs/signing.md).
- **Local build destination:** Every non-release build must finish as
  `/Applications/Spotter.app`. Do not maintain or launch a separate `Spotter Dev.app`, and do not
  distinguish a routine Debug build from the normal locally installed app. `project.yml` already
  builds Debug as `Spotter.app` / `com.spotter.app`; keep it that way.
- **Replace and relaunch after every successful build.** Build into a staging/DerivedData location
  first. Only after the new app has built and passed its required checks, quit the running Spotter,
  delete the exact old `/Applications/Spotter.app`, copy the new app into `/Applications`, and launch
  the newly installed copy automatically. Never delete the working installed copy before a new build
  succeeds, and never target anything broader than the exact Spotter app bundle.
- **Release is the only exception.** When the user explicitly requests a Release build, follow the
  documented release/signing/DMG workflow and preserve its requested channel, product name, bundle
  identifier, output location, and launch behavior.
- Anything newly persisted must stay keyed by `Bundle.main.bundleIdentifier`.
- **Tests:** no XCTest target — standalone `swiftc` harnesses in `Tools/` (see Critical Invariants and
  `docs/development.md`).

## Project Philosophy

- Production-quality, as if written by a senior macOS engineer.
- Prefer simple, maintainable solutions over clever ones; preserve existing behavior unless the task
  changes it.
- Keep SwiftUI views declarative and lightweight; business logic lives in models / managers.
- Respect Swift 6 actor isolation; keep expensive work off the main actor.
- Remove dead code rather than adding compatibility layers. Leave the codebase cleaner than you found
  it.
- **Comments are single-line** — no stacked / multi-line blocks. Only comment the non-obvious (a
  _why_, a gotcha, a load-bearing invariant); never restate the code.

## Architecture

Full detail: [`docs/architecture.md`](docs/architecture.md).

- **Single-owner core.** `AppCore.shared` (`Core/AppCore.swift`) is a `@MainActor` singleton owning
  every long-lived manager and the window controllers.
  `AppDelegate.applicationDidFinishLaunching` calls `AppCore.shared.start()` and nothing else — that
  is the one wiring point. Palette / paste / launch actions are methods on `AppCore` that views call.
- **Mostly AppKit windows.** `SpotterApp` (`@main`) declares only a `MenuBarExtra` scene. The command
  palette is a borderless floating `NSPanel` hosting SwiftUI; Settings/About are plain `NSWindow`s via
  `AuxWindowController`. SwiftUI `Settings` / `Window` scenes are deliberately avoided (unreliable for
  accessory apps).
- **Subsystems:** [palette](docs/palette.md) · [launcher & fuzzy match](docs/launcher.md) ·
  [calculator](docs/calculator.md) · [clipboard](docs/clipboard.md) · [emoji](docs/emoji.md) ·
  [plugins](docs/plugins.md) · [hotkeys](docs/hotkeys.md) · [UI & design system](docs/ui.md).

## Critical Invariants

Never break these without an explicit task to do so.

- **`AppCore` is the sole owner.** New long-lived state belongs on `AppCore`, wired in `start()`; don't
  create competing singletons or wire managers elsewhere. The one deliberate exception is
  `Core/AppLog.swift` (`AppLog.shared`), the diagnostics sink — infrastructure like
  `NotificationCenter.default`, reachable from any subsystem and isolation; feature errors should
  log through it.
- **`PaletteWindowController` solely owns the palette frame.** The hosting view sets
  `sizingOptions = []` so SwiftUI never drives the window size — otherwise the top edge drifts on the
  compact↔expanded swap.
- **The app follows the system appearance, and appearance lives only in `Core/Theme.swift`.** Every
  color token is built by `Theme.Colors.adaptive(dark:light:)`; views never branch on `colorScheme`
  and never hardcode a literal white/black (use the semantic `NSColor`s in AppKit code). The dark
  stops are the original design and must not drift — `Tools/theme-test.swift` pins both stops of
  every token. Rasterized art is the one exception: an `IconCache` symbol tile bakes its colors, so
  the appearance is part of its cache key and the view re-decodes on a flip.
- **The flat `selection` index must match the visible row order exactly**, including the inline
  calculator card at index 0 when present. Selection is the single source of truth for highlight /
  activation.
- **While a footer menu is open the palette search field never resigns first responder** — input is
  frozen instead (resigning shifts the text a point or two). See [palette.md](docs/palette.md).
- **Focus restoration is load-bearing.** Paste targets the recorded `previousApp` and requires the
  Accessibility permission (`Permissions.ensureAccessibility()`). See [palette.md](docs/palette.md).
- **`Core/Calculator/` (incl. `CalcDateTime`) must stay Foundation-only *and pure*** — no AppKit /
  SwiftUI imports, no clock or network reads. The Currency Conversion parser and generated table in
  `Plugins/CurrencyConversion/` share that boundary. `Tools/calc-test.swift` compiles the real
  sources. Both externally-sourced inputs are injected: the clock via `now`/`calendar`, the FX table
  via `rates` (`CurrencyRateStore` owns the fetch). Likewise the catalog and geometry sources in
  `Plugins/EmojiSymbols/` stay AppKit/SwiftUI-free for `Tools/emoji-test.swift`,
  `Plugins/WorldClock/WorldClockEngine.swift` stays Foundation-only with an injected clock/calendar/
  local time zone while `Plugins/WorldClock/WorldClockStore.swift` stays Foundation + Combine,
  `Plugins/KillProcess/KillProcessEngine.swift` and `Plugins/ChangeCase/ChangeCaseEngine.swift` stay
  Foundation-only and pure, `Plugins/SelectionTools/SelectionToolsTypes.swift` and
  `Plugins/SelectionTools/SearchURLBuilder.swift` stay Foundation-only and pure,
  `Plugins/TextReplacement/TextReplacementEngine.swift` stays
  Foundation-only and pure while `Plugins/TextReplacement/TextReplacementStore.swift` stays
  Foundation + Combine, `Plugins/Note/NoteEngine.swift` stays Foundation-only and pure while
  `Plugins/Note/NoteStore.swift` stays Foundation + Combine for `Tools/note-test.swift`,
  `Plugins/Quicklinks/QuicklinkTypes.swift` stays Foundation-only and pure while
  `Plugins/Quicklinks/QuicklinkStore.swift` stays Foundation + Combine for
  `Tools/quicklink-test.swift`, `Plugins/AIChat/AIChatTypes.swift` and
  `Plugins/AIChat/AIChatSelectionPrompts.swift` stay Foundation-only and pure for
  `Tools/ai-chat-test.swift`, `Plugins/DashboardWidgets/DashboardWidgetsEngine.swift` stays
  Foundation-only and pure for `Tools/dashboard-widgets-test.swift`,
  `Plugins/ChatGPTLauncher/ChatGPTLauncherTypes.swift` stays
  Foundation-only and pure for `Tools/chatgpt-launcher-test.swift`,
  `Plugins/Mole/MoleTypes.swift` stays Foundation-only and pure for
  `Tools/mole-test.swift` (its harness never executes Mole), `Plugins/Coffee/CoffeeTypes.swift`
  stays Foundation-only and pure for `Tools/coffee-test.swift`, the
  `Plugins/WindowManagement/WindowCommand.swift` / `WindowLayout.swift` / `WindowActionMemory.swift`
  trio stays Foundation + CoreGraphics for `Tools/window-command-test.swift`, and
  `Plugins/ImageModification/ImageModificationTypes.swift` stays
  Foundation-only so their standalone harnesses compile without app state.
  `Plugins/Clipboard/ClipboardStore.swift` must keep to Foundation + SQLite3 with no other app
  source, so their `Tools/` harnesses can compile them standalone. `Core/LauncherRankingStore.swift`
  is the same deal for `Tools/ranking-test.swift` — Foundation only, with the clock injected via
  `now` and the store path via `fileURL`, as is `Core/SearchScopes.swift` for `Tools/scopes-test.swift`.
  `Core/CustomCommand.swift` and `Core/ShellCommandRunner.swift` must likewise stay free of AppKit /
  SwiftUI (Foundation plus Combine for `ObservableObject` and Darwin for `mkstemp`) so
  `Tools/custom-command-test.swift` can compile them standalone — which is why the custom-command
  confirmation gate lives in `AppCore` and not in the runner.
- **`Core/SearchRelevance.swift` stays Foundation-only and pure** — `Tools/fuzz-test.swift` compiles
  the real scorer, so there is no copy to keep in sync (the old mirrored-`FuzzyMatch` invariant is
  retired). `Core/SpotlightNames.swift` owns the only Spotlight read; keep its per-bundle
  modification-date cache, since the scan reruns on every launcher open.
- **`EmojiData.generated.swift` is emitted by `node Tools/gen-emoji.js` and
  `CurrencyData.generated.swift` by `node Tools/gen-currencies.js`** — never edit either by hand.
  Their outputs live in `Plugins/EmojiSymbols/` and `Plugins/CurrencyConversion/`, respectively.
  Currency names, signs and uncontested nouns are generated (Frankfurter × CLDR); the only
  hand-maintained currency data is `CalcCurrency.contested`, the nouns several currencies share
  (`dollars`, `pounds`). Don't add slang or synonyms there — no source of truth, so they rot.
- **Every networked feature ships off and is consent-gated.** Spotter is offline by default; a
  feature that reaches the network must be opt-in behind a Settings toggle whose dialog names the
  provider, the cadence and what leaves the machine, and its owning store must re-check consent at
  every entry point — including on both sides of the `await` around the request, since consent can
  be withdrawn mid-flight. Consent flags live on the owning store, never in `AppSettings`
  (`SettingsBackup` mirrors that type, and an import must not grant network access). Model the gate
  so the *safe* state is the default: `CalcEngine.evaluate`'s `currency:` parameter defaults to
  `.off`, so forgetting to pass one disables the feature rather than enabling it. Fetch on a private
  **cacheless** `URLSession` (`.ephemeral`, `urlCache = nil`), never `URLSession.shared` — a cacheable
  response would leave a second copy in the on-disk `URLCache` that opting out doesn't delete.
  `Plugins/CurrencyConversion/CurrencyRateStore.swift` is the reference implementation — follow it
  rather than inventing a second shape. **Deliberate exception (owner decision, Aug 2026):**
  `Core/OpenRouterStore.swift` has no separate consent toggle — the API key is the gate. No key
  means no request can be made (AI Chat and its selected-text actions stay unavailable); entering the key, or syncing
  a settings file that carries one, is the consent act. Do not reintroduce a toggle for it, and do
  not copy this shape for new networked features without an explicit owner decision.
  `Core/UpdateStore.swift` follows the consent shape: the daily update check ships off behind a
  consent dialog (never synced); the manual Check for Updates click is itself the consent for that
  one request. Stable and beta feeds stay channel-isolated, and installs only happen on an explicit
  click after the new bundle passes designated-requirement signature verification. See
  [`docs/updates.md`](docs/updates.md). `Core/UpdateFeed.swift` stays Foundation-only and pure for
  `Tools/update-test.swift`.
- **Plugins are native compile-time modules.** Every built-in plugin owns one
  `Spotter/Plugins/<Name>/` directory and one registration factory. Do not add runtime-loaded bundles,
  JavaScript execution, reflection-based discovery or a second plugin registry. See
  [`docs/plugins.md`](docs/plugins.md) and use the tracked `$spotter-plugin` skill.
- **AI Chat is an application feature; Commands is a plugin.** AI Chat reuses registry wiring with
  `settingsPlacement: .application` but is always enabled and never exports an enable state. Commands
  owns the custom-command Settings view and dynamic launcher entries; disabling it preserves command
  data and bindings while hiding entries and making their hotkeys no-op.
- **Plugin interaction is palette-first.** Search/filter → result-list → action plugins must use a
  registered `PluginPaletteScreenRegistration` and the shared `PluginPaletteList`; they must not
  create a separate window, search field, list chrome or footer. Dedicated plugin windows are limited
  to sustained editors/canvases or complex multi-step workspaces that cannot fit the launcher model,
  and must still go through `AppCore.showPluginWindow`. Kill Process is the palette-screen reference.
- **Confirmations are in-palette.** Every destructive palette flow (Mole actions, built-in Commands,
  custom commands, Quit All) asks through `AppCore.confirmInPalette` / `ConfirmationCard`, never an
  `NSAlert`, and the card's highlight always starts on Cancel — a reflexive second ↵ must never be
  the confirmation. The one deliberate exception is Image Modification's Replace Original alert,
  which belongs to its workspace window.
- **Process and image mutations stay explicit.** Kill Process never exposes PID 0/1 or Spotter and
  executes selected process actions immediately without dismissing its palette. Image Modification's
  Convert Image command selects a target format in a second-level palette before any work starts and
  confirms every Replace Original run; pixel work stays off the main actor and temporary output is
  bundle-identifier-scoped.
- **Swift 6 language mode: data-race violations are hard errors.** Almost everything is `@MainActor`;
  cross-actor model types are `Sendable`; heavy / IO work (app scan, image decode) is pushed off-main
  via `Task.detached` / `nonisolated`. Keep that boundary. House idioms: `NotificationToken` (RAII) for
  block observers, `isolated deinit` for `ClipboardStore`'s SQLite teardown, decode raw Carbon / C
  pointers to plain values before crossing into actor code.
- **Clipboard writes stamp a private `internalType` marker** so the poller skips Spotter's own writes.
- **Settings sync reuses `SettingsBackup`.** The selected JSON file may live in iCloud Drive, but
  Spotter must coordinate access with `NSFileCoordinator`, observe replacement-safe file changes,
  hot-apply only fully decoded snapshots, suppress its own write notifications, and never synchronize
  network consent. See [`docs/settings-sync.md`](docs/settings-sync.md).
- **Text Replacement never records arbitrary typing or uses the clipboard.** Its matcher retains only
  a suffix that can still become a configured trigger, and its synthetic deletion/insertion events use
  the shared event-source marker so neither its own tap nor Hyper Key rewrites them.
- **Hotkeys persist under legacy `KeyboardShortcuts_<name>` UserDefaults keys** (from the removed
  KeyboardShortcuts package) so old bindings survive — and a `.combo` binding must keep encoding as
  the bare `KeyShortcut` record, or every existing binding and backup reads as unbound.
  `Core/HotKey/DoubleTapDetector.swift` stays Foundation-only and pure for `Tools/hotkey-test.swift`.
  See [hotkeys.md](docs/hotkeys.md).
- **Read [`docs/ui.md`](docs/ui.md) before any restyle or new view.** `Core/Theme.swift` is the single
  design-token source.
- **`Core/EdgeDissolve.swift` and `Core/ThinScrollbar.swift` are off-limits.** Both are tuned by eye
  against the palette's floating bars, so any edit is a visual regression. Do not touch them to fix a
  scroll bug, and never as a side effect of a restyle or refactor — needing to is the signal that the
  real fix belongs elsewhere (a scroll target, an inset, an intent). Edit either one only under an
  explicit task to change that look.

## Project Layout

- `Spotter/Core/` — shared managers, stores, windows and AppKit glue (no view bodies beyond hosting).
  `Core/Calculator/` is the shared pure calculator engine; `Core/Theme.swift` owns design tokens;
  `Core/HotKey/` is the in-house hotkey stack.
- `Spotter/Plugins/Infrastructure/` — the shared plugin contract and registry;
  `Spotter/Plugins/<Name>/` — each native plugin's registration, logic, settings and feature views;
  `Spotter/Plugins/BuiltInPlugins.swift` — the intentionally explicit compile-time catalog.
- `Spotter/Features/` — shared/system SwiftUI views: `RootPaletteView`, `Launcher/`, `Calculator/`,
  `Settings/`, `About/`, `Onboarding/`, plus shared `PopoverMenu`.
- `Spotter/App/` — `@main` app + delegate.
- `Tools/` — standalone test harnesses and the emoji generator.
- `scripts/release-preflight.sh` — version-mirror and publication prerequisite validation.
- `.codex/skills/spotter-plugin/` — tracked project skill for all built-in plugin lifecycle work.
- `.codex/skills/spotter-release/` — tracked release preparation, publication and audit workflow.
- `.github/workflows/release.yml` — the entire release pipeline (see `docs/development.md`).

## Additional Documentation

- [`docs/architecture.md`](docs/architecture.md) — core ownership, windows, concurrency.
- [`docs/plugins.md`](docs/plugins.md) — native plugin contract, directory layout and extension flow.
- [`docs/kill-process.md`](docs/kill-process.md) · [`docs/change-case.md`](docs/change-case.md) ·
  [`docs/image-modification.md`](docs/image-modification.md) ·
  [`docs/notes.md`](docs/notes.md) · [`docs/quicklinks.md`](docs/quicklinks.md) ·
  [`docs/world-clock.md`](docs/world-clock.md) · [`docs/selection-tools.md`](docs/selection-tools.md) ·
  [`docs/window-management.md`](docs/window-management.md) · [`docs/system-commands.md`](docs/system-commands.md) ·
  [`docs/mole.md`](docs/mole.md) · [`docs/coffee.md`](docs/coffee.md) (Caffeinate) ·
  [`docs/ai-chat.md`](docs/ai-chat.md) · [`docs/chatgpt-launcher.md`](docs/chatgpt-launcher.md) ·
  [`docs/custom-commands.md`](docs/custom-commands.md)
  — built-in plugin behavior and implementation.
- [`docs/palette.md`](docs/palette.md) — palette state flow, menu-open freeze, focus restoration.
- [`docs/launcher.md`](docs/launcher.md) · [`docs/calculator.md`](docs/calculator.md) ·
  [`docs/clipboard.md`](docs/clipboard.md) · [`docs/emoji.md`](docs/emoji.md) ·
  [`docs/hotkeys.md`](docs/hotkeys.md) · [`docs/text-replacement.md`](docs/text-replacement.md) ·
  [`docs/settings-sync.md`](docs/settings-sync.md) — subsystem internals.
- [`docs/ui.md`](docs/ui.md) — the full visual design system, tokens, scrollbars, section headers.
- [`docs/development.md`](docs/development.md) — build, test, package, release.
- [`docs/signing.md`](docs/signing.md) — signing model and Gatekeeper.
- [`docs/updates.md`](docs/updates.md) — updater channels, consent, trust and installation flow.
