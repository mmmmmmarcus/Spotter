# Kill Process plugin

Kill Process is an on-demand native process inspector modeled on Raycast's Kill Process extension. It
does not poll while its window is closed. Opening the command runs `/bin/ps` off the main actor, parses
plain values in `KillProcessEngine`, and refreshes only at the configured interval while visible.

## Behavior

- Sort by CPU or resident memory; filter by name, app name, executable path or PID.
- Optionally group helpers that share an outer `.app` bundle and aggregate their CPU/memory totals.
- Terminate with `SIGTERM`, force-terminate with `SIGKILL`, restart an app/binary, or target every
  process with the same executable name. A force action retries permission-denied targets through the
  standard macOS administrator prompt.
- Copy an executable path and manually refresh the snapshot.
- Confirm termination and restart actions by default. PID 0, PID 1 and Spotter's own PID are never
  included.

`KillProcessManager` is owned by `AppCore`; `KillProcessEngine` is Foundation-only and tested with a
fixed `ps` fixture. Disabling the plugin cancels refresh work and closes its workspace.
