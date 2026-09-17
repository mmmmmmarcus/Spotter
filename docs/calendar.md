# Schedule

The **Schedule** launcher command and the calendar Widget open the same calendar canvas inside the
existing Palette. No auxiliary window is created. The command ID `command:calendar-schedule`,
plugin ID and shortcut binding remain unchanged, so existing shortcuts and favorites survive the
rename from My Schedule.

## Views and navigation

The Day / Week / Month segmented control switches between actual layouts. Day and Week display a
scrollable 24-hour time grid, a separate all-day lane, local-time labels and a current-time line.
Overlapping events occupy separate columns; overnight events are clipped into each displayed day.
Month displays six complete weeks, including adjacent-month dates. Cells show one event preview
and an overflow count; clicking a date or pressing Return on it opens that day with every event
accessible through scrolling. Week starts on the system calendar's configured weekday.

Entering a day/week that contains today centers the current-time line after events and the all-day
lane have loaded. Automatic refreshes do not keep recentering after the user scrolls. Other periods
start at 8 AM.

Previous / Next advances by the displayed period, and Today returns to the current date. Empty-query
Left / Right arrows also navigate periods. Up / Down and Return reuse the Palette selection and
activation path. The shared search field filters events within the displayed period by title,
calendar name or location. Month retains its date cells while filtering their previews.

Selecting an event opens its details in the same canvas; Esc or Back returns to the calendar. The
meeting button and the shared Actions menu offer explicit Join, Copy Meeting Link, Copy Event Title
and Open Calendar actions. Only those explicit actions leave the Palette. Meeting-link detection
continues to recognize the existing trusted conference-host patterns.

## Ownership and data

`AppCore.calendarSchedule` owns `CalendarScheduleStore`: the current date, view mode, selected detail,
visible event records and refresh tasks. These browsing choices are transient. The store loads only
the visible day/week/42-day month range, including past and future dates; the previous 14-day/50-event
schedule cap no longer applies. Each load uses a background-owned EventKit store, maps events to
Sendable values, and releases its native objects before returning. Stale and cancelled results never
replace the current range. Minute refreshes preserve the existing view while reading, and stop on
leaving the screen. Calendar access is checked before and after reading.

Account choice, all-day preference, canceled-event exclusion and permission state are shared with
`DashboardWidgetsStore`. The Widget retains its existing upcoming-event cache and refresh behavior.
Missing saved accounts retain the existing all-accounts fallback and Settings explanation. There
are no new permissions, network requests, content writes or persisted preference keys.

Without full Calendar access, the existing shared palette list presents Request Access or Open
System Settings. Granting access mounts and refreshes the calendar canvas.

## Palette integration and tests

`PluginPaletteScreenRegistration.canvas` optionally supplies a plugin-owned calendar or other spatial
view inside the existing palette content area. Shared header, footer, Actions, selection and back
handling remain owned by the Palette. List plugins continue to use `PluginPaletteList`.

Month snapshots contain one selectable item per date, in row order; previews and overflow counts
are not extra selectable items. Day/week snapshots contain all-day events first, then timed events.
Recurring occurrences retain identifier-plus-start-time identities.

`ScheduleLayout.swift` and `CalendarScheduleEngine.swift` stay Foundation-only and pure, with calendar
and time injected. The harness covers leap months, week boundaries, DST day lengths, exclusive
midnight endings, overnight clipping and overlap column allocation, alongside existing meeting-link
and date-label checks.

Layout references: [Apple Calendar](https://support.apple.com/en-ie/guide/calendar/icl1002/mac) and
[Google Calendar](https://support.google.com/calendar/answer/6110849?hl=en-ID).
