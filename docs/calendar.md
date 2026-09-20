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
Today displays its text label. Week uses `rectangle.split.3x1` and Month uses `calendar`,
with their names in tooltips and accessibility labels.
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
retain text-editing behavior. Menus, confirmations and an active IME composition retain keyboard priority. The shared search field matches events within the displayed period by title,
calendar name or location. All events remain in the grid, with nonmatches at 12% opacity and excluded
from event activation, hover previews and keyboard navigation. Overlap columns and viewport remain stable.
Month retains every date and gives matching previews priority, fading previews on days without matches.

Week keyboard focus scrolls only when the selected timed event falls outside the viewport, using its
actual minute range rather than the layout origin of offset-drawn cards. Visible events preserve the
viewport; all-day focus only scrolls its separate lane. Command-plus (including Command-equals) and
Command-minus scale hour heights in bounded 25% steps. Grid height and viewport animate together over
200 ms, preserving the center time and clamping at midnight/day end. Reduce Motion disables animation.
Zoom is session-only, leaves the Palette frame unchanged and applies only to the week grid.

Space toggles a preview of the focused week event; hovering an event for three seconds opens the same
preview. While typing a filter, spaces remain text until arrow navigation explicitly focuses events.
The preview is anchored to the event and kept within the canvas, with the same calendar tint, leading
stripe and corner radius, a raised material surface and a short scale/fade animation. It shows the
original-zone time/date, location, organizer and attendees, including locally extracted imported
attendee fields; no note body is displayed. Long metadata scrolls inside the preview. Escape, Space,
clicking outside or leaving the preview dismisses it; paging, scrolling, zooming, filtering, opening
Actions or leaving Schedule cancel it and any pending hover. Its expand action opens full details.

Selecting an event opens its details in the same canvas; Esc or Back returns to the calendar. The
meeting button and the shared Actions menu offer explicit Join, Copy Meeting Link, Copy Event Title
and Open System Calendar actions. Return in details opens Google Calendar: an existing Google event
link from the event URL or notes opens that event; otherwise the action explicitly says Open Date in
Google Calendar and opens its date in the event's time zone. EventKit identifiers are not converted
into Google event IDs. The same destination is available in Actions. Only explicit actions leave the Palette. Meeting-link detection
continues to recognize the existing trusted conference-host patterns.

## Event details

Details use two columns inside the existing Palette, inset by an additional 12 points. The left column
scrolls independently beneath its headline. Date, time, calendar, location, organizer, participants,
repeat and status fields share an icon column and a leading-aligned content column. Text headings are
replaced with SF Symbols, retaining tooltips and accessibility labels. Meeting ID, Alerts and
Availability are not displayed. It has a 28-point headline, calendar and one combined date/time field
in the event's original zone (or Local Time for floating events). All-day events retain date semantics.
The former converted-time rows are removed. Meeting/event links and available metadata follow.

The right column places `WorldClockMapContent` and the note body without a heading inside one
ScrollView, so the map scrolls away with the notes. The same component draws World Clock's land, day/night boundary, saved-city markers and time
labels, with the instant explicitly fixed at the event's start. No live clock or World Clock preview
offset can shift the event map. It uses half the previous height: up to 22.5% of the column height, capped at a
4:1 aspect; the continents retain their projection scale. Compact city/time labels share a horizontal
strip over the map instead of being omitted by geographic collision avoidance; overflow scrolls horizontally.
Every saved city remains available, including ones outside the cropped map or without coordinates. The event map is read-only, so scrolling
continues to navigate notes rather than changing the event time. The extra Back to Schedule row is
removed; keyboard back navigation and shared Palette controls remain. The month heading is hidden
in details, as are Today and the Week/Month switch.

`CalendarEventMetadata` reads organizer, attendees and responses, recurrence rules
and event status on the background EventKit reader, returning plain display fields.
People display only names; accepted native responses append an SF Symbol checkmark. Unknown names
use an unnamed-person label rather than an email address; imported names never imply an accepted RSVP.
The same people presentation is shared by details and peek. Absent fields are omitted. Calendar URL and structured-location title are retained when available.
`ScheduleNotes` is Foundation-only and parses HTML anchors, Markdown links, ordinary URLs and HTML
entities locally. It uses an anchor's supplied title; bare URLs use compact host labels. No web title
fetch, HTML renderer or remote image request occurs. Scripts/styles are omitted and only http, https
and mailto links are actionable, through explicit clicks. Link processing runs off the main actor.
Recognizable organizer/participant/meeting-ID lines from imported notes become left-column metadata;
native EventKit values take precedence. The remaining note text stays on the right. Neither notes nor
calendar records are modified, and missing native data is never guessed.

## Ownership and data

`AppCore.calendarSchedule` owns `CalendarScheduleStore`: the current date, view mode, zoom level, selected detail/preview,
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
multi-day event has only one highlighted placement and every matching placement is keyboard-reachable.
Event details and actions still resolve to the original occurrence. PalettePanel routes calendar keys
before the field editor can consume them; the shared flat selection remains the sole selection state.

`ScheduleLayout.swift` and `CalendarScheduleEngine.swift` stay Foundation-only and pure, with calendar
and time injected. The harness covers leap months, week boundaries, DST week navigation, elapsed-region boundaries, exclusive
midnight endings, overnight clipping, overlap columns, spatial navigation, empty-day skipping and
multi-day selection identities, viewport reveal boundaries and center-preserving zoom, alongside existing meeting-link
and date-label checks.

Layout references: [Apple Calendar](https://support.apple.com/en-ie/guide/calendar/icl1002/mac) and
[Google Calendar](https://support.google.com/calendar/answer/6110849?hl=en-ID).
