# Calendar plugin

Calendar & meetings in the launcher: the **My Schedule** command opens a palette screen of the next
two weeks' events, and an event carrying a video-call link joins it with one Return. The widget
strip's calendar card and this screen are **one feature** — both read the same
`DashboardWidgetsStore` EventKit fetch, and this plugin's Settings pane owns the shared calendar
preferences.

## Data flow

`DashboardWidgetsStore` (owned by `AppCore`, deliberately not gated by this plugin's enablement)
fetches events once per minute while visible and publishes:

- `upcomingEvents` — the soonest events of the next 14 days, capped at 50, each carrying its URL
  field, location and notes for meeting-link detection.
- `nextEvent` — the widget card's single reading, the head of `upcomingEvents`, falling back to the
  year horizon's soonest event when the fortnight is empty.

The existing account filter, all-day toggle and cancellation/source rules apply to both readings —
one fetch, two surfaces. Preference keys keep their historical `dashboard-widgets.*` names, so
nothing migrates.

## The schedule screen

A `PluginPaletteScreenRegistration` rendered by the shared list. Rows are keyed by event identifier
*plus start time*, because a recurring event reuses one identifier across occurrences. Each row:

- Title, with `Today · 2:00 – 2:30 PM · CalendarName` (and the location, when it isn't a link)
  as the subtitle.
- A green video tile and a provider accessory (Zoom, Google Meet, Microsoft Teams, Webex, Whereby,
  Jitsi, FaceTime) when a meeting link is found; a red calendar tile otherwise.
- ↵ joins the meeting when there is one, otherwise opens Calendar. The ⌘K menu adds Join, Open
  Calendar, Copy Meeting Link and Copy Event Title.

Without full access the screen shows a single actionable row: request access, or open System
Settings when access was denied. Nothing here reads the network — events come from EventKit and
"joining" is opening the event's own URL in the default browser.

## Meeting-link detection

`CalendarScheduleEngine` stays Foundation-only and pure (clock, calendar and locale injected;
`Tools/calendar-schedule-test.swift` compiles it). `meetingLink(urlString:location:notes:)` scans the
event's URL field first, then the location, then the notes, extracting URLs and matching hosts
(exact or subdomain) against the known providers — a lookalike host or an ordinary website is not a
meeting. The engine also owns the schedule rows' day labels (Today / Tomorrow / abbreviated
weekday+date) and time spans.

## Settings

The pane hosts the plugin enable card, the shared calendar preferences (access state, account
picker, all-day toggle — moved here from the Widgets page, which now points at this pane), and the
My Schedule shortcut recorder. Disabling the plugin removes the command and screen and returns an
active schedule screen to the launcher; the widget card keeps showing, since widgets have no off
switch.
