# Hotkeys (in-house, zero dependencies)

`Core/HotKey/` holds:

- `KeyShortcut` — Sendable model, Carbon keycode + modifiers, layout-aware glyphs via `UCKeyTranslate`.
- `HotKeyCenter` — the Carbon `RegisterEventHotKey` layer, pausable.

`HotKeyManager` owns both: persistence, conflict lookup, and dispatch.

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
Selection Tools registers Search, Translate and Grammar as separate actions under the
`plugin.selection-tools.*` namespace. They intentionally ship unbound; users record Hyper + S/T/G in
Settings → Shortcuts, using the same recorder, conflict detection and Carbon registration as every
other plugin action.

## Recorder

The settings recorder (`Features/Settings/ShortcutRecorder.swift`) is deliberately **not** a focusable
control: the active recorder is `HotKeyManager.recordingAction` state, and keys are captured by local
NSEvent monitors while all Carbon registrations are paused.
