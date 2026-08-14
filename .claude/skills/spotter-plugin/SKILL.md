---
name: spotter-plugin
description: Create, modify, refactor, migrate, debug, test, or remove native built-in Spotter plugins under Spotter/Plugins. Use for any Spotter plugin lifecycle work, including registration, palette and window surfaces, settings, permissions, launcher commands, shortcuts, query providers, managers and stores, persistence, network consent, tests, project regeneration, documentation, or complete plugin deletion.
---

# Spotter Plugin

Maintain production-quality native Swift plugins compiled into Spotter. Cover the complete plugin
lifecycle: create, modify, migrate, troubleshoot, or remove. Do not introduce runtime bundles,
JavaScript plugins, reflection-based discovery, long-lived helper processes, or external loading.

## Establish context

Before changing a plugin:

1. Read `AGENTS.md` completely (skip when it is already in context, e.g. via `CLAUDE.md`).
2. Read `docs/plugins.md` and `docs/architecture.md` completely.
3. Read the plugin's subsystem document and its source folder completely when modifying or removing it.
4. Read `docs/ui.md` before changing a Settings view, palette result, or plugin workspace.
5. Inspect the dirty worktree and preserve unrelated user changes.
6. Search for the plugin ID, registration factory, action keys, persistence keys, manager/store,
   tests, generators, documentation, and project references before deciding the edit scope.

Use these reference implementations:

- `WorldClock/` for a query provider, persisted store, and palette screen.
- `Clipboard/` for lifecycle and permissions.
- `KillProcess/` for a process-action palette screen.
- `CurrencyConversion/` for consent-gated network access.
- `Note/` for a justified sustained-workspace window.
- `ImageModification/` for direct commands and off-main processing.

## Preserve the plugin architecture

Keep each plugin self-contained:

```text
Spotter/Plugins/<PascalCaseName>/
├── <Name>Plugin.swift
├── <Name>Engine.swift              # when pure query/business logic exists
├── <Name>SettingsView.swift
└── supporting stores/views/data    # only files owned by this plugin
```

Keep shared contracts in `Spotter/Plugins/Infrastructure/` and the explicit ordered catalog in
`Spotter/Plugins/BuiltInPlugins.swift`. Change infrastructure only for a genuinely reusable missing
capability, not to avoid a small plugin-local implementation.

Keep long-lived managers and stores owned by `AppCore`; registration closures may refer to them.
Never add a plugin singleton or a second registry. Keep pure engines Foundation-only and inject
clocks, calendars, filesystem paths, network snapshots, and other external inputs. Preserve Swift 6
actor boundaries and push CPU, process, filesystem, image, AppleScript, and network work off the main
actor.

## Choose the operation

### Create a plugin

1. Define one stable lowercase-hyphenated `PluginID` in
   `Spotter/Plugins/Infrastructure/PluginTypes.swift`.
2. Create one self-contained plugin folder and a `@MainActor` registration factory. Omit `core` from
   `registration(core:)` only when the plugin needs no manager or app action.
3. Add exactly one ordered factory call to `BuiltInPlugins.registrations(core:)`.
4. Supply metadata, `defaultEnabled`, and a standard Settings view with its `Plugin` enable card first.
5. Add only the capabilities the plugin actually needs: permissions, shortcuts, launcher commands,
   query provider, palette screen, lifecycle hooks, or feature-owned enabled-state adapters.
6. Add a pure-logic harness, subsystem documentation, and the required development test command.

Use stable `PluginActionKey` values. Set `defaultVisible: false` for secondary or direct commands that
should ship hidden while remaining available in System → Shortcuts. Make lifecycle closures
idempotent. Disabling must stop work, remove commands and query routing, make shortcuts no-op, close
plugin UI, and return an active plugin palette mode to `.launcher`.

### Modify or migrate a plugin

1. Read its registration, engine, manager/store, views, settings, tests, and documentation before
   editing. State the requested behavior delta and identify the smallest owning layer.
2. Preserve the existing `PluginID`, action keys, hotkey defaults keys, preference keys, and persisted
   data format unless the user explicitly requests a breaking migration.
3. Change business behavior in the engine or manager rather than adding state to SwiftUI views.
   Change only plugin-local code unless multiple plugins genuinely need a shared capability.
4. When adding or removing a capability, update registration, lifecycle cleanup, Settings, commands,
   shortcuts, permissions, tests, and documentation together. Delete dead paths rather than leaving
   compatibility branches with no supported caller.
5. For stored-data schema changes, implement a bounded one-time migration and test both old and new
   representations. Persistence remains keyed by `Bundle.main.bundleIdentifier`.
6. Search for stale behavior descriptions, settings keys, action routes, enum cases, and switch
   branches after the edit.

### Remove a plugin

Treat removal as an exact, repository-wide cleanup:

1. Resolve the complete removal set before deleting anything: plugin folder, catalog entry,
   `PluginID`, action keys, `AppCore` ownership and wiring, palette/window routes, permissions,
   settings, tests, generators, generated assets, documentation, and project references.
2. Remove the catalog entry and lifecycle/UI routes, then remove plugin-owned source. Remove shared
   infrastructure only when a repository-wide search proves no remaining consumer exists.
3. Remove the `PluginID` and action declarations only after their callers are gone. Never renumber or
   rename surviving IDs and never reuse a removed ID for a different feature.
4. Preserve existing user data and preference keys by default. Purge or migrate stored data only when
   the user explicitly requests it; keep any purge scoped to the exact plugin and bundle identifier.
5. Remove obsolete harness commands, feature docs, generated-output rules, catalog descriptions, and
   critical invariants that apply only to the removed plugin.
6. Run repository-wide stale-reference searches before regenerating the project. Do not leave a
   disabled stub, empty folder, dead compatibility layer, or second implementation.

## Choose the interaction surface

**Palette first is mandatory.** Search/filter → result rows → primary action/Actions menu plugins use
`PluginPaletteScreenRegistration` and the shared `PluginPaletteList`. Do not create another window,
search field, native `List`, row chrome, footer, or keyboard-selection model. The shared palette owns
query focus, flat selection, navigation, scrolling, edge dissolve, and the ⌘K Actions menu.

Use `PluginQueryProvider` when one query produces one inline answer. The Foundation-only provider must
reject unrelated syntax cheaply, honor the 256-character bound, do no disk or network reads during
`evaluate`, inject `now` and `calendar`, and return at most one result. The first enabled provider in
catalog order wins at flat selection index 0.

Use a dedicated workspace only for a sustained editor/canvas or a complex multi-step flow that cannot
fit the launcher. Document the justification, call `AppCore.showPluginWindow`, and leave window
ownership with `AuxWindowController`.

## Registration, Settings, and permissions

Use `PluginRegistration` as the only integration contract:

- `permissions` for macOS grants.
- `shortcutActions` for globally bindable actions.
- `launcherCommands` for signed in-process commands.
- `queryProvider` for inline answers.
- `paletteScreen` for shared-palette result lists and row actions.
- `onEnable` and `onDisable` for timers, tasks, monitors, and cleanup.
- `readEnabled` and `writeEnabled` only when the owning store must gate its own state.
- `exportsEnabledState = false` for consent flags or any state a backup must not grant.

Build Settings with `SettingsPane`, `SettingsCard`, `SettingsRow`, `SettingsDivider`, and `Theme`
tokens. Do not add a `SettingsTab`; the Plugins sidebar is registry-driven. Declare permissions in
registration so System → Permissions remains registry-driven. Keep plugin commands out of System →
Custom Commands, which is only for user-authored shell commands.

## Handle network access

Follow `CurrencyRateStore` exactly for any networked plugin: ship disabled, obtain explicit consent,
name the provider/cadence/transmitted data, re-check consent before and after every `await`, use a
private cacheless ephemeral `URLSession`, delete cached data when consent is revoked, and exclude
consent from Settings backup. Model the safe/off state as the default at every entry point.

## Test, document, build, and install

For every create, modification, migration, or removal:

1. Add, update, or remove `Tools/<plugin>-test.swift` with the pure engine/store sources it compiles.
2. Update `docs/development.md` test commands, `docs/plugins.md`, and the subsystem document. Update
   `docs/architecture.md` for ownership changes, `docs/ui.md` for surface changes, and `AGENTS.md` for
   generated files, purity boundaries, or critical invariants.
3. Update generator paths when generated data moves; never hand-edit generated Swift data.
4. Run the affected standalone harnesses plus any shared harness whose source changed.
5. Run `xcodegen generate` after source or `project.yml` changes; never hand-edit the generated project.
6. Complete a signed Debug Xcode build. After it succeeds and validation passes, replace only
   `/Applications/Spotter.app` and relaunch it according to `AGENTS.md`. Never remove the working
   installed app before a valid staged build exists.
7. Report the lifecycle operation, capabilities and persistence impact, removed or migrated state,
   tests, build result, and installed-app status.

Before finishing, search for stale plugin names, IDs, paths, preference keys, action keys, commands,
documentation, and generated-project references. Preserve unrelated dirty-worktree changes.
