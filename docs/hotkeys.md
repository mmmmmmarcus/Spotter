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

## Persistence

Shortcuts persist as JSON strings under `KeyboardShortcuts_<name>` UserDefaults keys — a **legacy
format** from the removed KeyboardShortcuts package, kept so old bindings survive. The set of bound
bundle IDs lives in `boundAppBundleIDs` and is re-registered on launch. System Settings panes use
`boundPaneBundleIDs`; custom commands use their stable UUIDs in `boundCustomCommandIDs`. Built-in
plugins expose stable `PluginActionKey` values through `PluginRegistry`; new keys use the
`plugin.<plugin-id>.<action-id>` namespace while migrated actions may retain legacy defaults keys.

Disabling a plugin makes registry dispatch a no-op while preserving the Carbon registration and saved
binding. Re-enabling resumes the action without creating plugin-specific branches in `HotKeyManager`.
Plugins with several commands expose a stable action key per command, so each can be bound directly.
Selection Tools registers Search, Translate, Define and Grammar as separate actions under the
`plugin.selection-tools.*` namespace. They intentionally ship unbound; users record Hyper + S/T/D/G in
Settings → Shortcuts, using the same recorder, conflict detection and Carbon registration as every
other plugin action.

## Recorder

The settings recorder (`Features/Settings/ShortcutRecorder.swift`) is deliberately **not** a focusable
control: the active recorder is `HotKeyManager.recordingAction` state, and keys are captured by local
NSEvent monitors while all Carbon registrations are paused.
