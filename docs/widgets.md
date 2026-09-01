# Widgets

Widgets is the card strip above the launcher sections when the palette is on its empty query root. It
shows an analog clock, what Apple Music is playing, connected device batteries, the next calendar
event and the Finder selection. Every card is the same 116-point square; which cards appear is set in
Settings → Widgets, and the order is set by dragging the cards in the palette itself. Typing a query or switching palette mode
hides the strip immediately.

The clock is the strip's watch face: a title-free analog dial following the selected time zone, with
live hour, minute and second hands and the dashboard's adaptive translucent surface rather than an
opaque dial. Only the quarters are numbered — 12, 3, 6 and 9 — since the tick ring already says where
the rest are. Complications ride the bezel around it the way a watch face carries them: the date is
split across three corners (month top-right, day bottom-left, weekday bottom-right), and once weather
is on and a reading has landed the temperature takes the fourth, top-left, with the condition glyph
inside the dial above the six. A corner with nothing known stays empty rather than drawing a
placeholder, so a clock with weather off is still just a clock. Weather has no card of its own: it
*is* that corner and that glyph, which is why it is configured in the Clock pane.

The clock is also the one card that spends its whole 116-point square rather than keeping the
uniform `md` margin the others do: the complications *are* its bezel, so that margin would only have
shrunk the dial. The complication arc rides at `ringInset`, which is *negative* (-4 points): the arc
is wider than the card, because the corners the labels sit in reach further out than its inscribed
circle, so the type still lands inside the rounding. The dial is held `clockFaceInset` — 6 points —
inside the card, the tightest setting where the longest corner label still clears the tick ring.

`ClockComplicationRing` sets each label **on a curve**, not square in a corner: the string is
measured character by character and each glyph is drawn at the angle its own width has reached, then
turned to stand on the tangent there, so the line follows the dial's circle. The two bottom labels
run anticlockwise and are turned over, or they would read upside down at the foot of the circle.
Resolving per character is what costs those strings their kerning — the usual trade for type on a
curve. The condition glyph is not on that ring at all: it sits level inside the dial, on the radius
between the hub and the six, since a tilted icon reads as a mistake.

The calendar card shows only what is next, and the event's own title is the headline, ranged from the
top-left corner with the time pinned to the bottom-left — an "Up Next" heading would spend the card's
best line saying what the card obviously is, and the date left for the clock's corner so a second
copy here wouldn't be the strip repeating itself. Splitting the two to opposite ends of the card is
what puts the time in the same place whether the title runs to one line or three. Clicking the card
hides the palette and opens Calendar — the card is a door to the real thing; the access-state
buttons it shows before authorization consume their own clicks first. The card and the Calendar
plugin's My Schedule screen are one feature: both read the same store's fetch, and the card's
account/access/all-day preferences live on the plugin's Settings pane
(see [calendar.md](calendar.md)); the Widgets page points there.

The File Info card states what is selected in the Finder: its kind in the title slot, its own Finder
icon as the card's middle, then what it is called and how big it is. It reads a selection only when
the Finder is the app the palette was summoned from, but it keeps its place in the row either way —
with nothing to report it rests on a generic glyph under `FINDER` / `No selection`, because a card
that came and went with the Finder's focus couldn't be relied on to be there.

## Arrangement

`DashboardWidgetPreferences.widgetOrder` is the strip order: every kind exactly once. It is also the
*only* preference the strip has — there is no on/off state, because every card shows (owner decision,
Aug 2026). A card that has nothing to report says so in its resting state, which is a better answer
than a switch the user has to find.
`DashboardWidgetsEngine.widgetOrder(from:)` repairs whatever was saved — unknown raw values and
duplicates drop out, and any kind the saved order predates lands at the end — so a new widget appears
without a migration and the strip can index the result without a second existence check.
`DashboardWidgetsEngine.reorder(_:moving:to:)` moves one kind to the position a dragged card was
dropped on, rather than SwiftUI's `move(fromOffsets:toOffset:)` index, which is off by one downward.

**The strip reorders itself, live.** Hold a card briefly and it lifts, scales up and follows the
pointer while the other cards spring out of its way, home-screen style; releasing writes the order
once. The gesture is a long-press-then-drag (`DashboardWidgetsView.reorderGesture`), so a quick
click still taps a card and a quick swipe still scrolls the list. The strip lays cards out by
computed slot offsets rather than an `HStack`, which is what lets slots change hands under a spring
while the lifted card keeps tracking the pointer. Dragging a card onto another's slot puts it in that one's
place; there is no list of names in Settings for it, because the cards are the thing being arranged
and a name is a worse handle than the card. Dashboard cards are the launcher's only non-selectable
rows, which is what makes a drag here unambiguous — it can never be confused with picking a result.
A card dropped onto a neighbour takes that neighbour's index in the order.

Device Battery is the one card that withholds itself, because with nothing connected reporting a
level an empty square would claim a reading it doesn't have; every other card either has something to
say or a resting state to say it in. A feature whose visibility would be a consent act does not
belong in the strip at all — that is why Uptime became [a plugin of its own](uptime.md).

## Architecture

`DashboardWidgetsPlugin` is the registration adapter that places this system feature in Settings.
`DashboardWidgetsStore`, owned by `AppCore`, owns EventKit authorization, the next-event snapshot,
widget preferences and the visible-only refresh task. Preferences use bundle-scoped `UserDefaults`
and participate in trusted settings backup/sync. `DashboardWidgetsEngine.swift` remains
Foundation-only and pure; it resolves preference fallbacks, clock hand angles and calendar filters
for `Tools/dashboard-widgets-test.swift`.

Music is its own pair — the half that talks to another app stays isolated. `DashboardMusicStore`,
owned by `AppCore`, owns the Apple Events, the poll timer, the player-info observer and the artwork
cache. `DashboardMusicEngine.swift` stays Foundation-only and pure: it parses the reader script's
one line and resolves the card's subtitle and resting lines for `Tools/dashboard-widgets-test.swift`.

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

## Music

The music card is the cover, and nothing else: at rest the artwork fills the square edge to edge with
no title, no scrim and no controls over it. The pointer is what reveals the transport — hovering dims
the cover and centres previous, play/pause and next on it, all three in white because they sit on
artwork that could be any colour. They act on Music directly, and each is a full-cell hit target since
a glyph alone leaves most of the control unclickable.

A track with no cover would leave a blank square, so that case shows the track's name and nothing
else until the pointer arrives. With no track at all the `music.note` mark stands alone
(owner decision, Aug 2026): "Nothing playing" restated what a bare music card already says, so the
resting words live only in Settings and the accessibility label — where "Music is not open" still
reads differently from nothing playing. There is deliberately no progress readout: the card shows
what is playing and lets you change it, and a playhead is the one thing a glance at a launcher does
not need.

Everything goes through one Apple Event run as an `osascript` subprocess off the main actor, exactly
like `Core/FinderSelection`: macOS's own Automation prompt is the gate, and a refused grant reads as
"nothing playing" rather than an error. **Spotter never launches Music.** `tell application "Music"`
starts the app if it is not running, so the store checks `NSWorkspace.runningApplications` before any
script runs; with Music closed the Settings row and accessibility label say so, which is not the same
as nothing playing. Note also
that `st` is a reserved token inside a Music `tell` block — the reader script spells its variables
out rather than abbreviating them.

The card polls every three seconds while the launcher is on screen and stops when it leaves, and it
also listens for Music's own `com.apple.Music.playerInfo` distributed notification so a track or
state change lands immediately. Between polls the playhead is interpolated from the last anchor by
`DashboardMusicEngine.interpolatedPosition` rather than asking Music every second — a subprocess per
tick would be the whole cost of the card. Artwork is re-read only when the persistent track ID
changes, written by the script to a bundle-scoped temporary file because artwork bytes cannot come
back through stdout as text; a slower artwork read never overwrites the track that replaced it. The
reader asks for name, artist, album and duration only — the playhead went with the progress bar. Note
that `osascript` always answers with a trailing newline, so `runScriptSync` trims: comparing the raw
answer to a bare `"ok"` silently discarded every cover that had just been written.

Not every track has a cover to fetch. A streamed URL track — Apple Music radio, and anything played
outside the library — reports zero artworks, and the card falls back to its plain surface rather than
inventing one; fetching a cover from the network would be a consent-gated feature, not a widget
detail.

## Device battery

The card is a grid of ring gauges, title-free and filled edge to edge like the clock — the rings
*are* the card, and a heading would cost a row of them. Each connected peripheral that reports a
level — a mouse, keyboard, trackpad, earbuds or speaker — gets one ring: a faint full track with the level swept clockwise from twelve
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

The card holds its 116-point square explicitly rather than hugging its gauges, and the grid is
**always four slots, ranged from the top-left corner** — the slots nothing fills are drawn as bare
grey tracks with no glyph in the middle, since a glyph would name a device that isn't there. That
fixed shape is the point: a device keeps its position as others connect and disconnect, instead of
the whole card re-centring and every ring changing size under the same reading. Four is the limit; a
fifth device turns the last slot into a `+2` count rather than dropping those devices unremarked.
Devices order lowest-first throughout, so whatever needs charging soonest is the first ring drawn.

The category behind each symbol comes from bluetoothd's minor type when the device came from that
scan, and otherwise from the product name. A paired device is named after its owner ("Marcus's Magic
Mouse"), so the stable part is the category noun inside it; anything Spotter doesn't recognize falls
back to a generic battery glyph and keeps its own name in Settings, rather than being guessed at
from a vendor/product table that would rot.

Levels come from two reads merged into one list. The first is the `BatteryPercent` property a HID
peripheral publishes on its `AppleDeviceManagementHIDEventService` node in the IOKit registry. The
second exists because a BLE peripheral reporting through the battery GATT service — most third-party
Bluetooth keyboards and mice, and AirPods — publishes nothing there: its level lives with
bluetoothd, and one `system_profiler SPBluetoothDataType -json` subprocess is the unrestricted route
to bluetoothd's answer. Only the connected section is read (the not-connected one carries stale
cached readings), the `device_minorType` bluetoothd names decides the category before the
product-name parse gets a say, and earbuds read as their lowest bud with the case ignored. The two
scans agree on identity through normalized addresses (IOKit spells `c0-44-...`, bluetoothd
`C0:44:...`), and on a duplicate the HID reading wins because it alone carries the charging flag —
bluetoothd reports none, so a device from that scan never gets a bolt (owner decision, Aug 2026,
superseding the earlier AirPods exclusion, whose reason was that this route hadn't been adopted).

Neither read needs a consent gate, unlike the other two non-obvious cards: any process can read the
registry, `system_profiler` only relays what bluetoothd already knows, and there is no TCC prompt,
no entitlement and no permission to explain. IOBluetooth and CoreBluetooth remain off-limits — they
require `NSBluetoothAlwaysUsageDescription` and prompt for Bluetooth access process-wide, a system
permission for one card. Nothing is persisted and nothing leaves the machine.

The card is hidden whenever nothing connected reports a level, since an empty square would imply a
reading it doesn't have — a Mac with only a built-in keyboard is the normal case, not a fault. That
hiding is why the scan also runs from `AppCore.showPalette`: the card's own poll lives with the card,
so with the card unrendered nothing else would notice a device that has since connected. The registry
scan is a handful of property reads, measured at ~0.03 ms, so it runs synchronously on the main
actor; while the card is on screen it repeats once a minute, which is as fast as a whole percent
moves. The Bluetooth read is a ~0.2 s subprocess, so it runs off the main actor, re-publishes when it
lands, and reuses an answer younger than 30 seconds rather than respawning `system_profiler` on
every palette open.

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

Widgets is an always-available system feature placed under Settings → System, and the whole strip is
configured on **one page**: a section per card — the clock's time zone, the weather section, what
Music is playing, the devices found and their levels, the calendar's access, account and all-day
preference, and what File Info reads and never reads. There is no Show list, no pane of its own for
any card and no arrangement list: every card shows, and order belongs to the palette.

Weather's section is the one that reads unusually: it has no switch, because it is three
complications on the clock rather than a card of its own. Choosing a city is what turns it on and
removing the city is what turns it off, which leaves one control instead of two without touching the
gate — the consent dialog still names the provider, the cadence and what leaves the Mac before
anything is contacted.

Existing calendar-account, all-day-event and time-zone preferences remain unchanged, and saved
identifiers for removed widgets are ignored. The permission overview exposes Calendar and
Automation as global permissions, because the calendar card depends on the first and both the Music
and File Info cards on the second. Calendar refreshes and Music polling occur only while the
dashboard is visible: neither has anything to report to a closed palette. Permission views re-check authorization while visible
so returning from System Settings updates them without a relaunch.
