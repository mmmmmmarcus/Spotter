# Screenshot

Screenshot is a native built-in plugin under `Spotter/Plugins/Screenshot/`. `AppCore` owns its
`ScreenshotManager`; the plugin registration contributes the launcher command, global shortcut,
Screen Recording permission declaration and Settings pane.

## Entry points

`Capture Screenshot` is available from the launcher and defaults to Option-Z on a fresh install.
The default is seeded once: changing or clearing the binding is respected on later launches. Turning
the plugin off preserves its binding, cancels an active selection and makes the shortcut a no-op.
The Carbon callback schedules capture on the next main-run-loop turn so panel creation starts after
the hotkey event has returned.
Repeated shortcut events are ignored while a selection or pixel capture is already active, preventing
key repeat from cancelling and rebuilding the selection panels underneath the pointer.
The menu-bar menu also exposes `Capture Screenshot` as a direct click target. It deliberately routes
through the registered shortcut action, including its deferred handoff, so this entry exercises the
same enabled-state and capture path as Option-Z instead of bypassing shortcut dispatch.

## Region selection

Invoking capture creates one borderless panel per display at the screen-saver window level. Spotter
does not activate: each overlay is a `.nonactivatingPanel`, explicitly receives mouse events and
accepts the first click while the user's current app remains frontmost. Its content rect is the
display's global frame, with no second screen-relative offset, so displays left of or below the
primary remain covered. Each panel uses Capso's prevents-activation window flag before becoming key,
so AppKit routes pointer and Escape events without bringing Spotter to the front.

The system cursor is hidden once for the short selection session and the overlay draws a black/white
reticle at the current pointer position. This avoids relying on another application's cursor ownership
or on Option-key release timing. A left-button drag is clamped to its starting display. The overlay
does not dim the screen: the panel's full-screen surface uses only one 8-bit black alpha step, which is
visually transparent but preserves the mouse hit region that macOS 26 drops for a fully clear panel.
During a drag, the selected rectangle is replaced with an exact 5%-black overlay so its extent is
clear without obscuring the source. With Rounded Corners on, both that fill and the selection border
use a four-physical-pixel radius on every display scale. Releasing the button accepts any region at
least one point in both dimensions. Escape, a secondary click or a zero-area click cancels without
touching the clipboard, and every exit path balances the cursor hide before removing the panels.

The pure `ScreenshotGeometry` normalizes drag direction, clamps local points and flips a display-local
AppKit rectangle into ScreenCaptureKit's display-local top-origin space. Its standalone harness pins
normal, reverse, clamped and secondary-display coordinates without depending on the display's global
origin.

## Rounded corners

Rounded Corners is on by default and persists under the bundle-scoped
`screenshot.rounded-corners` preference. It is included in trusted Settings Backup/Sync and applied
live through `ScreenshotManager`. Turning it off makes both the selection border and copied image
square.

When enabled, `ScreenshotImageProcessor` clips the captured `CGImage` to a four-pixel rounded path
and encodes a TIFF with transparent corner pixels off the main actor. Regions narrower than eight
pixels clamp the radius to half their shortest side rather than producing invalid geometry.

## Capture and clipboard

Screen pixels are protected by macOS Screen Recording permission. The manager checks that grant at
every invocation and requests it before showing selection panels. No monitor, timer or background
capture remains active between invocations.

After selection, every overlay panel is hidden and WindowServer gets one frame to remove the border.
The manager resolves the selected `CGDirectDisplayID`, creates an `SCContentFilter` for that display,
uses its native point-to-pixel scale and asks `SCScreenshotManager` for only the display-local source
rectangle. The result is
written to `NSPasteboard.general` as TIFF together with `ClipboardManager.internalType`, so the
Clipboard plugin does not re-ingest Spotter's own write. The image is not saved to disk and a small
non-activating HUD reports success or failure.

No capture panel, event monitor, ScreenCaptureKit object, timer or background task exists while the
plugin is idle. The interaction architecture is adapted from Capso revision
`81c7ce50023b9b56d5b1ab569f0abd4551fcf2b1`; its Business Source License 1.1 is retained in
`Spotter/Plugins/Screenshot/Capso-BSL-1.1.txt` and embedded in the app bundle.
