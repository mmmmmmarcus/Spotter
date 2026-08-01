# Built-in plugins

Spotter plugins are native Swift feature modules compiled into the signed application. Each plugin is
independently organized and enabled, but there is no runtime bundle loader, JavaScript runtime or
reflection-based discovery. Adding or removing plugin source requires rebuilding the app; once built,
plugin calls have the same performance characteristics as the rest of Spotter.

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
├── EmojiSymbols/
├── WorldClock/
├── KillProcess/
├── ChangeCase/
├── ImageModification/
└── QuickTime/
```

`Infrastructure/` contains only the shared contract and registry. Every sibling plugin directory owns
its registration factory, engine/store, views, settings and generated data. Plugin code must not be
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
- `Spotter/Features/Settings/SettingsRootView.swift` — System and Plugins sidebar groups generated
  from the registry.

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
  `PluginActionKey.standard(...)`.
- `launcherCommands` contributes signed in-process commands to `AppIndex`. Enabling or disabling the
  plugin adds or removes them without editing `CommandRegistry` or `AppCore.runCommand`.
- `launcherCommands.defaultVisible` defaults to true. Set it to false for secondary commands that
  should ship hidden but remain discoverable in System → Shortcuts. The one-time visibility seed does
  not overwrite a later user choice.
- `queryProvider` contributes a synchronous inline result provider.
- `onEnable` and `onDisable` start and stop work. They run once at startup for enabled plugins and on
  later state transitions. Both must be idempotent.
- `readEnabled` and `writeEnabled` adapt a feature-owned state gate. Currency uses these because
  network consent must remain on `CurrencyRateStore`; ordinary plugins use the registry's
  bundle-scoped `UserDefaults` key.
- `exportsEnabledState` controls Settings backup. It defaults to true. Network-consent plugins must set
  it to false so importing a backup cannot grant network access.

Disabled plugin commands disappear from launcher search, shortcut actions no-op, query providers are
removed from the hot-path cache, and `onDisable` stops ongoing work. A feature-specific entry point
should still guard `PluginRegistry.isEnabled` as defense in depth.

Plugin workspaces use `AppCore.showPluginWindow(id:title:size:content:)`. This keeps every `NSWindow`
under the existing `AuxWindowController`; plugins own their SwiftUI content but never create window
singletons or SwiftUI `Window` scenes. CPU, process, filesystem, image and AppleScript work must leave
the main actor, returning only `Sendable` values to an `AppCore`-owned manager.

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

## Adding a plugin

The repository tracks a project skill at `.codex/skills/spotter-new-plugin/`. In Codex, invoke
`$spotter-new-plugin` with the plugin name and behavior; the skill follows this checklist and the
project invariants. Because it is committed with the repository, it is available after cloning Spotter
on another computer.

The manual flow is:

1. Create `Spotter/Plugins/<PascalCaseName>/`; keep all plugin-specific source, views, settings and
   generated assets there.
2. Add a stable lowercase `PluginID` in
   `Spotter/Plugins/Infrastructure/PluginTypes.swift`. Never rename an ID after release because it is
   part of persisted settings.
3. Put business logic in the plugin directory. Prefer a Foundation-only engine with injected clock,
   calendar, filesystem path or network snapshot, plus a standalone harness in `Tools/`.
4. Add `<Name>Plugin.swift` with a `@MainActor` registration factory. If the plugin needs a long-lived
   manager, add exactly one owner property to `AppCore` and have the factory capture that instance.
5. Add a Settings view built from `SettingsPane`, `SettingsCard` and `SettingsRow`. Its first card is
   conventionally `Plugin` and contains the enable switch bound to `PluginRegistry`.
6. Add one factory call to the ordered array in `Spotter/Plugins/BuiltInPlugins.swift`. Do not add
   reflection, directory scanning or another registry.
7. If it runs work, make lifecycle methods idempotent and stop timers/tasks in `onDisable`. If it owns
   a palette mode, return the palette to `.launcher` when disabling it.
8. If it reaches the network, follow `CurrencyRateStore`: ship off, show explicit provider/cadence/data
   consent, re-check consent before and after every `await`, use a private cacheless session, delete
   cached data on revoke, and exclude the consent state from backup.
9. Update the relevant subsystem documentation, run the feature and full standalone harnesses, run
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

Plugin commands are signed application actions. System → Custom Commands remains the user-authored
shell-command feature; do not use shell commands as an internal plugin API.

## Current plugins

- **Currency Conversion** (`Spotter/Plugins/CurrencyConversion/`) — disabled by default;
  `CurrencyRateStore` owns consent and daily rates.
- **Clipboard** (`Spotter/Plugins/Clipboard/`) — enabled by default; disabling stops pasteboard
  polling while preserving history.
- **Emoji & Symbols** (`Spotter/Plugins/EmojiSymbols/`) — enabled by default; lazily loads its
  Foundation catalog when enabled.
- **World Clock** (`Spotter/Plugins/WorldClock/`) — enabled by default; local-only, backed by macOS
  IANA time-zone data. Queries include `SF time now`, `time in Tokyo`, `London time` and `上海时间`.
- **Kill Process** (`Spotter/Plugins/KillProcess/`) — on-demand `ps` snapshot with CPU/memory sorting,
  app-helper grouping, filtering, terminate/force-terminate/restart actions and confirmations.
- **Change Case** (`Spotter/Plugins/ChangeCase/`) — 21 local text transforms, selected-text/clipboard
  fallback, pinned and recent cases, copy/paste actions and hidden-by-default direct commands.
- **Image Modification** (`Spotter/Plugins/ImageModification/`) — local Core Image, Vision and ImageIO
  batch operations with Finder/clipboard/file input and explicit output handling.
- **QuickTime Recording** (`Spotter/Plugins/QuickTime/`) — three on-demand AppleScript actions for
  screen, audio and movie recording; requires Automation only when a command runs.

Detailed internals: [Kill Process](kill-process.md), [Change Case](change-case.md),
[Image Modification](image-modification.md), and [QuickTime Recording](quicktime.md).
