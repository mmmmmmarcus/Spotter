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

The plugin ships off, and its switch *is* the consent act — the registration reads and writes its
enabled state straight through the store, so a monitor can never be running under a plugin the user
believes is off. Turning it on from the palette asks the same question Settings does, through the
confirmation card. `exportsEnabledState` is false: only the store's own flag travels, in the trusted
settings snapshot. Its persistence keys keep their `dashboard-widgets.uptime-*` names from the widget
era — renaming them would silently drop existing consent and tallies.

## Reading and input privacy

The session row reads *hours since the screen first came on today*, over today's key-press and
click tallies. Elapsed time is wall clock, so a mid-day sleep counts; the day's start is stamped on
its first sign of activity — a woken screen, a resumed session or a counted event — and never at
midnight, so a Mac left awake overnight doesn't claim a session since 00:00. A sleeping display is
not a sign of activity, so a 4am background wake can't start the day either. Tallies survive a
relaunch, clear at midnight, and clear when the plugin is turned off. `Reset Today` in Settings
clears them without disturbing the start stamp.

Counting input system-wide is not networked, but it gets the same consent shape: the plugin ships
off, enabling it goes through a dialog naming exactly what is and isn't recorded, and no monitor is
installed until then. The counters take two facts off an event — key or click, and whether a key was
an autorepeat — and increment an integer. Key codes, characters, modifiers and click locations are
never read, so nothing retained can reconstruct what was typed.

Counting runs through `NSEvent` monitors rather than a fourth `CGEventTap`: a global monitor is
passive by construction and cannot alter or swallow an event. A local monitor sits beside it, since
global monitors never see events delivered to Spotter itself and the palette's own keystrokes would
otherwise go uncounted. Key events need the Accessibility grant and clicks do not, so an untrusted
Mac still counts clicks and both the rows and Settings offer the grant instead of showing a
misleading zero. AppKit hands back a monitor token either way, so trust is polled on the same timer
that flushes the tallies, and the monitors are re-registered once it is granted.

Tallies are coalesced and written at most every five seconds, plus on `applicationWillTerminate`;
they stay in bundle-scoped `UserDefaults` and are device-local. Only the consent flag travels in the
trusted settings backup/sync file — restoring one may switch counting on, which is itself the consent
act.
