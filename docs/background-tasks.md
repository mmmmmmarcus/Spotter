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

On an empty launcher, the non-selectable Widgets strip comes first, background tasks come
next, and Favorites follows them. Tasks are a resting-state surface, not a search result: **typing a
query hides them**, because a query is a request for something else and the rows would otherwise sit
above every match. They return the moment the query is cleared. On the empty launcher their rows are
part of the same flat selectable-row model:

1. background tasks, newest first;
2. the optional inline calculator/plugin answer;
3. ordinary launcher results.

A running row shows determinate progress when its feature can estimate a total and an indeterminate
indicator otherwise. Return on a running row **opens the surface doing the work** — the footer reads
Open — when its feature registered an activation with `begin(onOpen:)`. Activations are process-local
by necessity: a closure cannot be synced, and a row mirrored from another Mac has no local work to
open, so those rows stay inert. A Done or Failed row exposes only **Dismiss**; it has no Actions menu,
and its activation is dropped when it finishes. Any task keeps compact mode expanded so progress
cannot be hidden in the slim search bar.

## Integrated work

The current one-shot work integrated with this surface is:

- every state-changing Mole action: Clean, Optimize, Purge and Uninstall;
- every Image Modification operation, including multi-image batches and Vision work;
- the one in-flight Spotter AI reply, which is also the only task with an activation today: Return
  switches to that conversation and opens the chat. The row exists to carry a reply the user walked
  away from, so a reply that lands while the palette is showing that very session is **discarded
  rather than completed** — they have already read it, and there is nothing to come back to.

Mole and image batches publish determinate progress when they have a trustworthy total. Uninstall
and AI requests stay indeterminate rather than inventing a percentage. Feature-owned cancellation
(such as Stop Waiting or disabling Image Modification) discards the running row; user dismissal
remains limited to Done and Failed rows. Built-in and custom Commands deliberately use the brief HUD
instead of this persistent surface.

Updater installation is deliberately excluded because it replaces and relaunches Spotter. Mole previews and disk analysis remain attached to their
result screens because their output is the screen itself and those reads are cancellable. Caffeinate
and clipboard polling are ongoing services, not dismissible one-shot tasks. Automatic refreshes,
indexing and rate/dashboard updates are not user-started work and do not enter the launcher.
