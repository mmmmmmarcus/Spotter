# Built-in system commands

The Commands plugin includes 30 read-only everyday macOS actions — ported from Tinycast #107 and
adapted to the plugin contract. Users can assign shortcuts, but cannot edit or delete these built-ins.

## What's covered

- **Session** — Lock Screen, Sleep, Sleep Displays, Restart, Shut Down, Log Out, Show Screen Saver
- **Media** — Play/Pause, Next Track, Previous Track (system-defined `NSEvent` aux keys)
- **Volume** — Toggle Mute, Volume Up/Down, and 0/25/50/75/100% presets (CoreAudio HAL)
- **Desktop** — Show Desktop, Toggle System Appearance, Toggle Stage Manager, Toggle Hidden Files
- **Files** — Open Trash, Empty Trash, Eject All Disks
- **Apps** — Hide Others, Unhide All, Quit All Applications
- **Other** — Dismiss Notifications (AX tree walk), Toggle Bluetooth (`dlopen`'d IOBluetooth)

Upstream's **Set Volume…** is deliberately not ported: it needs a value-picker dialog that only
exists inside upstream's `ModalWindowController`, which is a cross-cutting UI layer Spotter doesn't
have. The five presets plus up/down cover the same ground without importing that infrastructure.

## Confirmation

Restart, Shut Down, Log Out, Empty Trash and Quit All Applications are `confirmation: .required`.
The gate lives in `AppCore.runSystemCommand`, the single funnel both palette activation and the
global shortcut reach, so no path can skip it. The confirmation is the shared **in-palette card**
(`ConfirmationCard`), never a system dialog, and its highlight starts on Cancel — a destructive
command is one ↵ away in the palette, and a reflexive second ↵ must not restart the Mac. A hotkey
fired with the palette closed shows the palette first. Commands whose effect is otherwise invisible
("Trash Emptied", "No Disks to Eject") report through the command HUD when they finish.

All 30 commands ship visible in the launcher — unlike Window Management and Change Case, nothing here
uses `defaultVisible: false`.

## Permissions

Commands declares both `.accessibility` (media keys, Dismiss Notifications) and `.automation` (the
System Events / Finder AppleScripts), so System → Permissions lists Commands under each. A denial
comes back as a typed `SystemCommandFailure.settings`, and the failure alert offers the matching
Settings pane rather than just reporting the error.

## Layout

- `Commands/SystemCommand.swift` — Foundation-only catalog: IDs, names, symbols, confirmation policy. Quit
  All keeps its legacy `command:quit-all-apps` entry ID so existing favorites, visibility and
  learned ranking survive.
- `Commands/SystemCommandRunner.swift` — every platform side effect, off the main actor where it blocks.
- `Commands/SystemCommandsIntegration.swift` — confirmation/failure presentation and the `AppCore` funnel.
- `Commands/CommandsPlugin.swift` — one registration for built-ins and dynamic custom commands.
- `Commands/CustomCommandsSettingsView.swift` — read-only built-in rows plus editable custom commands.

The shortcut action now belongs to the Commands plugin, but deliberately retains its old
`KeyboardShortcuts_plugin.system-commands.*` defaults key so an upgrade never drops an existing
binding. Backup import likewise accepts the former `system-commands.<action>` identifier.

## Testing

```sh
swiftc -swift-version 6 Spotter/Plugins/Infrastructure/PluginTypes.swift \
    Spotter/Plugins/Commands/SystemCommand.swift Tools/commands-test.swift \
    -o /tmp/commands-test && /tmp/commands-test
```

The harness pins the built-in count, stable launcher IDs, mandatory confirmation set, Commands
ownership and legacy shortcut-storage keys without executing a system action.
