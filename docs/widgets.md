# Widgets

Widgets is the card strip above the launcher sections when the palette is on its empty query root. It
shows an analog clock, today's uptime, connected device batteries, the next calendar event and the
Finder selection. Every card is the same 116-point square, and which cards appear — and in what order
— is set in one place, Settings → Widgets → **Arrangement**. Typing a query or switching palette mode
hides the strip immediately.

The clock is the strip's watch face: a title-free analog dial following the selected time zone, with
live hour, minute and second hands and the dashboard's adaptive translucent surface rather than an
opaque dial. Four complications ride the bezel around it the way a watch face carries them — the day
top-right, and, once weather is on and a reading has landed, the temperature top-left, today's range
bottom-left and the condition glyph bottom-right. A corner with nothing known stays empty rather than
drawing a placeholder, so a clock with weather off is still just a clock. Weather has no card of its
own: it *is* those three complications, which is why it is configured in the Clock pane.

The clock is also the one card that spends its whole 116-point square rather than keeping the
uniform `md` margin the others do: the complications *are* its bezel, so that margin would only have
shrunk the dial. The arc rides at `ringInset` from the card's edge and the dial is held `clockFaceInset`
inside it — 13 points, the tightest setting where a full range label ("18°–26°") still clears the
tick ring at every corner.

`ClockComplicationRing` sets each label **on a curve**, not square in a corner: the string is
measured character by character and each glyph is drawn at the angle its own width has reached, then
turned to stand on the tangent there, so the line follows the dial's circle. The two bottom labels
run anticlockwise and are turned over, or they would read upside down at the foot of the circle.
Resolving per character is what costs those strings their kerning — the usual trade for type on a
curve. The condition glyph is the exception: it stays level, since a tilted icon reads as a mistake.

The calendar card shows only what is next — the date left it for the clock's corner, so a second copy
here would be the strip repeating itself.

The File Info card states what is selected in the Finder: its kind in the title slot, its own Finder
icon as the card's middle, then what it is called and how big it is. It reads a selection only when
the Finder is the app the palette was summoned from, but it keeps its place in the row either way —
with nothing to report it rests on a generic glyph under `FINDER` / `No selection`, because a card
that came and went with the Finder's focus couldn't be relied on to be there.

## Arrangement

`DashboardWidgetPreferences.widgetOrder` is the strip order: every kind exactly once, kept complete so
a card switched off keeps its place for when it comes back.
`DashboardWidgetsEngine.widgetOrder(from:)` repairs whatever was saved — unknown raw values and
duplicates drop out, and any kind the saved order predates lands at the end — so a new widget appears
without a migration and the strip can index the result without a second existence check.
`DashboardWidgetsEngine.reorder(_:moving:to:)` moves one kind to the position a dragged row was
dropped on, rather than SwiftUI's `move(fromOffsets:toOffset:)` index, which is off by one downward.

The Arrangement pane draws the strip as a row of tiles in that order — filled when the card is on,
dash-outlined when it is off — and dragging one tile onto another puts it in that one's place. The
list below repeats the widgets with a description, a switch, and up/down buttons as the keyboard path
to the same reordering.

`DashboardWidgetKind.ownsEnabledState` is what keeps that one pane honest: it is false for Uptime,
whose switch is a consent act owned by `DashboardUptimeStore`, so the pane routes that one through
the store and its dialog rather than through `enabledWidgets`. Device Battery is the one card that
withholds itself even when switched on, because with nothing connected reporting a level an empty
square would claim a reading it doesn't have; every other card either has something to say or has a
resting state to say it in.

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

File Info is a third pair for the same reason as the others — the half that shells out to the Finder
stays isolated. `DashboardFileInfoStore`, owned by `AppCore`, holds the last snapshot and discards a
read that lands after a newer one; `DashboardFileInfoReader` does the Apple Event and the `stat`s off
the main actor, through `Core/FinderSelection.swift`, the one place in Spotter that asks the Finder
what is selected (Image Modification's Finder input uses the same reader).
`DashboardFileInfoEngine.swift` stays Foundation-only and pure — it decides what the card's three
lines say — so the same harness covers it.

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
matching non-cancelled event. Every access state below `fullAccess` fills the card's one content slot with what to
do about it, rather than the card going missing. A selected account that is temporarily unavailable falls back to all
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

## File Info and the Finder

`Core/FinderSelection.swift` asks the Finder for `selection as alias list` through one `osascript`
Apple Event, run off the main actor and drained before the wait. macOS asks for Automation access to
the Finder the first time; a refusal reads as an empty selection — the card simply never appears, and
macOS remembers the answer, so there is no repeat prompt. `DashboardFileInfoReader` then `stat`s each
path for its localized name, kind and size. File contents are never opened, and nothing about the
selection is persisted or sent anywhere.

A **folder is counted, not weighed**: a size for it would mean crawling an unbounded tree on every
summon. A **package is weighed**, because it is one item to the user rather than a container — its
size is the sum of its regular files, abandoned above `packageFileLimit` (20,000 files) rather than
run long. In a mixed selection the folders are named alongside the total, so the size never reads as
covering something it left out.

`AppCore.showPalette` calls `refreshDashboardFileInfo()` once per summon, and nothing watches the
Finder between summons. The store only reads when the palette's recorded `previousApp` **is** the
Finder; any other frontmost app clears the card instead of leaving a stale file on screen. While a
read is in flight the previous snapshot stays up — the Finder is still frontmost, so it is nearly
always the same selection, and clearing first would flash the card away and back.

## Settings and lifecycle

Widgets is an always-available system feature, and the only registration placed `.widgets`: it has no
Settings row of its own, contributing the sidebar's **Widgets** section between System and Plugins
instead. **Arrangement** is that section's first row and the only place a card is switched on or off;
the rest are the cards themselves — Clock, Uptime, Device Battery, Calendar, File Info — each
configured on its own rather than in a shared list of switches, and none of them carrying a
show/hide switch of its own.

Each pane holds only that card's details: the clock's time zone plus the whole weather section (its
consent switch, city, unit and last reading), the uptime card's keyboard-permission state and Reset
Today, the calendar's access, account and all-day preference. Device Battery's card is a read-out
rather than a setting — the devices found and their levels, so a Mac showing no card says why — and
File Info's is the same, explaining what is read and what never is. Uptime shows its details only
while it is on, since it is consent-gated, and points at Arrangement when it is off. Switching every
card off hides the strip.

Existing calendar-account, all-day-event and time-zone preferences remain unchanged, and saved
identifiers for removed widgets are ignored. The permission overview exposes Calendar, Accessibility
and Automation as global permissions, because the calendar card, the uptime card's key counting and
the File Info card depend on them respectively. Calendar refreshes occur only while the dashboard is
visible, while uptime counting runs whenever the widget is on — a tally of the whole day would be
wrong if it only accrued with the palette open. Permission views re-check authorization while visible
so returning from System Settings updates them without a relaunch.
