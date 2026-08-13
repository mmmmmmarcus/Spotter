# Dashboard Widgets

Dashboard Widgets is the card strip above the launcher sections when the palette is on its empty
query root. It shows the current time and date and the next calendar event. Each card can be shown or
hidden independently. Typing a query or switching palette mode hides the strip immediately.

## Architecture

`DashboardWidgetsPlugin` is the registration adapter that places this system feature in Settings.
`DashboardWidgetsStore`, owned by `AppCore`, owns EventKit authorization, the next-event snapshot,
widget preferences and the visible-only refresh task. Preferences use bundle-scoped `UserDefaults`
and participate in trusted settings backup/sync. `DashboardWidgetsEngine.swift` remains
Foundation-only and pure; it resolves preference fallbacks and calendar filters for
`Tools/dashboard-widgets-test.swift`.

The registry permits exactly one `launcherDashboard` owner. `RootPaletteView` injects that view into
the launcher's existing scroll content only for an empty launcher query. Dashboard cards never join
the flat result index, so the first favorite/application remains selection 0.

## Calendar privacy

Calendar access starts undetermined and is requested only after the user clicks **Allow** in the
dashboard or Settings. The Info.plist purpose string names the one value Spotter reads: the next
upcoming event, and the signed app carries the Calendar personal-information entitlement required by
EventKit. Denied access renders an explicit System Settings affordance, while a policy-restricted Mac
shows a non-actionable restricted state instead of an empty-event claim.

After full access is granted, the store exposes EventKit calendar sources as accounts. The user can
include all accounts or one source such as iCloud, Google or Exchange, and can independently exclude
all-day entries. The store queries EventKit from now through one year ahead and shows the earliest
matching non-cancelled event. A selected account that is temporarily unavailable falls back to all
available calendars rather than producing a false empty result. Calendar work starts when the
dashboard becomes visible and stops when it leaves the palette.

## Settings and lifecycle

Dashboard Widgets is an always-available system feature under Settings → System → Dashboard Widgets.
Its pane independently toggles Clock and Next Event; switching both off hides the strip. Clock can
follow the system time zone or use any IANA zone built into macOS. Existing calendar-account,
all-day-event and time-zone preferences remain unchanged. Saved identifiers for removed widgets are
ignored. The permission overview exposes Calendar as a global permission because the next-event card
depends on it. Calendar refreshes occur only while the dashboard is visible. Permission views
re-check authorization while visible so returning from System Settings updates them without a
relaunch.
