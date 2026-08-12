# Architecture

How Spotter is wired together. See the per-subsystem docs for internals:
[palette](palette.md), [launcher](launcher.md), [calculator](calculator.md),
[clipboard](clipboard.md), [plugins](plugins.md), [custom commands](custom-commands.md),
[hotkeys](hotkeys.md), [background tasks](background-tasks.md), [ui](ui.md),
[settings-sync](settings-sync.md), [signing](signing.md),
plus one doc per built-in plugin (emoji, world-clock, kill-process, change-case, selection-tools,
image-modification, notes, text-replacement, quicklinks, window-management,
commands (including built-in system commands), mole, coffee).

## Single-owner core

`AppCore.shared` (`Core/AppCore.swift`) is a `@MainActor` singleton that owns every long-lived
manager — `AppIndex`, `ClipboardStore`, `ClipboardManager`, `HotKeyManager`, `HyperKeyTap`,
`AppSettings`, `FavoritesStore`, `VisibilityStore`, `LauncherRankingStore`, `CustomCommandStore`,
`CalculatorHistoryStore`, `CurrencyRateStore`, `EmojiIndex`, `FrequentEmojiStore`,
`RunningAppsMonitor`, `WorldClockStore`, `DashboardWidgetsStore`, `KillProcessManager`, `ChangeCaseStore`,
`OpenRouterStore`, `SelectionToolsManager`, `ImageModificationManager`, `TextReplacementStore`,
`TextReplacementManager`, `NoteStore`, `QuicklinkStore`, `QuicklinkManager`, `WindowMover`,
`MoleManager`, `CoffeeManager`, `BackgroundTaskStore`, `UpdateStore`, `CommandHUD`,
`SettingsSyncManager`,
`PaletteViewModel`, `PluginRegistry`, `AIChatStore` — plus the window
controllers. One deliberate singleton lives outside this rule: `AppLog.shared`
(`Core/AppLog.swift`), the diagnostics sink every subsystem reaches — infrastructure like
`NotificationCenter.default`, not feature state. It mirrors entries into `os.Logger`, keeps a
ring buffer for Settings → Diagnostics, and writes a size-capped rotated file. The registry owns capability registrations, not feature managers: registration closures
refer back to managers on `AppCore`, so it does not weaken the single-owner rule.
`AppDelegate.applicationDidFinishLaunching` calls
`AppCore.shared.start()` and nothing else; that is the single wiring point. All palette / paste /
launch actions are methods on `AppCore` that the SwiftUI views call.

## Built-in plugin registry

Native feature modules live under `Spotter/Plugins/<Name>/` and register through the explicit
`Spotter/Plugins/BuiltInPlugins.swift` catalog. Shared contracts stay in
`Spotter/Plugins/Infrastructure/`; plugin-specific engines, stores, settings and views stay inside the
plugin's own directory. These are source-level modules in the main target, so they retain direct native
calls and compile-time checking without framework or runtime-loader overhead.

The registry adds system-feature rows to the fixed System Settings group, generates the Plugins
group, persists plugin enable states, routes
launcher commands and shortcut actions, declares permission use, keeps a precomputed enabled
query-provider list, and hosts plugin palette-screen registrations. AI Chat and Dashboard Widgets
are always-available system features that reuse this wiring; Commands is a disableable plugin. See
[plugins.md](plugins.md) for the contract, directory rules, `$spotter-plugin` project skill and plugin
lifecycle checklists.

## Entry points and windows

`SpotterApp` (`@main`) declares only a `MenuBarExtra` scene; everything else visible is driven
imperatively from AppKit.

- **Command palette** — a borderless floating `NSPanel` (`Core/PalettePanel.swift`) hosting SwiftUI
  via `NSHostingView`, managed by `PaletteWindowController`. It toggles between a compact bar and the
  full launcher by resizing the window. `PaletteWindowController` solely owns the frame (resolved once
  per show to a top-left anchor so it grows downward), and the hosting view sets `sizingOptions = []`
  so SwiftUI never drives the window size — without that the hosting view resizes the panel to fit
  content and the top edge drifts on the compact↔expanded swap. The panel is drag-movable by its
  background; a drag re-anchors the session, and with **Remember position** on it persists across
  summons. The panel auto-dismisses on `windowDidResignKey`.
- **Settings / About** — plain `NSWindow`s via `AuxWindowController` (in
  `Features/About/AboutView.swift`). SwiftUI `Settings` / `Window` scenes are unreliable for accessory
  apps, so this is deliberate.
- **Software Update** — a core command-palette sub-screen opened by the launcher command. It observes
  the `AppCore`-owned `UpdateStore`, performs a fresh manual check on every invocation and keeps the
  complete check/download/verify/install/relaunch flow inside the shared palette shell.
- **Plugin workspaces** — the same `AuxWindowController`, reached only through
  `AppCore.showPluginWindow`. A plugin owns the hosted view and feature manager, while `AppCore`
  retains sole window ownership and closes the workspace from `onDisable`. The helper can opt a
  workspace into transparency, resizing and floating window level. Notes uses all three and requests
  content-driven height changes through `AppCore`, including its temporary list expansion, leaving
  frame ownership and activation routing centralized.
- **Command HUD** — a second borderless panel (`Core/CommandHUD.swift`), owned directly by `AppCore`,
  that briefly confirms otherwise-invisible command results ("Trash Emptied"). Non-activating and
  mouse-ignoring by design: the command just acted on the app the user came from, and taking focus
  back to report on it would undo the thing being reported.
- **Plugin palette screens** — `PaletteMode.plugin(PluginID)` keeps list-oriented plugin flows inside
  the command palette. `PluginRegistry` supplies snapshots and actions; `RootPaletteView` and
  `PluginPaletteList` retain sole ownership of the search, selection, rows, scrolling and footer.
  Selection Tools uses this route for browser-search failures and its three-row Google translation
  result. AI Chat owns bilingual definition and grammar checking as follow-up-ready chat sessions.
- **Launcher dashboard** — the registered system feature that owns `launcherDashboard` contributes one
  non-selectable view above the empty-query launcher sections. `RootPaletteView` keeps the dashboard
  inside the palette's existing scroll view and selection model; the plugin owns only its local data
  and card content, never a window or a second search field.
- **Background tasks** — `BackgroundTaskStore` keeps long-running work visible as the launcher's
  first selectable rows, visually below the non-selectable dashboard and above Favorites, while
  each feature manager remains the executor. Finished rows stay until dismissed; see
  [background-tasks.md](background-tasks.md).

The app follows the system appearance. Every color token lives in `Core/Theme.swift` as an
`adaptive(dark:light:)` pair resolved through `NSColor`'s dynamic provider, so views never branch on
`colorScheme`; `Tools/theme-test.swift` pins both stops of every token.

## Concurrency

The target builds in **Swift 6 language mode** (tools version 6.0, no language-mode override), so
data-race safety violations are hard errors. Almost everything is `@MainActor`; cross-actor model
types are `Sendable`. Heavy / IO work (app scan, process snapshots, image transforms, AppleScript and
the FX rate fetch) is deliberately
pushed off-main via `Task.detached` / `nonisolated`. Keep that boundary when adding code.

House idioms for the sharp edges:

- Block-observer lifetimes go through the RAII `NotificationToken` (`Core/NotificationToken.swift`)
  instead of removal in a `deinit`.
- `ClipboardStore` uses `isolated deinit` for its SQLite teardown.
- Raw Carbon / C pointers get decoded to plain values before crossing into actor code (see
  `hotKeyCarbonEventHandler`).
