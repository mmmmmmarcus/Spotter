# World Clock plugin

World Clock is a local-only query provider and launcher-native palette screen backed by the IANA
time-zone data built into macOS. It never reads the network.

## Inline queries

Queries such as `time in London`, `SF time now`, `Tokyo time` and `上海时间` show the requested city,
its current time and date, then the system's local time for the same instant. While the inline card is
selected, ↑ advances that instant by one hour and ↓ rewinds it by one hour. Both city and local values
move together, and editing the query resets the offset.

`WorldClockEngine` remains Foundation-only and pure: callers inject the date, calendar and local time
zone. Common aliases are hand-curated, while the remaining city catalog is derived from
`TimeZone.knownTimeZoneIdentifiers`.

## Saved cities

Launching World Clock opens a `PluginPaletteScreenRegistration` rendered by `PluginPaletteList`.
First-run defaults are London, Shanghai and San Francisco, in that order. The screen refreshes its
clock every 30 seconds while visible, filters only the saved cities and copies a row's time on Return.

`WorldClockStore`, owned by `AppCore`, persists the ordered city IDs in bundle-scoped `UserDefaults`.
The plugin Settings pane searches the macOS city catalog, adds or removes cities and restores the
three defaults. Disabling the plugin stops its visible-only clock task and exits an active World Clock
palette screen.
