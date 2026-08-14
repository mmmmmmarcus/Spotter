# Dashboard Widgets

Dashboard Widgets is the card strip above the launcher sections when the palette is on its empty
query root. It shows an analog clock, the current weather and the next calendar event. Each card can
be shown or hidden independently. The title-free clock uses a square card, follows the selected time
zone, draws live hour, minute and second hands, and keeps the dashboard's adaptive translucent
surface instead of introducing an opaque clock face. The weather card matches that square, title-free
shape. Typing a query or switching palette mode hides the strip immediately.

## Architecture

`DashboardWidgetsPlugin` is the registration adapter that places this system feature in Settings.
`DashboardWidgetsStore`, owned by `AppCore`, owns EventKit authorization, the next-event snapshot,
widget preferences and the visible-only refresh task. Preferences use bundle-scoped `UserDefaults`
and participate in trusted settings backup/sync. `DashboardWidgetsEngine.swift` remains
Foundation-only and pure; it resolves preference fallbacks, clock hand angles and calendar filters
for `Tools/dashboard-widgets-test.swift`.

Weather is a separate pair so the networked half stays isolated. `DashboardWeatherStore`, also owned
by `AppCore`, owns consent, the chosen city, the unit, the cached reading and the refresh loop.
`DashboardWeatherEngine.swift` stays Foundation-only and pure — it builds the request URLs and maps
WMO weather codes to an SF Symbol and phrase — so the same harness covers it without app state.

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

## Weather privacy

Weather is the one networked part of the dashboard, so it follows the project's consent shape and
ships off. Nothing reaches the network until the user accepts a dialog naming the provider
(Open-Meteo), the cadence and what leaves the machine. `DashboardWeatherStore` re-checks `isEnabled`
at every entry point rather than trusting a caller, including on both sides of the `await` around a
request, since consent can be withdrawn mid-flight.

Spotter never reads Location Services. Until the user picks a city, the card uses
`WeatherCity.default` — a fixed place (Tokyo, Japan), deliberately a constant rather than something
derived from the locale or time zone, which would be location inference by another name. The city
search is itself gated: typing into the field before consent is refused rather than quietly
geocoded. Only the current city's coordinates leave the machine. Requests go out on a private ephemeral `URLSession` with
`urlCache = nil`, never `URLSession.shared`, so a cacheable response cannot leave a second copy in
the shared on-disk `URLCache` that opting out would not delete.

The reading refreshes every 30 minutes while the dashboard is visible, backing off to a shorter retry
only after a failure, and the loop does not run without both consent and a city. The latest snapshot
is cached in a bundle-scoped `weather.json` so a relaunch shows the last reading instead of an empty
card; turning the widget off deletes that file and clears the reading. Consent, city and unit travel
in the trusted settings backup/sync file — restoring one may switch the feature on, which is itself
the consent act.

## Settings and lifecycle

Dashboard Widgets is an always-available system feature under Settings → System → Dashboard Widgets.
Its pane independently toggles Clock, Weather and Next Event; switching them all off hides the strip.
Clock can follow the system time zone or use any IANA zone built into macOS. Weather reveals its
details card — city search and unit — only while it is on. Existing calendar-account, all-day-event
and time-zone preferences remain unchanged. Saved identifiers for removed widgets are ignored. The permission overview exposes Calendar as a global permission because the next-event card
depends on it. Calendar refreshes occur only while the dashboard is visible. Permission views
re-check authorization while visible so returning from System Settings updates them without a
relaunch.
