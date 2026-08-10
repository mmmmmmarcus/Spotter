# Kill Process plugin

Kill Process is an on-demand native process inspector modeled on Raycast's Kill Process extension. It
has no independent window or custom list UI. Opening the command enters a registered plugin mode in
Spotter's main palette; the shared launcher owns its search field, flat keyboard selection, result
rows, bottom action group and ⌘K menu. `/bin/ps` runs off the main actor, is parsed into plain values by
`KillProcessEngine`, and refreshes only at the configured interval while that palette mode is visible.

## Behavior

- Sort by CPU or resident memory; filter by name and app name, plus PID (on by default) and
  executable path (off by default) — both toggles in Settings, and both synced through
  `SettingsBackup.PluginPrefs.KillProcess` with the other six preferences.
- Optionally group helpers that share an outer `.app` bundle and aggregate their CPU/memory totals.
- Terminate with `SIGTERM`, force-terminate with `SIGKILL`, restart an app/binary (with a force
  variant), or target every process with the same executable name — force-kill-all included. A force action retries permission-denied targets through the
  standard macOS administrator prompt (`osascript … with administrator privileges`). That prompt is
  per-action credential entry, not a TCC grant, so Kill Process deliberately declares no
  `PluginPermission` and does not appear in System → Permissions; the Settings pane carries a callout
  instead.
- Process actions execute immediately without a confirmation dialog. After completion the palette
  stays open and refreshes its process results in place.
- A failed signal or restart also leaves the palette and its search focus in place. It reports through
  the non-activating HUD and records the OS error in Settings → Diagnostics instead of interrupting
  the process list with a modal alert.
- Copy an executable path or manually refresh from the shared Actions menu.
- PID 0, PID 1 and Spotter's own PID are never included.

`KillProcessManager` is owned by `AppCore`; `KillProcessEngine` is Foundation-only and tested with a
fixed `ps` fixture. Its registration maps the manager state into `PluginPaletteSnapshot` rows and
routes row IDs back to process actions. Leaving the mode, hiding the palette or disabling the plugin
cancels refresh work; disabling also returns the palette to the launcher root.
