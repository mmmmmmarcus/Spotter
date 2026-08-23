# Hotkeys (in-house, zero dependencies)

Persistence keys are rename-stable by design: a plugin's display name may change while its
`PluginID` raw value must not — Caffeinate still binds under
`KeyboardShortcuts_plugin.coffee.<action>` because the id stayed `coffee` through the rename.

`Core/HotKey/` holds:

- `KeyShortcut` — Sendable model, Carbon keycode + modifiers, layout-aware glyphs via `UCKeyTranslate`.
- `HotKeyBinding` — the persisted binding enum; a `.combo` case encodes as the bare `KeyShortcut`
  record so every pre-double-tap binding and backup still reads.
- `HotKeyCenter` — the Carbon `RegisterEventHotKey` layer, pausable.
- `DoubleTapDetector` / `DoubleTapModifier` — pure, clock-injected recognition of "tap a lone
  modifier twice" (both compile into `Tools/hotkey-test.swift`).
- `DoubleTapMonitor` — the listen-only event tap that feeds it, installed only while something is bound.
- `HyperKey` / `HyperKeyTap` — the Hyper Key: an HID-level Caps Lock remap owned by
  `AppCore.hyperKeyTap`, released in `applicationWillTerminate`, configured in General Settings and
  synced as four settings fields (`hyperKey`, `hyperKeyIncludesShift`, `hyperKeyQuickPress`,
  `hyperKeyReplacesGlyph`). It deliberately keeps running while the recorder pauses Carbon, because
  the recorder relies on the tap's rewritten flags to capture Hyper shortcuts.

`HotKeyManager` owns them all: persistence, conflict lookup, and dispatch.

## Two engines, one binding

A `HotKeyBinding` is either a `.combo` (a Carbon registration) or a `.doubleTap` of ⌘/⌃/⌥/⇧ — Carbon
cannot register a modifier-only shortcut at all, so double-taps run through an event tap instead. Both
kinds share conflict detection (comparing whole bindings, so two actions can never claim the same
modifier) and both render through `HotKeyBinding.keycaps`, which is why a double-tap shows as its
doubled glyph everywhere a combo shows its caps.

A tap fires on the second *release*, so the modifier is already up when the action runs — the palette
never opens with a phantom ⌘ held. A press longer than 0.25 s, a gap over 0.30 s, a second modifier
joining, or any key/click in between all cancel it. Caps Lock is deliberately excluded (it belongs to
the Hyper Key) and so is `fn`, which isn't a real modifier on every keyboard.

## Transient keys

`holdTransientKey(id:shortcut:onKeyDown:)` claims a bare system key for as long as a short-lived
surface is on screen — the screenshot preview thumbnail's Return, whose panel never becomes key, and
Escape while a capture selection is up, which cannot rely on the overlay holding keyboard focus. A transient key is deliberately *not* a
binding: nothing persists, it never appears in Settings, it takes no part in conflict detection, and
the caller must release it. Carbon consumes the key while it is held, so hold one only while its
surface is actually visible, and release it on every dismissal path. The recorder's pause covers
transient keys too, so recording a shortcut can never fire one.

## Persistence

Shortcuts persist as JSON strings under `KeyboardShortcuts_<name>` UserDefaults keys — a **legacy
format** from the removed KeyboardShortcuts package, kept so old bindings survive. The App Launcher
holds two independent actions, `togglePalette` and `togglePaletteBackup`, dispatching to the same
toggle — either binding summons the palette, and shared conflict detection keeps them off the same
shortcut. The set of bound
bundle IDs lives in `boundAppBundleIDs` and is re-registered on launch. System Settings panes use
`boundPaneBundleIDs`; custom commands use their stable UUIDs in `boundCustomCommandIDs`, and
quicklinks theirs in `boundQuicklinkIDs`. Built-in
plugins expose stable `PluginActionKey` values through `PluginRegistry`; new keys use the
`plugin.<plugin-id>.<action-id>` namespace while migrated actions may retain legacy defaults keys.

**Every launcher row that can be bound, is.** A row in Settings ▸ Shortcuts shows a recorder exactly
when `AppEntry.hotKeyAction` resolves, and each command kind resolves through its own case:

| Row | Action | Key |
| --- | --- | --- |
| A plugin's command | `.plugin(PluginActionKey)` | `plugin.<plugin-id>.<action-id>` |
| A custom command | `.customCommand(id:)` | `customCommandHotkey.<uuid>` |
| A quicklink | `.quicklink(id:)` | `quicklinkHotkey.<uuid>` |
| Spotter's own built-ins | `.builtInCommand(CommandID)` | `builtInCommandHotkey.<slug>` |

`CommandID` owns the identity and metadata of the built-ins and lives in its own `Core/CommandID.swift`
so the command-to-shortcut mapping compiles into `Tools/commands-test.swift` without dragging
`AppEntry` in; `CommandRegistry` only turns those into launcher entries. The harness pins the slugs,
because a collision would silently make two commands share one binding and a rename would unbind
whatever the user had set. Unlike the per-item kinds, the built-in set is fixed and fully known at
launch, so it needs no bound-ID index — every case is simply registered, and `register` no-ops
without a saved shortcut.

The two per-item kinds are indexed because they can disappear: on launch a binding whose custom
command or quicklink no longer exists is deleted rather than re-registered, and deleting either from
the UI drops its binding, favorite, alias and learned ranking in the same step.

Disabling a plugin makes registry dispatch a no-op while preserving the Carbon registration and saved
binding. Re-enabling resumes the action without creating plugin-specific branches in `HotKeyManager`.
Plugins with several commands expose a stable action key per command, so each can be bound directly.
Screenshot's `Capture Screenshot` action seeds Option-Z exactly once on a fresh install. The seed
marker is separate from the binding so a later clear remains unbound instead of returning after
relaunch; an existing Spotter conflict prevents the seed rather than stealing another action's key.
Carbon registration failures are mirrored to Diagnostics with the action's stable defaults key and
OSStatus. The saved shortcut remains visible so user intent is not discarded, but the failure is no
longer silent when another process or the system refuses the global combination.
Selection Tools registers Search, Translate, Define and Grammar as separate actions under the
`plugin.selection-tools.*` namespace. They intentionally ship unbound; users record Hyper + S/T/D/G in
Settings → Shortcuts, using the same recorder, conflict detection and Carbon registration as every
other plugin action.

## Recorder

The settings recorder (`Features/Settings/ShortcutRecorder.swift`) is deliberately **not** a focusable
control: the active recorder is `HotKeyManager.recordingAction` state, and keys are captured by local
NSEvent monitors while all Carbon registrations are paused.
