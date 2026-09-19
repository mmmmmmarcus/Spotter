# Schedule

The **Schedule** launcher command and the calendar Widget open the same calendar canvas inside the
existing Palette. No auxiliary window is created. The command ID `command:calendar-schedule`,
plugin ID and shortcut binding remain unchanged, so existing shortcuts and favorites survive the
rename from My Schedule.

## Views and navigation

The Week / Month switch sits at the trailing edge of the shared Palette search header, in one
Liquid Glass capsule with an immediate selection highlight. It preserves search focus and exposes
its selected state to VoiceOver. A separate Liquid Glass Today button sits immediately to its left;
both glass surfaces share the same 32-point height.
Today uses `calendar.badge.clock`, Week uses `rectangle.split.3x1`, and Month uses `calendar`;
the controls show only icons, keeping their names in tooltips and accessibility labels.
The redundant week-range title is omitted; Month retains its month/year heading. Week displays a
scrollable 24-hour time grid, a separate all-day lane, local-time labels and a current-time line.
The left time axis uses only the hour (`0`–`23`), without minutes, leading zeros or AM/PM, regardless of the system's hour-cycle preference.
The current-time line spans all seven day columns in the current week, above the event cards.
Past date columns and the elapsed portion of today use 45% opacity, including event cards and grid lines;
future time stays at full opacity. Past day headings and all-day events also fade. The line remains
fully visible, and faded events remain selectable. The existing visible-only minute refresh updates
this presentation without another timer.
Overlapping events occupy separate columns; overnight events are clipped into each displayed day.
Month displays six complete weeks, including adjacent-month dates. Cells show one event preview
and an overflow count; clicking a date or pressing Return on it opens the week containing that date with every event
accessible through scrolling. Week starts on the system calendar's configured weekday.

Entering a week centers the current-time line only when a visible timed event is in progress;
otherwise it centers 10 AM, including other weeks. All-day events do not count as activity on the
time grid. Positioning waits for events and the all-day lane to load. Automatic refreshes and search
changes do not keep recentering after the user scrolls.

Changing the displayed week/month fades the new canvas in over 160 ms while it moves eight points
from the navigation side to rest, matching Note page turns. Event loading and initial scroll positioning
finish before the reveal; repeated navigation cancels the pending reveal. The header stays fixed,
selection highlights remain immediate, and Reduce Motion shows the new content without animation.
Minute refreshes, event focus changes and typing do not trigger page animations.

There are no on-screen paging arrows or empty navigation row in Week. Today returns to the current date.
Command-[ / Command-] page backward/forward by the displayed week or month, including with a search query.
In Week, Up / Down select adjacent events within the same day, including the all-day lane. Left / Right
select the closest start time on the nearest populated date, preferring the same all-day/timed lane
and skipping dates without matching events. Navigation stops at the visible range's edges rather than
paging. Month arrows move between date cells: one day horizontally, seven days vertically. Return
uses the shared activation path. Plain arrows navigate even with a filter typed; modified arrows
retain text-editing behavior. Menus, confirmations and an active IME composition retain keyboard priority. The shared search field filters events within the displayed period by title,
calendar name or location. Month retains its date cells while filtering their previews.

Selecting an event opens its details in the same canvas; Esc or Back returns to the calendar. The
meeting button and the shared Actions menu offer explicit Join, Copy Meeting Link, Copy Event Title
and Open Calendar actions. Only those explicit actions leave the Palette. Meeting-link detection
continues to recognize the existing trusted conference-host patterns.

## Ownership and data

`AppCore.calendarSchedule` owns `CalendarScheduleStore`: the current date, view mode, selected detail,
visible event records and refresh tasks. These browsing choices are transient. The store loads only
the visible week/42-day month range, including past and future dates; the previous 14-day/50-event
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
are not extra selectable items. Week snapshots contain all-day placements first, then timed placements, ordered by day and start time.
Each placement adds its day to the recurring occurrence's identifier-plus-start-time identity, so a
multi-day event has only one highlighted placement and every visible placement is keyboard-reachable.
Event details and actions still resolve to the original occurrence. PalettePanel routes calendar keys
before the field editor can consume them; the shared flat selection remains the sole selection state.

`ScheduleLayout.swift` and `CalendarScheduleEngine.swift` stay Foundation-only and pure, with calendar
and time injected. The harness covers leap months, week boundaries, DST week navigation, elapsed-region boundaries, exclusive
midnight endings, overnight clipping, overlap columns, spatial navigation, empty-day skipping and
multi-day selection identities, alongside existing meeting-link
and date-label checks.

Layout references: [Apple Calendar](https://support.apple.com/en-ie/guide/calendar/icl1002/mac) and
[Google Calendar](https://support.google.com/calendar/answer/6110849?hl=en-ID).
