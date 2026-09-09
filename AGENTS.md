## Project

Spotter is a native macOS menu-bar launcher (a minimal Raycast): fuzzy app launcher, global +
per-app hotkeys, a text/image clipboard history, an inline calculator, and an emoji picker. SwiftUI +
AppKit, runs as an accessory (no Dock icon, `LSUIElement`). Targets **macOS 26+** (Liquid Glass) and
builds with the **Xcode 26** toolchain.

- **Build:** XcodeGen owns the project — `Spotter.xcodeproj` is committed but generated from
  `project.yml`. After editing `project.yml`, run `xcodegen generate` and commit. There is **no**
  `Package.swift` / SwiftPM. Full build/test/sign/release steps: [`docs/development.md`](docs/development.md),
  [`docs/signing.md`](docs/signing.md).
- **Build channels and versions:** The build installed on this Mac is the **dev** channel; a public
  release is the **stable** channel. Dev builds are never published. Dev and stable share one base
  version: dev appends `-dev` (for example `1.4.9-dev`) while stable uses the bare version
  (`1.4.9`).
- **Local build destination:** Every successful new local build must be installed immediately as
  `/Applications/Spotter.app`. Do not maintain or launch a separate `Spotter Dev.app`;
  `project.yml` already builds Debug as `Spotter.app` / `com.spotter.app1`, so keep the same product
  name and bundle identifier across dev and stable.
- **Replace and relaunch after every successful build — through `scripts/install-dev.sh`.** Build
  into a staging/DerivedData location first; only after the new app has built and passed its required
  checks, hand that bundle to the script, which quits Spotter, waits for it to actually exit, stages
  the replacement beside `/Applications/Spotter.app` and swaps the two atomically before relaunching.
  **Never remove the installed bundle to install over it.** `tccd` invalidates a bundle's grants when
  it sees that bundle deleted, so a remove-then-copy install silently costs Accessibility, Screen
  Recording and Full Disk Access on every build — which strands the Hyper Key's event tap and every
  global hotkey with it, looking like a dozen unrelated bugs. `UpdateStore` swaps atomically for this
  exact reason; dev installs get no exemption. Waiting for a real quit is part of the contract too:
  a killed process can lose preferences it has just written. Never delete the working installed copy
  before a new build succeeds, and never target anything broader than the exact Spotter app bundle.
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
- **Don't verify with computer use that a feature looks right.** Build, install and relaunch as the
  install contract requires, then hand it over — whether the result is beautifully correct is the
  user's call, and driving the UI to screenshot it costs more than it settles. Say plainly what you
  did and did not check rather than implying a look was confirmed.
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
- **The flat `selection` index must match the visible selectable-row order exactly.** The empty-query
  dashboard is non-selectable; visually, background tasks sit below it and above Favorites. Among
  selectable rows, tasks come first, then the inline calculator/plugin card, then normal results.
  Selection is the single source of truth for highlight / activation.
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
  Foundation-only and pure, `Plugins/SelectionTools/SelectionToolsTypes.swift`,
  `Plugins/SelectionTools/SelectionToolsResults.swift` and
  `Plugins/SelectionTools/SearchURLBuilder.swift` stay Foundation-only and pure, as do
  `Plugins/Translate/TranslateTypes.swift` and `Plugins/Translate/TranslateResults.swift` for
  `Tools/translate-test.swift`,
  `Plugins/TextReplacement/TextReplacementEngine.swift` stays
  Foundation-only and pure while `Plugins/TextReplacement/TextReplacementStore.swift` stays
  Foundation + Combine, `Plugins/Note/NoteEngine.swift`,
  `Plugins/Note/NoteSyncDocument.swift` and `Plugins/Note/NoteFolderDocument.swift` stay
  Foundation-only and pure while `Plugins/Note/NoteStore.swift` stays Foundation + Combine and
  `Plugins/Note/NoteFolderIO.swift` stays Foundation with no app source, all for
  `Tools/note-test.swift` — the Notes folder's front-matter format, naming scheme, collision rule and
  whole reconciliation live in `NoteFolderDocument.swift` so the harness can exercise them, including
  the hostile files, against real temporary directories,
  `Plugins/Quicklinks/QuicklinkTypes.swift` stays Foundation-only and pure while
  `Plugins/Quicklinks/QuicklinkStore.swift` stays Foundation + Combine for
  `Tools/quicklink-test.swift`, `Plugins/AIChat/AIChatTypes.swift`,
  `Plugins/AIChat/AIChatSelectionPrompts.swift`, `Plugins/AIChat/AICommand.swift` and
  `Core/OpenRouterModelCatalog.swift` stay Foundation-only and pure while
  `Plugins/AIChat/AICommandStore.swift` stays Foundation + Combine, all for
  `Tools/ai-chat-test.swift` — the AI command record, its `{selection}` substitution, its validation
  and the list repair that keeps the two shipped commands present live there,
  `Plugins/DashboardWidgets/DashboardWidgetsEngine.swift`,
  `Plugins/DashboardWidgets/DashboardWeatherEngine.swift`,
  `Plugins/DashboardWidgets/DashboardMusicEngine.swift`,
  `Plugins/DashboardWidgets/DashboardDeviceBatteryEngine.swift` and
  `Plugins/DashboardWidgets/DashboardFileInfoEngine.swift` stay
  Foundation-only and pure for `Tools/dashboard-widgets-test.swift`,
  `Plugins/Uptime/UptimeEngine.swift` stays Foundation-only and pure for `Tools/uptime-test.swift`,
  `Plugins/Mole/MoleTypes.swift` stays Foundation-only and pure for
  `Tools/mole-test.swift` (its harness never executes Mole); `MoleProcessRunner` must check the real
  termination status, retain stderr, and supply synthetic stdin only to a post-confirmation
  uninstall — a queued run is still one of those, and nothing else may receive it. Mole runs one
  state-changing command at a time, so confirmed actions wait in `MoleRunQueue`: the ordering rule
  stays a pure type in `MoleTypes.swift` while `MoleManager` owns the processes, and one
  confirmation card still buys exactly one queue entry. `Plugins/Coffee/CoffeeTypes.swift` stays Foundation-only and pure for
  `Tools/coffee-test.swift`,
  `Plugins/CalendarSchedule/CalendarScheduleEngine.swift` stays Foundation-only and pure (clock,
  calendar and locale injected) for `Tools/calendar-schedule-test.swift`, the
  `Plugins/Screenshot/ScreenshotWindowPicker.swift`, `ScreenshotGeometry.swift`,
  `ScreenshotColorSampler.swift`, `ScreenshotImageProcessor.swift`, `ScreenshotAnnotation.swift` and
  `ScreenshotTextLayout.swift`
  stay pure CoreGraphics/CoreText/ImageIO pixel code for `Tools/screenshot-test.swift`, the
  `Plugins/WindowManagement/WindowCommand.swift` / `WindowLayout.swift` / `WindowActionMemory.swift`
  trio stays Foundation + CoreGraphics for `Tools/window-command-test.swift`, and
  `Plugins/ImageModification/ImageModificationTypes.swift` and
  `Plugins/FileSearch/FileSearchTypes.swift` (which `Tools/file-search-test.swift` compiles beside
  the real `Core/SearchRelevance.swift` it ranks with) stay
  Foundation-only so their standalone harnesses compile without app state.
  `Plugins/Clipboard/ClipboardStore.swift` must keep to Foundation + SQLite3 with no other app
  source, so their `Tools/` harnesses can compile them standalone. `Core/LauncherRankingStore.swift`
  is the same deal for `Tools/ranking-test.swift` — Foundation only, with the clock injected via
  `now` and the store path via `fileURL`, as is `Core/SearchScopes.swift` for `Tools/scopes-test.swift`.
  `Core/CustomCommand.swift` and `Core/ShellCommandRunner.swift` must likewise stay free of AppKit /
  SwiftUI (Foundation plus Combine for `ObservableObject` and Darwin for `mkstemp`) so
  `Tools/custom-command-test.swift` can compile them standalone — which is why the custom-command
  confirmation gate lives in `AppCore` and not in the runner. `Core/LauncherFallback.swift` and
  `Core/TerminalCommandRunner.swift` also stay Foundation-only for
  `Tools/launcher-fallback-test.swift`; the latter passes user input as one `osascript` argv value,
  never interpolated AppleScript source. `Core/AppVersion.swift` stays Foundation-only for
  `Tools/app-version-test.swift`.
- **`Core/SearchRelevance.swift` stays Foundation-only and pure** — `Tools/fuzz-test.swift` compiles
  the real scorer, so there is no copy to keep in sync (the old mirrored-`FuzzyMatch` invariant is
  retired). `Core/PaletteMenuTypeahead.swift` reuses that same scorer for Actions-menu matching and
  stays Foundation-only and pure for `Tools/menu-typeahead-test.swift`.
  `Core/SpotlightNames.swift` owns the only Spotlight read; keep its per-bundle
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
  (`SettingsBackup` mirrors that type). Fresh installs remain off; explicitly trusting a sync or
  backup file may restore consent and is itself the consent act. Model the gate
  so the *safe* state is the default: `CalcEngine.evaluate`'s `currency:` parameter defaults to
  `.off`, so forgetting to pass one disables the feature rather than enabling it. Fetch on a private
  **cacheless** `URLSession` (`.ephemeral`, `urlCache = nil`), never `URLSession.shared` — a cacheable
  response would leave a second copy in the on-disk `URLCache` that opting out doesn't delete.
  `Plugins/CurrencyConversion/CurrencyRateStore.swift` is the reference implementation — follow it
  rather than inventing a second shape. The Translate plugin's Google Translation path follows that
  consent shape; its API key and target list are included in the trusted v3 backup/sync snapshot.
  `Plugins/DashboardWidgets/DashboardWeatherStore.swift` follows it too: the clock face's weather
  complications (one reading and one request) ship off, the forecast fetch is refused without
  consent, and its enable state *is* consent. **The place is the Mac's own** (owner decision, Sep
  2026, reversing the chosen city that preceded it): `DashboardWeatherLocation.swift` holds the only
  `CLLocationManager` in Spotter and takes **one coarse fix** — `kCLLocationAccuracyReduced`, with
  `NSLocationDefaultAccuracyReduced` in `Info.plist` so macOS never offers the precise kind, and
  `requestLocation()` rather than a subscription. A forecast is a property of a city, so never ask for
  a finer fix, never monitor between refreshes, and keep CoreLocation out of the pure engines — they
  see a coordinate, never a manager. Spotter's dialog comes first and macOS's location prompt second:
  a decline creates no location manager and raises no system prompt at all. The forecast request asks
  for the located place's own day (`timezone=auto`), which is derived from the coordinates it already
  carries; don't widen it to anything the fix doesn't already imply, and take the clock's zone from
  that same answer rather than a second request. **There is no fallback place and no manual entry**:
  a denied, restricted or unobtainable fix must *say so* — on the card and in the Settings row, with
  the path to System Settings ▸ Privacy — and must never show another place's weather as though it
  were the user's, which with no city field left would be a wrong reading nobody could correct.
  `DashboardWeatherEngine.locationState` holds those states as pure logic and
  `Tools/dashboard-widgets-test.swift` pins them. **Weather is asked once, at first launch, and once granted it is
  permanently on** (owner decision, Sep 2026) — the one exception to "a networked feature must be
  withdrawable", and it is not a licence to build a second one. Everything else about the gate
  stands: no request before consent, a dialog that still names Open-Meteo, the 30-minute cadence and
  what leaves the Mac, and `isEnabled` re-checked at every entry point including both sides of the
  `await`. Because the question is asked exactly once, **"asked" and "granted" are two separate
  persisted facts** (`dashboard-widgets.weather-consent-asked` and
  `dashboard-widgets.weather-enabled`): a decline records the answer and leaves weather off, is never
  asked again on a later launch, and leaves Settings ▸ Widgets a way to grant it later. There is no
  off switch; `DashboardWeatherEngine.consentState`/`shouldPresentConsent` hold that rule as pure
  logic and `Tools/dashboard-widgets-test.swift` pins it. The Clock follows that located place, and the sharing
  runs **one way only** — the fix sets the clock's zone, but setting a zone reaches no location and
  sends nothing. **There is no location control at all**: no city field and no time-zone picker, and
  a Mac that has not answered the dialog, or cannot be located, still gets a working clock from its
  own saved zone or the system's, never a blank face. Do not make the complications draw without
  consent. Its consent flag and unit ride in the trusted v3 snapshot; the located place and the clock
  zone derived from it stay device-local, since a coordinate from another Mac is the same class of
  mistake as a file path from another Mac. A snapshot carrying `false` grants nothing and is not an
  answer, so the receiving Mac is still asked.
  `Plugins/Uptime/UptimeStore.swift` is deliberately **always on, with no switch and no consent
  dialog** (owner decision, Sep 2026), and what makes that defensible is how little it takes rather
  than a gate: the counters must stay counters — key or click and an autorepeat flag are the only
  facts taken off an event; never read a key code, character, modifier or click location. Nothing
  identifying is retained, so there is nothing here from which typing could be reconstructed; the
  tallies clear at midnight, stay device-local, and ride in no backup or sync file. Count through
  passive `NSEvent` monitors, never a new `CGEventTap` — a global monitor cannot alter or swallow an
  event, and the local one beside it is only there because global monitors never see Spotter's own.
  Widen any of that — a key code, a location, a tap, a network hop, anything persisted beyond the
  day's integers — and the feature needs a gate again, which is an owner decision. Uptime is a plugin
  rather than a widget (owner decision, Aug 2026). Its persistence keys keep their
  `dashboard-widgets.uptime-*` names — renaming them would silently drop existing tallies.
  The music card is not consent-gated, for the File Info reason: it asks Music through one Apple
  Event and macOS's own Automation prompt is the gate. It must never launch Music — check that the
  app is already running before any script, since `tell application "Music"` starts it — and it polls
  only while the launcher is on screen.
  `Plugins/DashboardWidgets/DashboardDeviceBatteryStore.swift` is deliberately *not* gated, and the
  contrast with uptime is the point: reading `BatteryPercent` off the IOKit registry and relaying
  bluetoothd's levels through one `system_profiler` subprocess need no TCC grant, no entitlement and
  no monitor, persist nothing and send nothing, so there is no ongoing access for a switch to
  withdraw. Do not add a consent dialog to it, and do not reach for IOBluetooth or CoreBluetooth —
  that route demands `NSBluetoothAlwaysUsageDescription` and prompts for Bluetooth access
  process-wide, which is a system permission for one card and needs an explicit owner decision.
  The File Info card is likewise not consent-gated, but for a different reason: it asks the Finder,
  through `Core/FinderSelection.swift`, and macOS's own Automation prompt *is* the gate. Keep that the
  only place anything asks the Finder what is selected, keep the read to name/kind/size, and never
  open a selected file's contents or persist anything about the selection. A folder is counted, not
  weighed — do not add a recursive folder crawl to a card that reads on every summon.
  File Search is deliberately not gated for the same reason: reading the Spotlight index macOS
  already keeps needs no TCC grant, no entitlement and no monitor, builds and persists no index of
  its own and sends nothing. Its structural exclusions are what hold that line — hidden paths, the
  interiors of `.app` bundles and `~/Library` as a general scope stay out of every search, so it
  never becomes a crawl of everything the user owns. Do not add a consent dialog to it, and do not
  widen those exclusions without an explicit owner decision.
  **Deliberate exceptions (owner decisions, Aug 2026):**
  `Core/OpenRouterStore.swift` has no separate consent toggle — the API key is the gate. No key
  means no request can be made (AI Chat and every AI command, shipped or user-written, stay
  unavailable); entering the key, or syncing
  a settings file that carries one, is the consent act. A user-authored AI command prompt is content,
  never a second way onto the network: it cannot run without the key either. Do not reintroduce a toggle for it, and do
  not copy this shape for new networked features without an explicit owner decision.
  `Plugins/Translate/TranslateManager.swift` is on that same shape: it has no Cloud Translation
  consent toggle and the Google API key is the only gate. No key,
  no request, and neither Translate Selected Text nor the Translate page can run. The Settings key
  row still names the provider, what is sent and the per-target billing, and the key and the
  target-language list ride the trusted v3 snapshot. The source language is detected **on device**
  with `NLLanguageRecognizer` before anything is sent, so a target the text is already written in
  costs no request at all — keep that detection local and never add a network round trip to discover
  the language or the language list. **The Translate page translates as you type, so its economy is
  load-bearing:** requests fire only after `TranslateTiming.typingPause` of silence (one constant,
  retune there and nowhere else), `TranslationMemo` refuses to bill the same text into the same
  targets twice, and a run whose text has been superseded is cancelled. Do not move the trigger to a
  keystroke, remove the memo, or let a second surface call `translate(_:)` without those guards. The
  Settings
  model menu's catalog read (`/models`) stays behind the same gate — no key, no fetch, and clearing
  the key drops the list — and stays unauthenticated and free of anything about this Mac.
  `Core/UpdateStore.swift` follows the consent shape: the daily update check ships off behind a
  consent dialog and its saved choice syncs; the manual Check for Updates click is itself the consent for that
  one request. Stable and beta feeds stay channel-isolated, and installs only happen on an explicit
  click after the new bundle passes designated-requirement signature verification. See
  [`docs/updates.md`](docs/updates.md). `Core/UpdateFeed.swift` stays Foundation-only and pure for
  `Tools/update-test.swift`.
  Notes sync through a **user-chosen folder of Markdown files**, one file per Note, and choosing that
  folder *is* the consent act — the Settings Sync precedent, so there is no dialog and no toggle to
  invent. Nothing leaves the Mac that the user did not point at a location: Spotter opens no network
  connection of its own for Notes. Notes' **CloudKit** pipeline (`NoteSyncManager`,
  `NoteCloudSyncEngine`) is retired but kept whole and compiling (owner decision, Sep 2026): it has
  no Settings switch, `AppCore` constructs it and never calls `start()`, and its consent flag no
  longer rides the backup — a v3 file carrying `iCloudSyncEnabled: true` is ignored on decode and can
  never start it. Restoring it means restoring an entry point, not rewriting the engine, so leave
  both files and the CloudKit entitlement/provisioning arrangement alone.
- **Plugins are native compile-time modules, and every one of them is always on.** Every built-in
  plugin owns one `Spotter/Plugins/<Name>/` directory and one registration factory. Do not add
  runtime-loaded bundles, JavaScript execution, reflection-based discovery or a second plugin
  registry. **A plugin cannot be disabled** (owner decision, Sep 2026): the registry keeps no enable
  state, `PluginRegistration` has no `defaultEnabled` / `canDisable` / `exportsEnabledState` /
  `readEnabled` / `writeEnabled` / `onDisable` (only an idempotent `onStart`), no Settings pane
  carries an enable switch, and nothing guards on `isEnabled`. The stale `plugin.<id>.enabled`
  defaults keys and a backup's `pluginStates` are simply unread, so a file that carried a disabled
  plugin restores it on — a plugin can never end up off and unreachable. Do not reintroduce the
  concept, and do not confuse it with a **network consent gate**, which belongs to the owning store
  and stays: `CurrencyRateStore` is the reference, and its Settings switch is that consent act, not a
  plugin switch. See [`docs/plugins.md`](docs/plugins.md) and use the tracked `spotter-plugin` skill.
- **AI Chat and Widgets are system features; Commands is a plugin.** Both reuse registry wiring.
  AI Chat uses `settingsPlacement: .system`;
  Widgets uses `.system` too, with **one page for the whole strip** (owner decision, Aug 2026,
  superseding both the per-card panes and the Arrangement pane that briefly replaced them): a
  section per card that has something to configure, no pane of its own for any card. A card with
  nothing to set gets no section at all (Device Battery and File Info, owner decision, Sep 2026),
  and cards that share a setting share one section — Clock and Weather share the pane's opening
  section, which like every pane's first group carries **no header**; it reports the located place
  rather than offering one, with no city field, no time-zone picker and no way to turn weather off;
  the Music section carries no
  Automation Permission row either (owner decision, Sep 2026 — the Finder and Music reads and macOS's
  own Automation prompt are unchanged, only the row is gone). **Order is set by dragging the cards in the
  palette**, which is the thing being arranged — do not reintroduce a list of names for it. Strip
  order is `DashboardWidgetPreferences.widgetOrder`, which is the strip's *only* preference:
  every card shows, with no on/off state at all (owner decision, Aug 2026 — do not reintroduce a Show
  list). `DashboardWidgetsEngine.widgetOrder(from:)` repairs whatever was saved, so a new widget kind
  needs no migration and a kind that leaves drops out of a saved order the same way. A card with
  nothing to report says so in its resting state; a feature whose visibility would be a consent act
  belongs in a plugin of its own, which is why Uptime became one. AI Chat owns **AI commands**
  (`Plugins/AIChat/AICommand.swift`): Define and Check Grammar are the two Spotter ships and are the
  same record as one the user writes, keeping their historical launcher entry ids and
  `KeyboardShortcuts_plugin.selection-tools.*` binding keys — their prompt, model and shortcut are
  editable and resettable, their name and identity are not, and they cannot be deleted. Commands
  owns the custom-command Settings view and dynamic launcher entries.
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
- **Potentially long one-shot work returns to the launcher as a background task.** The feature keeps
  ownership of execution and cancellation; `BackgroundTaskStore` owns only the row snapshot. Current
  coverage and deliberate exclusions are pinned in [`docs/background-tasks.md`](docs/background-tasks.md).
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
  Screenshot has the two deliberate exceptions. Its text recognition writes *unmarked* (owner
  decision, Aug 2026): the output is the user's own text and belongs in history. An image capture
  stays marked but is inserted into the store directly (owner decision, Aug 2026), because that is
  what lets it keep the name Spotter gives it — `<App>_SpotterScreenshot_<yyMMddHHmm>` — and that
  name is the only thing that marks a history entry as a screenshot. `ClipboardItem.isScreenshot`
  derives it from the file name through `ScreenshotFileName`, so the Screenshots filter needs no
  column, migration or backfill; `ClipboardFilter.swift` therefore compiles beside
  `Spotter/Plugins/Screenshot/ScreenshotFileName.swift`, which stays Foundation-only and pure.
- **Settings sync reuses `SettingsBackup`.** The selected JSON file may live in iCloud Drive, but
  Spotter must coordinate access with `NSFileCoordinator`, observe replacement-safe file changes,
  hot-apply only fully decoded snapshots, suppress its own write notifications, and mirror all
  covered user-owned settings and content, including credentials and network consent. Plugin enable
  state is not among them — there is none. Notes are the
  deliberate exception: manual backups still include them, but automatic Settings Sync must exclude
  Note content because `NoteFolderSyncManager` owns per-Note replication through the user's Notes
  folder. That folder's path is device-local and never travels in a snapshot, as neither
  synchronization path does. Concrete palette coordinates and system privacy grants also stay
  device-local. See [`docs/settings-sync.md`](docs/settings-sync.md).
- **A missing Note file is never a deletion.** The Notes folder is reconciled by the pure
  `NoteFolderReconciler`, and only two things may remove a file: a tombstone that won its merge, and
  a duplicate whose body and tint are identical to the copy that stays. An absent file, an iCloud
  placeholder, an unreadable or non-UTF-8 file and an unreadable ledger are all "present, unknown" —
  left untouched, never overwritten, never counted as gone, and their names stay reserved so a write
  cannot land on top of one. Deletions travel only in the hidden `.spotter-notes.json` tombstone
  ledger, which is never rewritten while it cannot be read. Identity lives in the front matter, so a
  retitle is a coordinated two-step move rather than a delete plus a create; collisions resolve
  deterministically (oldest note keeps the bare name) so two Macs never fight over one. Conflicts
  reuse `NoteSyncMerge` — the one merge policy in the codebase — and the body round-trips
  byte-for-byte. **A deletion is absorbing and a fork can never launder one.** A tombstoned id is
  never a Note again whatever the timestamps say, so the tombstone set only grows and the ledger is
  append-only; and a fresh identifier — the one thing that carries no tombstone — is never minted
  for content whose id has been deleted. In steady state two files under one id are a filesystem
  race (a retitle's create and delete arriving in either order, or the two-step move's
  `~<uuid>.md` half), so the newer is the Note and the other is left untouched and reserved; only
  the `.adoption` pass forks. Ranking a deletion against an edit by time, and forking a
  duplicated id in steady state, is how 1.5.29/1.5.30 resurrected deleted Notes and grew a Note per
  title state — do not restore either. Reads, writes, moves and deletions all go through `NSFileCoordinator`, writes are
  atomic, and a removed file goes to the Trash. **The first reconcile after a folder is adopted is
  deliberately not that merge**, and the asymmetry is an owner decision (Sep 2026): that pass keeps
  *both* texts when one id diverges, forking the loser to a fresh id, because it runs once per Mac
  over timestamps that were never comparable across machines and a silent winner there is an
  invisible, unrecoverable loss. Every pass after it merges normally, since a duplicate on each
  ordinary edit collision would be noise. `NoteFolderReconciler.plan` takes that as an undefaulted
  `NoteFolderPass`; the once-per-Mac flag is `NoteFolderAdoption`, set when a folder is chosen and
  cleared only by a reconcile that finished. Do not unify the two paths.
  Window Transparency and Auto Window Sizing live only in the Note window's own tint popover; Notes
  Settings carries no Appearance card (owner decision, Sep 2026). See [`docs/notes.md`](docs/notes.md).
- **Snippets' expansion never records arbitrary typing or uses the clipboard.** The plugin keeps its
  historical `text-replacement` identity (IDs, keys, file names); its matcher retains only a suffix
  that can still become a configured trigger (built from keyworded snippets only — palette-only
  snippets never touch typing), and its synthetic deletion/insertion events use the shared
  event-source marker so neither its own tap nor Hyper Key rewrites them.
- **Hotkeys persist under legacy `KeyboardShortcuts_<name>` UserDefaults keys** (from the removed
  KeyboardShortcuts package) so old bindings survive — and a `.combo` binding must keep encoding as
  the bare `KeyShortcut` record, or every existing binding and backup reads as unbound.
  `Core/HotKey/DoubleTapDetector.swift` stays Foundation-only and pure for `Tools/hotkey-test.swift`,
  and `Core/CommandID.swift` stays Foundation-only for `Tools/commands-test.swift` — a built-in
  command's `slug` keys its persisted shortcut, so the harness pins both uniqueness and the
  `command:` prefix. Every launcher row that can carry a shortcut must resolve one through
  `AppEntry.hotKeyAction`; a command kind with no case there silently loses its recorder.
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
- `.claude/skills/` and `.codex/skills/` — the tracked `spotter-plugin` (all built-in plugin
  lifecycle work) and `spotter-release` (release preparation, publication and audit) project skills;
  the two directories mirror each other for Claude Code and Codex — edit both together.
- `.github/workflows/release.yml` — the entire release pipeline (see `docs/development.md`).

## Additional Documentation

- [`docs/architecture.md`](docs/architecture.md) — core ownership, windows, concurrency.
- [`docs/plugins.md`](docs/plugins.md) — native plugin contract, directory layout and extension flow.
- [`docs/kill-process.md`](docs/kill-process.md) · [`docs/change-case.md`](docs/change-case.md) ·
  [`docs/image-modification.md`](docs/image-modification.md) ·
  [`docs/notes.md`](docs/notes.md) · [`docs/quicklinks.md`](docs/quicklinks.md) ·
  [`docs/world-clock.md`](docs/world-clock.md) · [`docs/uptime.md`](docs/uptime.md) ·
  [`docs/calendar.md`](docs/calendar.md) ·
  [`docs/selection-tools.md`](docs/selection-tools.md) (Search) ·
  [`docs/translate.md`](docs/translate.md) ·
  [`docs/window-management.md`](docs/window-management.md) · [`docs/system-commands.md`](docs/system-commands.md) ·
  [`docs/mole.md`](docs/mole.md) ·
  [`docs/coffee.md`](docs/coffee.md) (Caffeinate) ·
  [`docs/ai-chat.md`](docs/ai-chat.md) ·
  [`docs/custom-commands.md`](docs/custom-commands.md) · [`docs/screenshot.md`](docs/screenshot.md) ·
  [`docs/file-search.md`](docs/file-search.md) · [`docs/widgets.md`](docs/widgets.md)
  — built-in plugin and widget behavior and implementation.
- [`docs/palette.md`](docs/palette.md) · [`docs/background-tasks.md`](docs/background-tasks.md) —
  palette state flow, long-running task rows, menu-open freeze and focus restoration.
- [`docs/launcher.md`](docs/launcher.md) · [`docs/calculator.md`](docs/calculator.md) ·
  [`docs/clipboard.md`](docs/clipboard.md) · [`docs/emoji.md`](docs/emoji.md) ·
  [`docs/hotkeys.md`](docs/hotkeys.md) · [`docs/text-replacement.md`](docs/text-replacement.md) ·
  [`docs/settings-sync.md`](docs/settings-sync.md) — subsystem internals.
- [`docs/ui.md`](docs/ui.md) — the full visual design system, tokens, scrollbars, section headers.
- [`docs/development.md`](docs/development.md) — build, test, package, release.
- [`docs/signing.md`](docs/signing.md) — signing model and Gatekeeper.
- [`docs/updates.md`](docs/updates.md) — updater channels, consent, trust and installation flow.
