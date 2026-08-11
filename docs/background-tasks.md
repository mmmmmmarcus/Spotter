# Background tasks

Spotter can return to the normal launcher immediately after starting long-running work. The
feature manager still owns and executes that work; `BackgroundTaskStore` owns only the progress
snapshot that remains visible to the user.

## Ownership and lifetime

`AppCore.backgroundTasks` is the single `@MainActor` owner. A feature begins a task with a title,
detail and symbol, then updates it by UUID and finishes it as Done or Failed. New tasks appear first.
Running tasks cannot be dismissed; finished tasks remain until the user selects one and presses
Return. Rows enter trusted v3 backups and automatic sync. A device identifier distinguishes remote
progress from this Mac's executor: a local task that was still running when Spotter quit returns as
Failed after relaunch, while a row owned by another live Mac can keep receiving remote progress.

The executing manager remains responsible for cancellation policy and work isolation. Background
tasks do not spawn processes, own network requests or mutate feature state themselves.

## Launcher integration

On an empty launcher, the non-selectable Dashboard Widgets strip comes first, background tasks come
next, and Favorites follows them. Once a query is typed the dashboard disappears, so tasks again
become the top visual section. Tasks remain visible while the query changes. Their rows are part of
the same flat selectable-row model:

1. background tasks, newest first;
2. the optional inline calculator/plugin answer;
3. ordinary launcher results.

A running row shows determinate progress when its feature can estimate a total and an indeterminate
indicator otherwise. A Done or Failed row exposes only **Dismiss**; it has no Actions menu. Any task
keeps compact mode expanded so progress cannot be hidden in the slim search bar.

## Integrated work

The current one-shot work integrated with this surface is:

- every state-changing Mole action: Clean, Optimize, Purge and Uninstall;
- every Image Modification operation, including multi-image batches and Vision work;
- every user-authored shell command, which intentionally has no timeout;
- Empty Trash, Eject All Disks and Dismiss Notifications from Commands; and
- the one in-flight Spotter AI reply.

Mole and image batches publish determinate progress when they have a trustworthy total. Uninstall,
custom commands, system commands and AI requests stay indeterminate rather than inventing a
percentage. Feature-owned cancellation (such as Stop Waiting or disabling Image Modification)
discards the running row; user dismissal remains limited to Done and Failed rows.

Updater installation is deliberately excluded because it replaces and relaunches Spotter. Mole previews and disk analysis remain attached to their
result screens because their output is the screen itself and those reads are cancellable. Caffeinate
and clipboard polling are ongoing services, not dismissible one-shot tasks. Automatic refreshes,
indexing and rate/dashboard updates are not user-started work and do not enter the launcher.
