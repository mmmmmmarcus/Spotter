# Dashboard Widgets

Dashboard Widgets is the card strip above the launcher sections when the palette is on its empty
query root. It shows the current time and date, the next calendar event, Claude Code and Codex quota
windows, and the current month. Typing a query or switching palette mode hides it immediately.

## Architecture

`DashboardWidgetsPlugin` owns the registry surface and Settings placement.
`DashboardWidgetsStore`, owned by `AppCore`, owns EventKit authorization, the next-event snapshot,
local usage snapshots and the visible-only refresh task. `DashboardWidgetsEngine.swift` remains
Foundation-only and pure; it builds the fixed 42-cell month grid and decodes locally persisted usage
formats for `Tools/dashboard-widgets-test.swift`.

The registry permits exactly one `launcherDashboard` owner. `RootPaletteView` injects that view into
the launcher's existing scroll content only for an empty launcher query. Dashboard cards never join
the flat result index, so the first favorite/application remains selection 0.

## Calendar privacy

Calendar access starts undetermined and is requested only after the user clicks **Allow** in the
dashboard or Settings. The Info.plist purpose string names the one value Spotter reads: the next
upcoming event, and the signed app carries the Calendar personal-information entitlement required by
EventKit. Denied access renders an explicit System Settings affordance, while a policy-restricted Mac
shows a non-actionable restricted state instead of an empty-event claim.

After full access is granted, the store queries EventKit from now through one year ahead. The month
grid marks dates that contain an event in the displayed month; the event card shows the earliest
non-cancelled event. Calendar work starts when the dashboard becomes visible and stops when it leaves
the palette.

## Local usage data

Dashboard Widgets never signs in, reads API keys, launches a CLI or sends a request. Claude Code
usage is taken from a current CodexBar Claude history/widget snapshot when one is available. Codex
usage prefers current CodexBar state and falls back to the newest local Codex session rate-limit
event under `~/.codex/sessions`.

Every usage window carries its capture and reset timestamps. Reset windows are discarded after their
reset time; formats without a reset are treated as fresh for six hours. Missing or stale data is
shown as unavailable rather than as zero usage.

## Settings and lifecycle

The plugin is enabled by default and can be disabled under Settings → Plugins → Dashboard Widgets.
Disabling it removes the strip and stops refresh work. The permission overview exposes Calendar as a
global permission because the next-event card depends on it. Usage refreshes occur only while the
dashboard is visible and can also be triggered from the plugin settings page. Permission views
re-check authorization while visible so returning from System Settings updates them without a relaunch.
