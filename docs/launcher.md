# App launcher & fuzzy match

`AppIndex.scan()` runs off-main, enumerates the user's search scopes, and dedups by bundle ID (the
earliest scope wins).

## Search scopes

`SearchScopes` (`Core/SearchScopes.swift`) owns the paths; the list is user-editable in General
Settings and persisted as `AppSettings.searchScopes`. A scope is either a directory or a single `.app`
bundle, stored tilde-abbreviated so the UI reads cleanly and a settings backup stays portable.

Enumeration **descends one subfolder deep**. A vendor folder such as `/Applications/Adobe` or
`/Applications/Blackmagic Design` is therefore indexed without being added as its own scope; anything
nested deeper still needs one, which keeps the list honest at the level that matters. The walk is
bounded twice over: a fixed depth of 1, and an `.app` is always a leaf, so it never opens a bundle's
own `Contents/` tree looking for helper apps. (The one-level walk was measured against the older flat
list over the real default set: same apps, same ~0.5 ms once `Bundle()` metadata reads are counted.)

`/Applications/Utilities` and `/System/Applications/Utilities` stay in the defaults even though their
parents now reach them — the scan dedups by bundle ID, so the overlap costs one extra directory
listing and changes nothing about the result.

The defaults cover `/Applications` and `/System/Applications` plus their `Utilities` folders,
`/System/Library/CoreServices/Applications`, the cryptex apps under
`/System/Volumes/Preboot/Cryptexes/App/System/Applications` (this is the only place Safari really
lives — `/Applications/Safari.app` is a symlink flagged hidden, so `.skipsHiddenFiles` never sees it),
`~/Applications`, and `/System/Library/CoreServices/Finder.app`.

Finder ships as an individual bundle scope rather than by adding `/System/Library/CoreServices`, which
holds ~120 background-agent bundles. There is no reliable way to filter those: `LSUIElement`,
`LSBackgroundOnly` and "declares no icon" each also exclude legitimately launchable apps — Raycast,
Stats, Spotter itself, Mission Control, Siri, Time Machine, Screenshot, System Information, Font
Book. Don't reintroduce such a heuristic.

`AppIndex.start(settings:)` observes `$searchScopes`, so an edit re-indexes immediately; overlapping
refreshes collapse into a single trailing scan.

## Searchable fields

An app is matched on five fields kept deliberately separate — flattening them into one string would
lose the thing that decides the ranking. `SearchRelevance.score` evaluates each independently and the
strongest one becomes the entry's base relevance:

| Band | Field | Match strength |
| --- | --- | --- |
| 7 | the user's own alias | literal — exact / prefix / word-start / substring |
| 6 | display name (plus a snippet's keyword) | literal |
| 5 | Spotlight alternate names | literal |
| 4 | the user's own alias | subsequence |
| 3 | display name | subsequence |
| 2 | Spotlight alternate names | subsequence |
| 1 | bundle identifier | literal only |
| 0 | executable name (`CFBundleExecutable`) | literal only |

Bands sit one `SearchRelevance.bandStride` apart, which is an order of magnitude wider than
`FuzzyMatch`'s whole range — so a field can never reach the band above it, and the learned frecency
boost (capped well below a stride) still reorders inside a tier without ever crossing one.

A *literal* hit on a weaker field outranks a *subsequence* hit on a stronger one. That is the point of
the split: an alias the vendor actually declared (`Codex` for ChatGPT) must beat the incidental
c-o-d-e…x scattered through an unrelated app's name, while a real prefix hit on a display name still
wins outright.

Identifier fields never subsequence-match — reverse-DNS text is a subsequence of nearly every short
query (`cop` ⊂ `com.apple.Photos`), which would change *which* apps appear rather than just their
order. For the same reason a bundle id is matched with its leading component stripped
(`apple.Photos`, not `com.apple.Photos`): `com` alone prefixes almost every installed app. The full id
still matches exactly, so a pasted identifier resolves.

### User aliases

Every launcher entry can carry one alias of the user's own — Raycast-style — set from the row's ⌘K
Actions menu (**Set Alias**, which opens an in-palette editor card) or inline in Settings ▸ Shortcuts.
`AliasStore` (`Core/AliasStore.swift`) persists one alias per `preferenceKey` in UserDefaults, keyed
exactly like favorites and learned ranking, and rides settings backups and sync as `launcherAliases`.
It is data rather than a capability — an alias grants nothing, it only renames — so an untrusted
restore may carry it.

`AppIndex` folds the alias in at *rank* time rather than storing it on the entry, so editing one never
forces a rescan; the store's revision counter joins the match-cache key, since an edit reorders the
same query over the same apps. A row shows its alias as a small chip after the name.

The alias is simply the **strongest field**: it matches on exactly the same terms as a display name,
literal and subsequence alike, and takes the top band of whichever group it lands in. So an alias
`figalias` is found by `fig`, by `alias`, and by `fga` — and in each case it outranks the same hit on
any vendor-supplied field.

### Alternate names

`SpotlightNames` reads `kMDItemAlternateNames` — the aliases macOS itself knows an app by, which no
Info.plist key exposes: `iBooks` for Books, `iCal` for Calendar, `Address Book` for Contacts,
`System Preferences` for System Settings, `browser` / `浏览器` / `사파리` for Safari. `MDItem.h` exports
no constant for the attribute, so it is named directly.

Spotlight mixes junk in with the real aliases, and `SearchFields.usableAlternateNames` (pure, covered
by the harness) drops it: every bundle lists its own `<Name>.app` file name, several system apps ship
untranslated `ALTERNATE_NAME_1` placeholders, and some just repeat the display name. Indexing those
would make `app` match the entire index.

A Spotlight round trip costs ~0.8 ms per bundle cold — 76 ms over the default scopes — and the scan
reruns on every launcher open, so `SpotlightNames.Cache` memoizes per bundle path and re-reads only
when the bundle's modification date moves, taking later passes to ~0.2 ms. Each pass is seeded from
the last and keeps only what it looked at, so uninstalled apps fall out instead of accumulating.
`.appex` Settings panes carry no alternate names, so `SettingsPaneScanner` doesn't ask.

> **Invariant:** `Tools/fuzz-test.swift` compiles the real `Spotter/Core/SearchRelevance.swift`, so
> that file must stay Foundation-only and pure. There is no copy of the scorer to keep in sync.

## Commands

`PluginRegistry` supplies commands from enabled native plugins — a static slice per registration plus
a runtime-varying one from `dynamicLauncherCommands` (a user's saved quicklinks or shell commands),
republished by `reloadDynamicCommands(for:)` whenever the owning store changes. Core and plugin
commands are alphabetized into the same final section, so they reuse fuzzy
ranking, favorites, visibility, keycap rendering and the launcher's flat selection; the registry's
entries win over a `CommandRegistry` id they republish (quit-all). Toggling a plugin rebuilds only
this in-memory command slice; it does not rescan applications.

A command row normally draws an SF Symbol tile, but `AppEntry.iconFilePath` lets it borrow a real
bundle's icon — a quicklink shows the icon of the app that will open it.

Core application commands remain in `CommandRegistry`. **Check for Updates** opens the Software
Update palette sub-screen and performs a fresh manual check; it observes the same `UpdateStore` used
by General Settings and carries the flow through download, signature verification, replacement and
relaunch without leaving the launcher.

**Spotter Version** is another ordinary core command rather than a query special case. Its display
name participates in the same fuzzy ranking as every other entry, while its trailing label shows the
running bundle's channel-aware short version (for example `1.4.13-dev`). Activating it opens About,
where the build number is also shown.

### Settings ▸ Shortcuts

Everything the launcher can open is one list there, grouped: **Applications**, **System Settings**,
then **Commands** split by whoever publishes them — Spotter's own built-ins first, then a heading per
plugin in catalog order, with the Commands plugin contributing two (**System** for the fixed macOS
actions, **Custom Commands** for the user's shell commands, since one heading over both would read as
one feature). Grouping resolves through `PluginRegistry.commandOwner(ofCommandID:)` rather than a
second hand-kept table of id prefixes, so a new plugin's commands group themselves.

Every heading folds, at both levels, and carries the number of rows beneath it — that count is what
keeps a folded heading informative, since collapsing would otherwise hide both the rows and the fact
that there were any. Folds persist in bundle-scoped `UserDefaults` but are deliberately **not** in
the settings backup: a synced Mac inheriting someone else's folded list would be restoring a view,
not a setting. A typed query overrides every fold, because a heading that hid its own matches would
read as no match at all.

There is deliberately **no category-level "show in launcher" switch**: every category is always on,
and an individual row's checkbox is the only way to hide something. The list never applies the
visibility filter to itself, so a hidden row stays re-checkable. A file written while categories
could be hidden still decodes, but its `hiddenLauncherKinds` are read and ignored rather than
restoring a hidden category no UI could bring back.

A registration may mark a secondary command `defaultVisible: false`. `AppCore.start()` seeds that
visibility exactly once, after which the normal visibility store and System → Shortcuts own the user
choice. Change Case uses this for its 21 direct transformations and Window Management for 20 of its 30
commands, so the default command list stays compact.

For the Commands plugin, only the display name is indexed. Activation resolves the stable UUID through
the store and dispatches to `ShellCommandRunner`; see [custom-commands.md](custom-commands.md) for
persistence, toggling, hotkeys and execution semantics.

Plugin command activation routes through the registration's in-process closure; see
[plugins.md](plugins.md). It never goes through the custom shell-command runner.

The ranking harness covers prefix learning, frequency/recency scoring, persistence, and both reset
paths; see the command in `development.md`.
The bounded learned ranking records enter trusted v3 backups and automatic sync; a reset therefore
propagates instead of being repopulated by stale records on another Mac.

Icons go through a byte-capped `NSCache` (`IconCache`, 32 MB, cost = decoded bitmap bytes).

## Browse sections

The empty-query launcher browses in sections — Favorites, Active Apps, Applications, System
Settings, Commands — whose order and visibility live in Settings → General → Launcher Sections
(`AppSettings.launcherSectionOrder` / `launcherHiddenSections`, both synced; the pure
`LauncherSectionsEngine` repairs whatever was saved, harness-covered). Hiding a section hides it
from browsing only: search always matches everything, and hiding Favorites returns its apps to the
Applications pool rather than losing them. The flat results array is rebuilt in section order
(`RootPaletteView.launcherBrowseLayout`), so the flat selection index and the visible row order stay
one and the same — the critical invariant is untouched.

Active Apps ships hidden. Enabled, it lists the running regular apps (pulled out of Applications so
nothing appears twice) with a live CPU · memory reading on the trailing edge, summed per app bundle
from one `ps` snapshot every few seconds (`RunningAppsMonitor.startUsageSampling`) — sampling runs
only while the palette is on screen.

## Background tasks

Long-running work is pinned below the empty-query dashboard and above Favorites; while a query is
typed, the dashboard disappears and tasks remain above every result. `BackgroundTaskStore` supplies
the rows; feature managers own the actual work and publish progress snapshots into it. The flat
selectable-row order is background tasks, the optional inline answer, then apps and commands. A
running task cannot be dismissed. Done and Failed rows remain until selected and dismissed with
Return. See [background-tasks.md](background-tasks.md).

## Query destinations

Every non-empty launcher query appends four explicit `Try With` rows after its normal results: send to
Spotter's AI Chat, send to ChatGPT on the web, run in Terminal, and search files in Finder. If there
are no normal or inline results, this group replaces the empty state. These are transient rows backed
by the current query; they never enter the app index, ranking, favorites, visibility settings or
command registry.

In the flat selection order the rows follow background tasks, the optional inline answer, and every
app/command match. AI Chat reuses the normal fresh-session send path and preserves the draft when no
OpenRouter key is configured. ChatGPT reuses the encoded web handoff. Terminal receives the command
in the user's preferred terminal (General → "Run in Terminal uses"; `AppSettings.preferredTerminal`,
synced): Terminal and iTerm2 get it as one `osascript` argv value — never interpolated into
AppleScript source — while Ghostty, Alacritty and kitty launch with the command as their own `-e`
shell input, followed by an `exec zsh -i` so the window outlives it. The picker lists only installed
terminals. Either way it executes in a new shell only after the user activates
that row; file search uses macOS's native Finder search. Both external-app actions dismiss Spotter
without restoring focus.

## Reveal in Finder

Application and System Settings results expose **Show in Finder** in their ⌘K Actions menu and on
**⌘↵**. Synthetic command results have no filesystem location, so neither the menu row nor the
shortcut is available for them. `AppEntry.canRevealInFinder` is the one rule both the menu row and
the key handler read, so the advertised chord can't drift from the behavior.

## Quitting apps

`RunningAppsMonitor` (live from `NSWorkspace` launch/terminate notifications) drives both the row's
running dot and the availability of the quit actions:

- **Quit Application** — the last row of an app's ⌘K Actions menu, shown only while that app is
  running, also bound to **⌃⇧Q** on the selected row. The chord guard mirrors the menu row's
  condition (an `.application` entry that `RunningAppsMonitor` reports running) so the key never
  swallows a press it won't act on, and it's skipped in the compact bar, which shows no selection.
  `AppLauncher.quit(bundleID:)` terminates every instance of the bundle and reports whether
  anything was running; the palette only dismisses when something was, and it restores focus unless
  the app it just quit *was* `previousApp`.
- **Quit All Applications** — normally the Commands plugin's read-only built-in (`AppCore.runCommand`
  dispatches `plugins.performCommand` first, and `AppIndex.publishEntries` drops the registry's
  duplicate id while Commands publishes it). With Commands disabled, the `CommandRegistry`
  fallback runs `AppCore.quitAllApps()`: `AppLauncher.quitAllTargets()` is the policy (every
  `.regular` app except Finder — `terminate()` only relaunches it — and Spotter, excluded by PID
  because About/Settings temporarily flips it to `.regular`), the list resolves **once**, the
  in-palette confirmation card asks, and exactly what was confirmed terminates.
- **Uninstall with Mole** — appended to an application row's ⌘K menu when the Mole plugin is enabled
  and the CLI installed (never for Spotter itself). It confirms in-palette, then resolves the exact
  copy and uninstalls entirely as a background-task row ([mole.md](mole.md)).

Both quits are graceful `NSRunningApplication.terminate()`, so an app with unsaved work still puts up
its own save sheet.

The ⌘K menu samples `isRunning` **once, when it opens** (`RootPaletteView.openActions()`), so an app
launching or quitting elsewhere can't add or drop the Quit row while the menu is up — the same freeze
the rest of the menu already has ([palette.md](palette.md)). Only `LauncherList` observes
`RunningAppsMonitor` live, for the running dot.
