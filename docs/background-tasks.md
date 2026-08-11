# Background tasks

Spotter can return to the normal launcher immediately after starting long-running local work. The
feature manager still owns and executes that work; `BackgroundTaskStore` owns only the progress
snapshot that remains visible to the user.

## Ownership and lifetime

`AppCore.backgroundTasks` is the single `@MainActor` owner. A feature begins a task with a title,
detail and symbol, then updates it by UUID and finishes it as Done or Failed. New tasks appear first.
Running tasks cannot be dismissed; finished tasks remain until the user selects one and presses
Return. The store is deliberately in-memory: closing or switching the palette never loses a task,
but terminating Spotter also terminates this UI lifetime rather than pretending a child process can
be recovered safely after relaunch.

The executing manager remains responsible for cancellation policy and work isolation. Background
tasks do not spawn processes, own network requests or mutate feature state themselves.

## Launcher integration

Every task is a selectable launcher row above the dashboard, inline answer and app results. Tasks
remain visible while the launcher query changes. Their rows are part of the same flat selection
model:

1. background tasks, newest first;
2. the optional inline calculator/plugin answer;
3. ordinary launcher results.

A running row shows determinate progress when its feature can estimate a total and an indeterminate
indicator otherwise. A Done or Failed row exposes only **Dismiss**; it has no Actions menu. Any task
keeps compact mode expanded so progress cannot be hidden in the slim search bar.

## Mole

All state-changing Mole actions use this surface. Confirmation still happens in-palette first. After
confirmation, Mole runs off-main while Spotter resets to the launcher. Clean, Optimize and Purge
compare streamed completed items with their preview count when possible; Uninstall reports streamed
status without inventing a percentage. Completion and failure stay in the first launcher section
until dismissed.
