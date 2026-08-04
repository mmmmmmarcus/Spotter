# System Commands plugin

30 everyday macOS actions in the launcher — ported from Tinycast #107 and adapted to the plugin
contract. Ships **disabled**.

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
global shortcut reach, so no path can skip it. **Return is bound to Cancel** — a destructive command
is one ↵ away in the palette, and a reflexive second ↵ must not restart the Mac. A re-entrancy flag
stops a held shortcut stacking dialogs.

## Permissions

The registration declares both `.accessibility` (media keys, Dismiss Notifications) and
`.automation` (the System Events / Finder AppleScripts), so System → Permissions lists the plugin
under each. A denial comes back as a typed `SystemCommandFailure.settings`, and the failure alert
offers the matching Settings pane rather than just reporting the error.

## Layout

- `SystemCommand.swift` — Foundation-only catalog: IDs, names, symbols, confirmation policy. Quit
  All keeps its legacy `command:quit-all-apps` entry ID so existing favorites, visibility and
  learned ranking survive.
- `SystemCommandRunner.swift` — every platform side effect, off the main actor where it blocks.
- `SystemCommandsPlugin.swift` — registration, the confirmation/failure presenter, `AppCore` funnel.
- `SystemCommandsSettingsView.swift` — enable switch plus a shortcut recorder per command.
