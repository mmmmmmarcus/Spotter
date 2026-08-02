---
name: spotter-new-plugin
description: Create or extend a native built-in Spotter plugin under Spotter/Plugins, including its registration, palette-first UI, lifecycle, settings, permissions, launcher commands, shortcuts, inline query provider, tests, Xcode project regeneration, and documentation. Use whenever adding a new Spotter plugin, converting an existing feature into a plugin module, or adding plugin capabilities to the Spotter macOS codebase.
---

# Spotter New Plugin

Create production-quality native Swift plugins that compile into Spotter. Do not introduce runtime
bundles, JavaScript plugins, reflection-based discovery, long-lived helper processes, or external
plugin loading.

## Establish context

1. Read `AGENTS.md` completely.
2. Read `docs/plugins.md` and `docs/architecture.md` completely.
3. Read `docs/ui.md` before creating or changing a Settings view or palette result.
4. Read the subsystem documents and one existing plugin closest to the requested capability.
5. Inspect the dirty worktree and preserve unrelated user changes.

Use `Spotter/Plugins/WorldClock/` as the minimal query-plugin example, Clipboard as the lifecycle and
permission example, Kill Process as the launcher-style palette-screen example, and Currency
Conversion as the consent-gated network example.

## Define the module boundary

Create one self-contained folder:

```text
Spotter/Plugins/<PascalCaseName>/
├── <Name>Plugin.swift
├── <Name>Engine.swift              # when pure query/business logic exists
├── <Name>SettingsView.swift
└── supporting stores/views/data    # only files owned by this plugin
```

Keep shared infrastructure in `Spotter/Plugins/Infrastructure/`. Change infrastructure only when the
new feature exposes a genuinely reusable capability missing from `PluginRegistration`.

Keep long-lived managers owned by `AppCore`; registration closures may refer back to those managers.
Do not add a plugin singleton. Keep pure engines Foundation-only and inject clocks, calendars,
filesystem paths, network snapshots, and other external inputs.

## Choose the surface

**Palette first is mandatory.** A plugin whose interaction is search/filter → result rows → primary
action/Actions menu must register a `PluginPaletteScreenRegistration` and render through the shared
`PluginPaletteList`. It must not open an `NSWindow`, `NSPanel`, SwiftUI `Window`, custom search field,
native `List`, or parallel footer. The shared palette owns query focus, flat selection, keyboard
navigation, row appearance, edge dissolve and the ⌘K Actions menu. Kill Process is the reference.

Use an inline `PluginQueryProvider` when one query produces one answer. Use a dedicated plugin window
only when the task is genuinely a sustained document/canvas editor or a complex multi-step workspace
that cannot fit the launcher interaction model; Notes and Image Modification are examples. Document
that justification. Even then, call `AppCore.showPluginWindow` and never create a window owner.

## Register the plugin

1. Add a permanent lowercase-hyphenated `PluginID` in
   `Spotter/Plugins/Infrastructure/PluginTypes.swift`.
2. Implement `<Name>Plugin.registration(core:)` in the plugin folder. Omit `core` when no shared
   manager or app action is needed.
3. Add exactly one ordered catalog entry to `Spotter/Plugins/BuiltInPlugins.swift`.
4. Supply metadata, `defaultEnabled`, and `settingsView`.
5. Add only the required capabilities:
   - `permissions` for macOS grants.
   - `shortcutActions` for globally bindable actions.
   - `launcherCommands` for signed in-process launcher commands.
   - `queryProvider` for inline launcher answers.
   - `paletteScreen` for searchable result lists and row actions inside the shared launcher shell.
   - `onEnable` and `onDisable` for timers, tasks, monitors, and mode cleanup.
   - `readEnabled` and `writeEnabled` only when the owning store must control state.

Make lifecycle closures idempotent. A disabled plugin must stop ongoing work, disappear from launcher
commands and query routing, and make shortcut actions no-op. Preserve legacy preference and hotkey keys
when migrating an existing feature.

Use `defaultVisible: false` for secondary/direct launcher commands that should ship hidden. Give each
one a stable `PluginActionKey` so System → Shortcuts can reveal it or bind it without adding central
command cases. A palette-screen `onOpen`/`onClose` owns polling and other visible-only work and must be
idempotent; `onDisable` must also return an active plugin palette mode to `.launcher`.

## Build the Settings view

Use `SettingsPane`, `SettingsCard`, `SettingsRow`, `SettingsDivider`, and `Theme` tokens. Put a
`Plugin` card first with an enable switch bound to `PluginRegistry`. Do not add a `SettingsTab` case:
the Plugins sidebar is registry-driven.

Declare permission use in registration so System → Permissions stays registry-driven. Keep System →
Custom Commands for user-authored shell commands; plugin launcher commands are native registered
actions, not shell-based internal APIs.

## Add query behavior

Conform a Foundation-only value to `PluginQueryProvider`. Apply a cheap syntax reject before parsing,
perform no disk or network reads in `evaluate`, honor the 256-character bound, and return one
`PluginQueryResult`. Inject `now` and `calendar`. Keep immutable lookup indexes in `static let` storage.

The first enabled provider in catalog order wins and occupies flat palette selection index 0. Do not
add another independently selected inline row or break the palette selection invariant.

## Handle network access

For any networked plugin, follow `CurrencyRateStore` exactly: ship disabled, obtain explicit consent,
name provider/cadence/transmitted data, re-check consent before and after every `await`, use a private
cacheless ephemeral `URLSession`, delete cached data on revoke, and set
`exportsEnabledState = false`. Never put network consent in `AppSettings` or Settings backup.

## Test and document

1. Add or update a standalone `Tools/<plugin>-test.swift` harness for pure logic.
2. Update `docs/development.md` with its exact compile command.
3. Update `docs/plugins.md`, the relevant subsystem document, `docs/architecture.md` when ownership
   changes, and `docs/ui.md` when a new surface is introduced.
4. Update `AGENTS.md` when the module adds a generated file, purity boundary, or critical invariant.
5. Update generator output paths when generated data moves into the plugin folder; never edit generated
   Swift data by hand.
6. Search the repository for stale paths and old central enum/switch cases.

Run the new harness, every affected existing harness, `xcodegen generate`, and a Debug Xcode build.
If XcodeGen is unavailable, use a temporary official XcodeGen binary and do not hand-edit the project.
Report the created module, registered capabilities, persistence/consent behavior, tests, and build
result.
