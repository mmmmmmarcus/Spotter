# World Clock plugin

World Clock is a local-only query provider and launcher-native palette screen backed by the IANA
time-zone data built into macOS. It never reads the network.

## Inline queries

Queries such as `time in London`, `SF time now`, `Tokyo time` and `上海时间` show the requested city,
its current time and date, then the system's local time for the same instant. While the inline card is
selected, → advances that instant by one hour and ← rewinds it by one hour (↑/↓ stay list
navigation). Both city and local values move together, and editing the query resets the offset.

`WorldClockEngine` remains Foundation-only and pure: callers inject the date, calendar and local time
zone. Common aliases are hand-curated, while the remaining city catalog is derived from
`TimeZone.knownTimeZoneIdentifiers`.

Each saved-city and Add City row leads with the country's flag emoji rather than a clock glyph. The
mapping is the tz database's own: `WorldClockEngine.countryCodes(fromZoneTab:)` parses the country
column purely (harness-covered), the store reads `/usr/share/zoneinfo/zone.tab` once (the store may
touch the filesystem, the engine may not), and `flagEmoji(countryCode:)` renders the ISO code as
regional indicators. A zone the table doesn't place falls back to the original symbol.

## Saved cities

Launching World Clock opens a `PluginPaletteScreenRegistration` rendered by `PluginPaletteList`.
First-run defaults are London, Shanghai and San Francisco, in that order. The screen refreshes its
clock every 30 seconds while visible, filters only the saved cities and copies a row's time on Return.

`WorldClockStore`, owned by `AppCore`, persists the ordered city IDs in bundle-scoped `UserDefaults`.
The palette screen manages the list in place: saved cities lead, and a non-empty query also surfaces
up to eight catalog matches as **Add City** rows (`add:<id>`) — ↵ adds and clears the query so the
grown list shows; ⌘K on a saved city offers Remove City. While the query is empty, **←/→ scrub every
row by ±1 hour** (the same gesture as the inline card): the offset shows in the section header as
`Cities · +3 h`, applies through `WorldClockStore.previewOffsetMinutes`, and resets on the next open.
The saved list itself syncs as `SettingsBackup.worldClockCities`.

## World map

The shared palette list has a non-selectable 6:1 cropped world map above its city rows, including when the
saved list is empty. It scrolls with the list and never changes the palette frame or selection order.
The map draws bundled Natural Earth land outlines, longitude guides, orange saved-city markers and
a solar day/night overlay. The land retains its original 2:1 projection scale; the shallow viewport
crops vertically around 30° N, rather than squeezing the continents. Taller viewports move the crop
center toward the equator so no empty margin appears beyond a pole. Cities outside the crop remain
in the complete list below. Labels prioritize the focused city and skip collisions; every city keeps
its dot and its complete time in the list below. Map content is exposed as an accessible summary.

`WorldClockMapContent` is the shared renderer with an explicit instant. World Clock's wrapper adds
its interactive scrub surface, 6:1 aspect and list spacing. Calendar details reuse the renderer at
the event's start, above notes, without the gesture surface or a live-clock subscription.

`WorldClockMapGeometry` stays Foundation-only: it parses IANA coordinates and computes an approximate
solar terminator from the injected instant using NOAA's fractional-year equations. The map uses the
same 30-second visible-only clock as the list, follows hourly scrubbing and uses the source instant
for time conversions. Dragging horizontally adjusts the shared preview two minutes per point (right backward, left forward),
so the daylight boundary follows the pointer.
It uses the gesture's total translation and its starting offset, without snapping or animation queues.
Trackpad and Magic Mouse scrolling adjust time from AppKit's already preference-adjusted deltas,
using the dominant horizontal or vertical axis, retaining fractional minutes and accepting momentum.
Both input paths use `WorldClockMapGeometry.minutesPerPoint` (2), while displayed times retain
one-minute precision.
A local native map surface handles these events without a global monitor or changing search focus;
scrolling elsewhere continues to scroll the city list. Direct dragging never moves the Palette window.
Keyboard adjustments add whole hours while retaining the minute remainder. Dragging a conversion
adjusts its resolved instant, including date rollover, and keeps its rows, labels and copied time in
sync. A new conversion query starts unshifted. Clock ticks pause during the gesture; the next open
resets all preview offsets. There is no extra timer, location request, geocoder or network access.
Coordinates come from the same system `zone.tab` read used for flags, with explicit coordinates for
San Francisco, Beijing, Mumbai and Delhi because their zones name other cities. Unplaced cities stay
in the list without a guessed map marker.

The template asset is generated with `python3 Tools/gen-world-clock-map.py <ne_110m_land.geojson>`.
See `THIRD_PARTY_NOTICES.md` for its public-domain source. The map follows system appearance through
Theme tokens. Tests cover coordinate parsing, map bounds, solstices/equinox, polar day/night and
preview/conversion clock alignment; visual sign-off is left to the user.

## Time conversion

The same field also converts: type `8pm in london` and the list becomes that instant rendered in
every configured city. There is no second field, no second screen and no second city catalog — the
rows are the saved-city rows, and `WorldClockEngine.screenIntent(for:cities:…)` decides which of the
two readings the query gets.

**Parse first, then search.** A query is a conversion only when it *starts* with a clock time;
anything else is left to city search, so `london` still adds London. A bare number is deliberately
not a clock time — the hour needs `am`/`pm` or a `:` — which is what keeps `10 downing` searching.

| Accepted | Rejected (stays a city search) |
| --- | --- |
| `8pm in london`, `8 pm london`, `8pm London` | `london`, `sao paulo` |
| `20:00 in tokyo`, `0:15 in london` | `8`, `8 london`, `10 downing` |
| `8:30pm in new york`, `8:30 pm new york` | `2000 in tokyo`, `8:5 in london` |
| `noon in tokyo`, `midnight in tokyo`, `12am`/`12pm` | `25:00`, `13pm`, `8:99pm` |
| `9am at sydney` (`in`/`at` are the connectors) | `time in london` (that is the inline card) |

A parsed time whose city words name nothing in the catalog says so — `No city called “Atlantis”` —
rather than guessing; `8pm` alone asks for a city. Trailing words are not ignored, so
`8pm in london tomorrow` is an unresolved city, not a silent conversion. Nothing here reaches the
network: the catalog is the one the rest of the plugin already uses.

**The moment is today in the source city**, taken from that city's own calendar date rather than the
Mac's, and it never rolls forward: `8pm in london` at 23:30 London time still means 20:00 *today*, an
instant in the past. Every row states its own full date, and the section header states the source
time, city and date (`8:00 PM in London · Jan 15, 2026`), so a row that lands on the next day says
so. A wall-clock time inside a spring-forward gap resolves to the instant that does exist and the
header reports *that* time (`2:30am in new york` on a US DST-start Sunday reads back as 3:30 AM); a
repeated hour after a fall-back takes its earlier occurrence.

**DST comes from the zone's real rules for that date**, never a fixed offset: the conversion builds
its instant with `Calendar.date(from:)` in the source zone, so `8pm in london` is 20:00 UTC in
January and 19:00 UTC in July, Sydney's inverted calendar puts January on +11 and July on +10, and a
zone whose rules changed historically (São Paulo, UTC−2 in January 2018 and UTC−3 in January 2020)
resolves per year. `Tools/world-clock-test.swift` pins all of those, both DST-gap cases and every
accepted and rejected input form.

Rows list the configured cities in saved order, then the Mac's own zone as **Local Time** whenever no
configured city already covers it — the answer is useless without the zone the reader is in. ↵ copies
that row's time, the same action saved-city rows carry, and ⌘K offers the same Copy Time. Conversion
rows hold no state: `AppCore` re-reads the live query to resolve the row an action names.

The plugin Settings pane searches the macOS city catalog, adds or removes cities and restores the
three defaults. Leaving the screen stops its visible-only clock task and exits an active World Clock
palette screen.

Settings keeps saved cities in the list and an Add City button in its trailing footer. The button
opens a focused search popover that excludes saved cities. Clicking a result or pressing Return on
the first match adds it and closes the popover; Escape or an outside click cancels. No-match searches
show an empty result state. Restore Defaults sits beside Add City when applicable.
