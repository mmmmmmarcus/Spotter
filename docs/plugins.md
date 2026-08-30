# Built-in feature registry

Spotter's system features and plugins are native Swift modules compiled into the signed application.
System features stay available, while plugins may be independently enabled. There is no runtime bundle
loader, JavaScript runtime or reflection-based discovery. Adding or removing feature source requires
rebuilding the app; once built, registry calls have the same performance characteristics as the rest
of Spotter.

This design keeps development boundaries clear for 20+ features while preserving static type checking,
Swift 6 actor isolation, dead-code optimization and predictable startup/security behavior.

## Directory layout

```text
Spotter/Plugins/
├── BuiltInPlugins.swift
├── Infrastructure/
│   ├── PluginTypes.swift
│   └── PluginRegistry.swift
├── CurrencyConversion/
│   ├── CurrencyConversionPlugin.swift
│   ├── CurrencyRateStore.swift
│   ├── CalcCurrency.swift
│   ├── CurrencyData.generated.swift
│   └── CurrencyConversionSettingsView.swift
├── Clipboard/
├── TextReplacement/
├── Note/
├── Quicklinks/
├── Commands/
├── AIChat/
├── EmojiSymbols/
├── WorldClock/
├── KillProcess/
├── ChangeCase/
├── SelectionTools/
├── ImageModification/
├── WindowManagement/
├── Mole/
├── OnePassword/
├── Coffee/
└── Screenshot/
```

`Infrastructure/` contains only the shared contract and registry. Every sibling feature directory owns
its registration factory, engine/store, views, settings and generated data. Feature code must not be
moved back into generic `Core/` or `Features/` buckets.

The folders are source-level modules inside the existing Spotter Xcode target, not separate frameworks
or Swift packages. `project.yml` includes `Spotter/` recursively, so XcodeGen compiles every plugin
directory automatically. `BuiltInPlugins.swift` remains a small, explicit catalog: this gives stable
Settings/query order and avoids reflection or filesystem scanning at launch.

## Ownership and registration

`AppCore` owns one `PluginRegistry`, preserving the single-owner rule. During `AppCore.init`,
`BuiltInPlugins.registrations(core:)` returns the ordered catalog and `AppCore` registers it. A
`PluginRegistration` is immutable capability metadata plus small `@MainActor` closures that refer back
to managers owned by `AppCore`; the registry never creates a second long-lived manager or singleton.

The shared integration points are:

- `Spotter/Plugins/Infrastructure/PluginTypes.swift` — Foundation-only IDs, metadata, permissions,
  shortcut action IDs and query-provider/result contracts.
- `Spotter/Plugins/Infrastructure/PluginRegistry.swift` — ordered registration, persisted enable
  state, lifecycle, settings factories, command routing and the enabled query-provider cache.
- `Spotter/Plugins/BuiltInPlugins.swift` — one ordered entry per compiled plugin.
- `Spotter/Features/Settings/SettingsRootView.swift` — the fixed System group, registered system
  feature rows and the registry-generated Plugins group.

Catalog order is user-visible in Settings and also determines query priority: the first enabled
provider that claims a query wins. Choose the order deliberately and make providers reject unrelated
input cheaply.

## Registration capabilities

Every registration supplies `metadata`, `defaultEnabled` and a standard Settings view. Everything else
is optional:

- `permissions` declares macOS grants the feature uses. System → Permissions derives its feature list
  from this metadata rather than maintaining another list.
- `shortcutActions` declares plugin-owned actions that can receive global shortcuts. Use a stable
  `PluginActionKey`; existing keys may specify a legacy `defaultsKey`, while new actions should use
  `PluginActionKey.standard(...)`. A genuinely primary action may supply `defaultShortcut`; it is
  seeded only once, never overwrites an existing/conflicting Spotter binding, and a later unbind is
  preserved by a separate seed marker.
- `launcherCommands` contributes signed in-process commands to `AppIndex`. Enabling or disabling the
  plugin adds or removes them without editing `CommandRegistry` or `AppCore.runCommand`.
- `launcherCommands.defaultVisible` defaults to true. Set it to false for secondary commands that
  should ship hidden but remain discoverable in System → Shortcuts. The one-time visibility seed does
  not overwrite a later user choice.
- `launcherCommands.iconFilePath` points a command row at a bundle to draw its icon from, instead of
  the SF Symbol tile commands normally get. A quicklink uses it to show the icon of the app that
  opens it.
- `dynamicLauncherCommands` contributes entries that change at runtime — such as a user's saved
  quicklinks or shell commands — and is re-read on every rebuild instead of captured once. Call
  `PluginRegistry.reloadDynamicCommands(for:)` whenever the underlying store changes; registration
  seeds the routing table so entries restored from disk are launchable before any change fires.
- `metadata.settingsPlacement` places a registration under Settings → System, Settings → Widgets or
  Settings → Plugins. System features may reuse the registry's command, shortcut and Settings routing
  without being presented as optional plugins. Widgets is one of them: the whole card strip is
  configured on a single System page, a section per card.
- `canDisable` (default true) pins a registration on. AI Chat and Widgets set it false
  because they are system features rather than optional plugins.
- `PluginCommandRegistration.actionKey` links a launcher row to its bindable shortcut so the row
  renders the recorded keycap. Pass the plugin's *existing* `shortcutActions` key rather than
  minting a second one: one `PluginActionKey` then serves the plugin's own Settings pane, its
  Settings ▸ Commands row, the launcher keycap, conflict detection, persistence and dispatch, so
  there is no way for the two to drift apart. Clipboard History is the reference — it reuses
  `.openClipboard`, whose `defaultsKey` is still the legacy `KeyboardShortcuts_toggleClipboard`
  (pinned by `Tools/commands-test.swift`, since renaming it would unbind every existing shortcut).
- `queryProvider` contributes a synchronous inline result provider.
- `paletteScreen` contributes a searchable result-list snapshot, primary row action, ⌘K menu actions
  and visible-only lifecycle to the shared command palette.
- `paletteScreen.livePlaceholder` overrides the static placeholder while the screen is open, for a
  step-by-step flow whose prompt changes between steps (Quicklinks' argument entry). Returning nil
  falls back to `placeholder`.
- `paletteScreen.adjustHours` opts a screen into ←/→ hour scrubbing while the query is empty (World
  Clock).
- `paletteScreen.observeChanges` wires the screen's manager into the registry's invalidation, so a
  background state change re-snapshots the visible list.
- `launcherDashboard` contributes one non-selectable view above the empty-query launcher rows. The
  registry enforces a single owner so the launcher layout and flat selection remain deterministic.
- `onEnable` and `onDisable` start and stop work. They run once at startup for enabled plugins and on
  later state transitions. Both must be idempotent.
- `readEnabled` and `writeEnabled` adapt a feature-owned state gate. Currency uses these because
  network consent must remain on `CurrencyRateStore`; ordinary plugins use the registry's
  bundle-scoped `UserDefaults` key.
- `exportsEnabledState` controls Settings backup. It defaults to true; set it false only for a system
  feature whose registry enable state is not user-configurable. Trusted
  v3 backup/sync snapshots intentionally include network-consent plugin states.
- Per-plugin **preferences** (not just the enable flag) sync by extending
  `SettingsBackup.PluginPrefs` — gather effective values, apply through the owning manager when the
  manager caches state. Change Case, Kill Process, Image Modification, Screenshot, Caffeinate,
  Window Management, Mole and 1Password are the current entries; a new plugin with preferences adds
  its own.

Disabled plugin commands disappear from launcher search, shortcut actions no-op, query providers are
removed from the hot-path cache, and `onDisable` stops ongoing work. A feature-specific entry point
should still guard `PluginRegistry.isEnabled` as defense in depth.

Search/filter → result-list → action plugins are palette screens by default. They register
`PluginPaletteScreenRegistration`, return `PluginPaletteSnapshot` values, and let
`PluginPaletteList` own the UI. A plugin must not duplicate the launcher's search field, keyboard
selection, row chrome, scrolling or footer in another window. Kill Process is the reference.

Dedicated workspaces are reserved for sustained document/canvas editing or complex multi-step flows
that cannot fit the launcher model. They use `AppCore.showPluginWindow(id:title:size:content:)`, which
keeps every `NSWindow` under `AuxWindowController`; Notes, the Change Case browser and the
Screenshot editor are the current examples. A seamless-title-bar window is drag-movable by its whole
background, which assumes every surface is chrome that real controls opt out of. A window hosting a
drawing canvas must pass `movableByBackground: false` and supply its own handle — a bare
`DragGesture` is not a control, so the window would otherwise move mid-stroke.
CPU, process, filesystem, image and AppleScript work must leave the main actor, returning only
`Sendable` values to an `AppCore`-owned manager.

## Query providers and performance

`PluginQueryProvider` is Foundation-only and synchronous:

```swift
struct ExampleQueryProvider: PluginQueryProvider {
    func evaluate(_ query: String, now: Date, calendar: Calendar) -> PluginQueryResult? {
        guard query.hasPrefix("example ") else { return nil }
        return PluginQueryResult(
            pluginID: .example,
            sectionTitle: "Example",
            expression: query,
            sourceBadge: nil,
            targetBadge: "Result",
            display: "Done",
            copyText: "Done",
            actionTitle: "Copy Result")
    }
}
```

The registry rebuilds a compact array of enabled providers only when registration or enablement
changes. Typing performs no settings lookup, reflection, disk read, network request or view creation;
it walks that array and stops at the first result. Queries are rejected at 256 characters. A provider
must apply a cheap syntax or prefix check before parsing and should keep immutable indexes in
`static let` storage. Expensive or network-backed state belongs in an `AppCore`-owned store and is
injected as a snapshot; never block the query hook.

The launcher shows one inline answer at flat selection index 0. `PaletteInlineResult` adapts calculator
and plugin results to the shared card without coupling Foundation-only engines to SwiftUI. Plugin
answers copy their payload but do not enter calculator history.

## Working with a plugin

The repository tracks the `spotter-plugin` project skill in two mirrored homes:
`.claude/skills/spotter-plugin/` for Claude Code (invoke `/spotter-plugin`) and
`.codex/skills/spotter-plugin/` for Codex (invoke `$spotter-plugin`). The skill creates, modifies,
migrates, debugs, or removes a plugin by applying the relevant lifecycle checklist and project
invariants. Because it is committed with the repository, it is available after cloning Spotter on
another computer; keep the two copies in sync when editing the skill.

The manual creation flow is:

1. Create `Spotter/Plugins/<PascalCaseName>/`; keep all plugin-specific source, views, settings and
   generated assets there.
2. Add a stable lowercase `PluginID` in
   `Spotter/Plugins/Infrastructure/PluginTypes.swift`. Never rename an ID after release because it is
   part of persisted settings.
3. Put business logic in the plugin directory. Prefer a Foundation-only engine with injected clock,
   calendar, filesystem path or network snapshot, plus a standalone harness in `Tools/`.
4. Choose the smallest shared surface: inline provider for one answer, palette screen for a searchable
   result list, or a justified dedicated workspace only for sustained editing/complex multi-step work.
5. Add `<Name>Plugin.swift` with a `@MainActor` registration factory. If the plugin needs a long-lived
   manager, add exactly one owner property to `AppCore` and have the factory capture that instance.
6. Add a Settings view built from `SettingsPane`, `SettingsCard` and `SettingsRow`. Its first card is
   conventionally `Plugin` and contains the enable switch bound to `PluginRegistry`.
7. Add one factory call to the ordered array in `Spotter/Plugins/BuiltInPlugins.swift`. Do not add
   reflection, directory scanning or another registry.
8. If it runs work, make lifecycle methods idempotent. Palette-only work starts/stops in screen
   `onOpen`/`onClose`; `onDisable` stops it too and returns an active mode to `.launcher`.
9. If it reaches the network, follow `CurrencyRateStore`: ship off, show explicit provider/cadence/data
   consent, re-check consent before and after every `await`, use a private cacheless session, delete
   cached data on revoke, and include the consent state in the trusted v3 backup/sync snapshot.
10. Update the relevant subsystem documentation, run the feature and full standalone harnesses, run
   `xcodegen generate`, and complete an Xcode build.

Example registration factory:

```swift
@MainActor
enum ExamplePlugin {
    static func registration(core: AppCore) -> PluginRegistration {
        let open = { core.openExample() }

        return PluginRegistration(
            metadata: PluginMetadata(
                id: .example,
                name: "Example",
                summary: "Does one bounded thing.",
                systemImage: "sparkles",
                tint: .purple),
            defaultEnabled: true,
            permissions: [.accessibility],
            shortcutActions: [PluginActionRegistration(key: exampleAction, perform: open)],
            launcherCommands: [
                PluginCommandRegistration(
                    id: "command:example",
                    name: "Open Example",
                    systemImage: "sparkles",
                    perform: open)
            ],
            queryProvider: ExampleQueryProvider(),
            onEnable: start,
            onDisable: stop,
            settingsView: { AnyView(ExampleSettingsView()) })
    }
}
```

Plugin commands are signed application actions. The Commands plugin is the user-authored
shell-command feature; do not use shell commands as an internal plugin API.

## System features

- **AI Chat** (`Spotter/Plugins/AIChat/`) — an always-available system feature shown under
  Settings → System. It reuses registry infrastructure for Settings routing, commands, permissions
  and shortcuts, but cannot be disabled and does not export an enable state. It remains inert without
  the shared OpenRouter key for Spotter-hosted replies. Tab sends a typed query through OpenRouter;
  Shift-Tab opens the same query at `https://chatgpt.com/?q=…` in the default browser. Selected-text
  definition and grammar checks start follow-up-ready conversations. The launcher's final query
  destination rows reuse both paths without adding registry commands.
- **Widgets** (`Spotter/Plugins/DashboardWidgets/`) — an always-available system feature that owns
  the launcher dashboard and is configured on one System page. It adds five square cards above the
  empty launcher — Clock, Uptime, Device Battery, Calendar and File Info — switched on or off in that
  page's Show list and **dragged into order in the palette itself**. Weather has no card of its own:
  it is three complications on the clock face, and choosing a city is what turns it on. The clock
  supports an explicit time zone; Calendar can filter by EventKit account and exclude all-day events.
  Calendar data is permission-gated, File Info is Automation-gated, and Weather and Uptime are
  consent-gated.

## Current plugins

- **Currency Conversion** (`Spotter/Plugins/CurrencyConversion/`) — the one plugin still disabled
  by default: its enable switch is the network-consent gate, so shipping it on would grant network
  access without consent;
  `CurrencyRateStore` owns consent and daily rates.
- **Clipboard** (`Spotter/Plugins/Clipboard/`) — enabled by default; disabling stops pasteboard
  polling while preserving history.
- **Text Replacement** (`Spotter/Plugins/TextReplacement/`) — enabled by default; expands
  user-defined prefix/keyword triggers into text in the active app through an Accessibility-gated
  event tap without storing typing history or using the clipboard.
- **Notes** (`Spotter/Plugins/Note/`) — enabled by default; unlimited local notes in a translucent,
  content-height floating Markdown editor that opens 440 points wide with a 20-point window radius
  and an inset overlay list, plus `Open Notes` and `New Note` actions. Selected text has a native
  editing and visible H1/H2/H3/Text/list format section, wrapped list content uses marker-width
  hanging indents, and a background-only transparency preference syncs through trusted Settings.
  Empty Notes are discarded when the window closes. Its consented private CloudKit sync replicates
  each Note and deletion independently from automatic Settings Sync.
- **Quicklinks** (`Spotter/Plugins/Quicklinks/`) — enabled by default; user-saved links, files and
  deep links published as launcher entries through `dynamicLauncherCommands`, with `{argument}`
  placeholders collected one step at a time on a palette screen using `livePlaceholder`.
- **Commands** (`Spotter/Plugins/Commands/`) — enabled by default; provides 30 read-only built-in
  macOS actions and publishes the user's editable persisted shell commands through
  `dynamicLauncherCommands`. Disabling it preserves custom commands and every binding, removes both
  command sources from the launcher, and makes their global shortcuts no-op. Commands never create
  background-task rows; successful invisible work reports through the brief command HUD, while
  failures preserve their detailed alerts. Work already running is not terminated when Commands is
  disabled.
- **Emoji & Symbols** (`Spotter/Plugins/EmojiSymbols/`) — enabled by default; lazily loads its
  Foundation catalog when enabled.
- **World Clock** (`Spotter/Plugins/WorldClock/`) — enabled by default; local-only, backed by macOS
  IANA time-zone data. Queries compare a city with local system time and support hourly keyboard
  adjustment; its launcher screen shows a user-managed saved-city list.
- **Uptime** (`Spotter/Plugins/Uptime/`) — ships **off**; its switch is the consent act for counting
  input, so the registration reads and writes the enabled state through `UptimeStore` and exports
  none of it. A palette screen shows today's session, key presses and mouse clicks.
- **Kill Process** (`Spotter/Plugins/KillProcess/`) — enabled by default; launcher-native palette screen backed by an
  on-demand `ps` snapshot, with CPU/memory sorting, grouping, filtering and safe process actions.
- **Change Case** (`Spotter/Plugins/ChangeCase/`) — enabled by default; 21 local text transforms, selected-text/clipboard
  fallback, pinned and recent cases, copy/paste actions and hidden-by-default direct commands.
- **Selection Tools** (`Spotter/Plugins/SelectionTools/`) — enabled by default; captures selected
  text and opens a Google Search in the default browser. Its former AI actions now belong to AI Chat.
- **Image Modification** (`Spotter/Plugins/ImageModification/`) — enabled by default; local Core Image, Vision and
  ImageIO commands with Finder/clipboard/file input and explicit output handling; Convert Image uses
  a searchable target-format palette before any conversion begins, then every operation reports
  batch progress through the launcher background-task surface.
- **Window Management** (`Spotter/Plugins/WindowManagement/`) — enabled by default; 30 commands
  covering halves, quarters, thirds, sizing, display moves and fullscreen, on a pure geometry engine
  with an AX mover.
- **Mole** (`Spotter/Plugins/Mole/`) — enabled by default (idle until the CLI is installed); a
  launcher front end for the Mole CLI with no Terminal hand-off — the installer screen is Spotter's
  own scan and native Trash. Launcher app rows offer **Uninstall with Mole**, which confirms first
  and then resolves the exact copy by path and uninstalls as one background task.
  Status, clean, optimize, purge, uninstall, disk analysis and history all render as palette screens
  off a menu hub; state-changing runs preview first, go through one confirmed funnel, then return to
  the launcher as persistent background-task rows. Nothing hands off to Terminal.
- **1Password** (`Spotter/Plugins/OnePassword/`) — enabled by default (idle until the `op` CLI is
  installed); a palette screen listing 1Password items whose ↵ opens an in-palette item view —
  fields masked until revealed, copied or pasted concealed — with open-in-app/browser actions and a
  hidden Generate Password command. Metadata comes from `op item list`; secrets are fetched only on
  an explicit action, held in memory only while a view is open, copied concealed so no clipboard
  manager records them, and cleared after 90 seconds unless replaced. 1Password 8's own
  authorization prompt is the gate; nothing is persisted.
- **Caffeinate** (`Spotter/Plugins/Coffee/`, display-renamed from Coffee; the id stays `coffee` so
  persisted state survives) — enabled by default; keeps the Mac awake indefinitely,
  for a duration, or while a chosen app runs, via a `caffeinate` process the plugin owns.
- **Screenshot** (`Spotter/Plugins/Screenshot/`) — enabled by default; Option-Z (seeded once and
  user-editable), the launcher command and the menu-bar menu open the same non-activating crosshair
  overlay without taking focus from the current app. A left drag captures a region through a
  display-scoped ScreenCaptureKit filter, a right click captures the window under the pointer, and
  a per-display Liquid Glass button beside the Dock captures that whole screen; Space cycles the
  session's output between screenshot, OCR text and a hex colour sample. Images land on the system
  clipboard; capture is one-shot and protected by macOS Screen Recording permission. The mode
  pointers are rendered once from SF Symbols with a one-point white outline and subtle drop shadow.
  The display stays visually unchanged; a one-alpha-step hit surface keeps the panel interactive,
  while a dragged region receives an exact 5% overlay. A default-on synced preference gives the
  overlay, selection border and output pixels a 4px radius.
  The overlay architecture is adapted from Capso under BSL 1.1; no Capso service or idle process is
  loaded.
Detailed internals: [Clipboard](clipboard.md), [Emoji](emoji.md), [World Clock](world-clock.md), [Uptime](uptime.md), [Widgets](widgets.md), [Kill Process](kill-process.md), [Change Case](change-case.md),
[Selection Tools](selection-tools.md), [Image Modification](image-modification.md),
[Window Management](window-management.md), [built-in Commands](system-commands.md),
[Mole](mole.md), [1Password](1password.md), [Caffeinate](coffee.md), [Quicklinks](quicklinks.md), [AI Chat](ai-chat.md),
[Notes](notes.md), [Text Replacement](text-replacement.md), [Screenshot](screenshot.md),
and [File Search](file-search.md).
