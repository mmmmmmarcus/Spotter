# Uptime

Uptime is a native built-in plugin under `Spotter/Plugins/Uptime/`. `AppCore` owns its `UptimeStore`;
the registration contributes the launcher command, a bindable shortcut, the Accessibility permission
declaration and the Settings pane. It began as a card in the launcher's widget strip and became a
plugin in August 2026 (owner decision): a reading most people check rarely earns a command rather
than a permanent square in the strip.

## Entry points

`Uptime` is available from the launcher and from its own shortcut, and opens as a palette screen
through the shared `PluginPaletteList`, like World Clock. Three rows: the session and how long it has
run, today's key presses, and today's mouse clicks. ↵ copies the row's value; ⌘K also offers **Reset
Today**, which asks first through the in-palette confirmation card.

Uptime is **always on**, with no switch and no consent dialog (owner decision, Sep 2026). Its
persistence keys keep their `dashboard-widgets.uptime-*` names from the widget era; the consent key
that used to sit beside them is no longer read or written. Nothing about Uptime travels in the
settings snapshot — the tallies are device-local and there is no longer a flag to carry.

## Reading and input privacy

The session row reads *hours since the screen first came on today*, over today's key-press and
click tallies. Elapsed time is wall clock, so a mid-day sleep counts; the day's start is stamped on
its first sign of activity — a woken screen, a resumed session or a counted event — and never at
midnight, so a Mac left awake overnight doesn't claim a session since 00:00. A sleeping display is
not a sign of activity, so a 4am background wake can't start the day either. Tallies survive a
relaunch and clear at midnight. `Reset Today` in Settings and in the palette's ⌘K menu clears them
without disturbing the start stamp.

Counting input system-wide runs without a gate, and what makes that defensible is how little is
taken. The counters take two facts off an event — key or click, and whether a key was an autorepeat —
and increment an integer. Key codes, characters, modifiers and click locations are never read, so
nothing retained can reconstruct what was typed, nothing identifies anything, the tallies clear at
midnight and none of it ever leaves the Mac. There is no ongoing access here for a switch to
withdraw; keep it that way, and keep the counters counters.

Counting runs through `NSEvent` monitors rather than a fourth `CGEventTap`: a global monitor is
passive by construction and cannot alter or swallow an event. A local monitor sits beside it, since
global monitors never see events delivered to Spotter itself and the palette's own keystrokes would
otherwise go uncounted. Key events need the Accessibility grant and clicks do not, so an untrusted
Mac still counts clicks and both the rows and Settings offer the grant instead of showing a
misleading zero. AppKit hands back a monitor token either way, so trust is polled on the same timer
that flushes the tallies, and the monitors are re-registered once it is granted.

Tallies are coalesced and written at most every five seconds, plus on `applicationWillTerminate`;
they stay in bundle-scoped `UserDefaults`, are device-local, and travel in no backup or sync file.
