# Widgets

Widgets is the card strip above the launcher sections when the palette is on its empty
query root. It shows an analog clock, the current weather, today's uptime, connected device
batteries and the next calendar
event. Each card can be shown or hidden independently, and every one of them is the same 116-point
square. The title-free clock follows the selected time zone, draws live hour, minute and second
hands, and keeps the dashboard's adaptive translucent surface instead of introducing an opaque clock
face. Typing a query or switching palette mode hides the strip immediately.

## Architecture

`DashboardWidgetsPlugin` is the registration adapter that places this system feature in Settings.
`DashboardWidgetsStore`, owned by `AppCore`, owns EventKit authorization, the next-event snapshot,
widget preferences and the visible-only refresh task. Preferences use bundle-scoped `UserDefaults`
and participate in trusted settings backup/sync. `DashboardWidgetsEngine.swift` remains
Foundation-only and pure; it resolves preference fallbacks, clock hand angles and calendar filters
for `Tools/dashboard-widgets-test.swift`.

Uptime is its own pair for the same reason — the half that watches input stays isolated.
`DashboardUptimeStore`, owned by `AppCore`, owns consent, the input monitors, the day's tallies and
the coalescing flush timer. `DashboardUptimeEngine.swift` stays Foundation-only and pure: it resolves
the day rollover and formats the elapsed time and the tally lines, pluralization included — the
card spells them out ("383 keys pressed", "16 mouse clicks") rather than labelling them with a glyph.

Device battery is another pair, isolated for the opposite reason — the half that reads IOKit is the
only part that isn't portable. `DashboardDeviceBatteryStore`, owned by `AppCore`, owns the registry
scan and the visible-only refresh loop. `DashboardDeviceBatteryEngine.swift` stays Foundation-only
and pure: it resolves a device's category from its product name, clamps the level, orders the
devices and builds the card's lines.

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
matching non-cancelled event. The card's date heading is formatted from the current instant rather
than from EventKit, so every access state below `fullAccess` replaces only the card's bottom row —
the day of the week and the date stay right whether or not Spotter can read a calendar. A selected account that is temporarily unavailable falls back to all
available calendars rather than producing a false empty result. Calendar work starts when the
dashboard becomes visible and stops when it leaves the palette.

## Uptime and input privacy

The uptime card reads *hours since the screen first came on today*, over today's key-press and
click tallies. Elapsed time is wall clock, so a mid-day sleep counts; the day's start is stamped on
its first sign of activity — a woken screen, a resumed session or a counted event — and never at
midnight, so a Mac left awake overnight doesn't claim a session since 00:00. A sleeping display is
not a sign of activity, so a 4am background wake can't start the day either. Tallies survive a
relaunch, clear at midnight, and clear when the widget is turned off. `Reset Today` in Settings
clears them without disturbing the start stamp.

Counting input system-wide is not networked, but it gets the same consent shape: the widget ships
off, enabling it goes through a dialog naming exactly what is and isn't recorded, and no monitor is
installed until then. The counters take two facts off an event — key or click, and whether a key was
an autorepeat — and increment an integer. Key codes, characters, modifiers and click locations are
never read, so nothing retained can reconstruct what was typed.

Counting runs through `NSEvent` monitors rather than a fourth `CGEventTap`: a global monitor is
passive by construction and cannot alter or swallow an event. A local monitor sits beside it, since
global monitors never see events delivered to Spotter itself and the palette's own keystrokes would
otherwise go uncounted. Key events need the Accessibility grant and clicks do not, so an untrusted
Mac still counts clicks and both the card and Settings offer the grant instead of showing a
misleading zero. AppKit hands back a monitor token either way, so trust is polled on the same timer
that flushes the tallies, and the monitors are re-registered once it is granted.

Tallies are coalesced and written at most every five seconds, plus on `applicationWillTerminate`;
they stay in bundle-scoped `UserDefaults` and are device-local. Only the consent flag travels in the
trusted settings backup/sync file — restoring one may switch counting on, which is itself the consent
act.

## Device battery

The card is a grid of ring gauges, title-free and filled edge to edge like the clock — the rings
*are* the card, and a heading would cost a row of them. Each connected mouse, keyboard or trackpad
that reports a level gets one ring: a faint full track with the level swept clockwise from twelve
over it, and the device's SF Symbol in the middle. The arc is green, red below 20%, which is the
question a glance is asking. Exact percentages are deliberately not on the card — four small numbers
at 44 points read worse than four arcs — and live in the Settings pane and the accessibility label
instead.

A device on external power breaks its ring at twelve for a bolt to sit in. The notch is punched out
of the track and arc together rather than drawn over them, since the card's fill is translucent and
a disc of it would let the green through instead of clearing room. The HID service publishes no
explicit charging key, only `BatteryStatusFlags`; bit 0 is set on a cabled device and clear on one
running off its battery, and only that bit is read — the rest of the word is undocumented. Absent
flags read as zero, so a device that reports nothing gets no bolt: the bolt is the claim that needs
evidence.

The card holds its 116-point square explicitly rather than hugging its gauges, so a single row of
rings doesn't sit as a stub between full-height neighbors. The grid sizes itself to what it holds:
one device takes the whole 96-point interior as a single large ring, two or more pair into two
columns, and the diameter is the largest circle that fits both directions, so three devices size to
their two rows and four fill the square at 44 points each. Four is the limit; a fifth turns the last
slot into a `+2` count rather than dropping those devices unremarked. Devices order lowest-first
throughout, so whatever needs charging soonest is the first ring drawn.

The category behind each symbol comes from the product name. A paired device is named after its
owner ("Marcus's Magic Mouse"), so the stable part is the category noun inside it; anything Spotter
doesn't recognize falls back to a generic battery glyph and keeps its own name in Settings, rather
than being guessed at from a vendor/product table that would rot.

Levels come from the `BatteryPercent` property that every HID peripheral publishes on its
`AppleDeviceManagementHIDEventService` node in the IOKit registry. That read needs no consent gate,
unlike the other two non-obvious cards: any process can read the registry, so there is no TCC prompt,
no entitlement and no permission to explain. Nothing is persisted and nothing leaves the machine.

AirPods are deliberately out of scope. They are not HID devices, so they publish no `BatteryPercent`
node; the only routes to their level are `system_profiler` or IOBluetooth, and IOBluetooth requires
`NSBluetoothAlwaysUsageDescription` and prompts for Bluetooth access process-wide — a system
permission for one card. Do not add it without an explicit owner decision.

The card is hidden whenever nothing connected reports a level, since an empty square would imply a
reading it doesn't have — a Mac with only a built-in keyboard is the normal case, not a fault. That
hiding is why the scan also runs from `AppCore.showPalette`: the card's own poll lives with the card,
so with the card unrendered nothing else would notice a device that has since connected. The scan is
a handful of registry property reads, measured at ~0.03 ms, so it runs synchronously on the main
actor; while the card is on screen it repeats once a minute, which is as fast as a whole percent
moves.

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

Widgets is an always-available system feature, and the only registration placed `.widgets`: it has no
Settings row of its own, contributing the sidebar's **Widgets** section between System and Plugins
instead. Each card gets one row and one pane there — Clock, Weather, Uptime, Device Battery,
Calendar, in the order
the strip draws them — so a card is configured on its own rather than in a shared list of switches.
Every pane opens with a `Widget` card holding that one card's show/hide switch, and reveals a
`Details` card below it: the clock's time zone, the weather's city and unit, the uptime card's
keyboard-permission state and Reset Today, the calendar's access, account and all-day preference.
Device Battery's second card is a read-out rather than a setting — the devices found and their
levels, so a Mac showing no card says why.
Weather and Uptime show their details only while they are on, since both are consent-gated. Switching
every card off hides the strip. Existing calendar-account, all-day-event and time-zone preferences
remain unchanged, and saved identifiers for removed widgets are ignored. The permission overview
exposes Calendar and Accessibility as global permissions, because the calendar card and the uptime
card's key counting depend on them.
Calendar refreshes occur only while the dashboard is visible, while uptime counting runs whenever
the widget is on — a tally of the whole day would be wrong if it only accrued with the palette open.
Permission views
re-check authorization while visible so returning from System Settings updates them without a
relaunch.
