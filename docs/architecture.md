# Architecture

How Spotter is wired together. See the per-subsystem docs for internals:
[palette](palette.md), [launcher](launcher.md), [calculator](calculator.md),
[clipboard](clipboard.md), [plugins](plugins.md), [custom commands](custom-commands.md),
[hotkeys](hotkeys.md), [ui](ui.md).

## Single-owner core

`AppCore.shared` (`Core/AppCore.swift`) is a `@MainActor` singleton that owns every long-lived
manager — `AppIndex`, `ClipboardStore`, `ClipboardManager`, `HotKeyManager`, `AppSettings`,
`FavoritesStore`, `VisibilityStore`, `LauncherRankingStore`, `CustomCommandStore`,
`CalculatorHistoryStore`,
`CurrencyRateStore`, `RunningAppsMonitor`, `WorldClockStore`, `KillProcessManager`, `ChangeCaseStore`,
`OpenRouterStore`, `SelectionToolsManager`, `ImageModificationManager`, `TextReplacementStore`,
`MoleManager`, `CoffeeManager`, `UpdateStore`,
`TextReplacementManager`, `NoteStore`,
`SettingsSyncManager`,
`PaletteViewModel`, `PluginRegistry` — plus the window
controllers. The registry owns capability registrations, not feature managers: registration closures
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

The registry generates the Plugins Settings group, persists safe enable states, routes plugin launcher
commands and shortcut actions, declares permission use, keeps a precomputed enabled query-provider
list, and hosts plugin palette-screen registrations. See [plugins.md](plugins.md) for the contract,
directory rules, `$spotter-plugin` project skill and plugin lifecycle checklists.

## Entry points and windows

`SpotterApp` (`@main`) declares only a `MenuBarExtra` scene; everything else visible is driven
imperatively from AppKit.

- **Command palette** — a borderless floating `NSPanel` (`Core/PalettePanel.swift`) hosting SwiftUI
  via `NSHostingView`, managed by `PaletteWindowController`. It toggles between a compact bar and the
  full launcher by resizing the window. `PaletteWindowController` solely owns the frame (resolved once
  per show to a top-left anchor so it grows downward), and the hosting view sets `sizingOptions = []`
  so SwiftUI never drives the window size — without that the hosting view resizes the panel to fit
  content and the top edge drifts on the compact↔expanded swap. The panel auto-dismisses on
  `windowDidResignKey`.
- **Settings / About** — plain `NSWindow`s via `AuxWindowController` (in
  `Features/About/AboutView.swift`). SwiftUI `Settings` / `Window` scenes are unreliable for accessory
  apps, so this is deliberate.
- **Plugin workspaces** — the same `AuxWindowController`, reached only through
  `AppCore.showPluginWindow`. A plugin owns the hosted view and feature manager, while `AppCore`
  retains sole window ownership and closes the workspace from `onDisable`. The helper can opt a
  workspace into transparency, resizing and floating window level. Notes uses all three and requests
  content-driven height changes through `AppCore`, including its temporary list expansion, leaving
  frame ownership and activation routing centralized.
- **Plugin palette screens** — `PaletteMode.plugin(PluginID)` keeps list-oriented plugin flows inside
  the command palette. `PluginRegistry` supplies snapshots and actions; `RootPaletteView` and
  `PluginPaletteList` retain sole ownership of the search, selection, rows, scrolling and footer.
  Selection Tools uses this route for asynchronous AI translation and grammar states after it
  snapshots the frontmost app's Accessibility selection, before Spotter activates.

The app forces `.darkAqua` appearance globally; the Liquid Glass material is tuned for a dark surface
only.

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
