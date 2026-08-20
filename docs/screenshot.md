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

The selection view replaces the system pointer for the bounded session, then restores the exact
previous cursor on every exit path. Both pointers are built once from SF Symbols — `dot.crosshair`
for region mode, `camera.viewfinder` for window mode — at 24-point `.medium`, tinted `#2076FF`
through a palette symbol configuration. Spotter generates the one-point external white outline by
stamping the same glyph in white around a 24-step circle before drawing the blue body on top, so any
symbol outlines correctly without a hand-transcribed path. A two-point, 28%-black drop shadow sits
one point below that artwork, with three points of transparent canvas padding keeping the blur
unclipped. Both glyphs are ink-centered in their own canvas, so the hotspot is simply the canvas
center: 41×39 points for the crosshair, 38×36 for the viewfinder. There is no runtime SVG parsing or
second overlay-drawn pointer. Cursor rects cover each display and the cursor is set
on presentation, every inactive-panel mouse move and explicitly during a drag, so Option-key release
and the previous app's cursor rect cannot reintroduce the arrow before or after mouse-down. Because
the window server otherwise drops cursor changes from an app that is not frontmost — which left the
arrow in place until a drag grabbed the pointer — the manager enables Capso's
`SetsCursorInBackground` connection property for the selection session and clears it again when the
panels come down. Its two CoreGraphics symbols are resolved with `dlsym`, so a system that no longer
exports them simply logs and keeps the arrow instead of failing to launch. A
left-button drag is clamped to its starting display. The overlay
does not dim the screen: the panel's full-screen surface uses only one 8-bit black alpha step, which is
visually transparent but preserves the mouse hit region that macOS 26 drops for a fully clear panel.
During a drag, the selected rectangle is replaced with an exact 5%-black overlay so its extent is
clear without obscuring the source. With Rounded Corners on, both that fill and the selection border
use a four-physical-pixel radius on every display scale. Releasing the button accepts any region at
least one point in both dimensions. Escape, a secondary click or a zero-area click cancels without
touching the clipboard, and every exit path restores the cursor before removing the panels.

## Window capture mode

Space switches the live selection between region and window mode as often as the user likes; every
capture starts in region mode. The manager owns the mode and pushes it to every panel at once, so the
displays never disagree. In window mode the pointer becomes `camera.viewfinder`, dragging is inert,
and the window under the pointer is filled and outlined with the same tokens a dragged region uses.
A left click captures the highlighted window; Escape and a secondary click still cancel.

Each swap plays a short pointer transition, since a hardware cursor cannot animate itself: the
outgoing symbol shrinks to 60% while it fades out, the incoming one grows from 60% back to full size
as it fades in, and the two overlap for the middle fifth of the swap. Both stay centered on the
hotspot, so the pointer never drifts. `ScreenshotCursorAnimator` replays seven composed frames and
lands on the shared resting cursor over `Theme.Animation.quick` (140 ms), rebuilding each panel's
cursor rect per frame so a pointer move mid-swap cannot restore the previous symbol. The frames are
composed once per direction from artwork rasterized at the deepest backing scale on the Mac and only
ever shrink it, so no frame is resampled upward. The curve itself lives in the pure
`ScreenshotCursorTransition`, whose harness pins its endpoints, its monotonic progress, the overlap
and the clamped out-of-range steps.

Hit testing reads `CGWindowListCopyWindowInfo` (on-screen, desktop elements excluded) on each pointer
move and keeps the window server's front-to-back order, so the first match under the pointer is the
top-most window. The pure `ScreenshotWindowPicker` applies the filters and both coordinate flips:
Spotter's own overlay panels are excluded by process id, only layer-0 windows qualify, and windows
that are effectively invisible (alpha under 0.05) or smaller than 24 points on a side are skipped.
Window rectangles arrive top-origin relative to the primary display and are flipped into AppKit's
global space before each panel converts them to its own display-local coordinates, so a window that
straddles two displays highlights correctly on both.

Capture resolves the picked window id against `SCShareableContent` and uses
`SCContentFilter(desktopIndependentWindow:)`, so the window is captured from its own content rather
than from screen pixels: occluded parts come through, and the overlay panels can never appear in the
result. Shadows are excluded for a tight crop, the window's own rounded alpha corners are preserved,
and the Rounded Corners setting is deliberately not reapplied to a window capture. If the window
disappears between the click and the request, the capture fails through the same HUD as any other
failure.

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

## Preview and mark-up editor

The success HUD is the entry point: after a capture lands on the clipboard, "Screenshot Copied" gains
a "Click to Edit" hint, accepts the mouse and lingers 3.5 seconds (hovering pauses dismissal).
Clicking it opens the mark-up editor on the retained capture; every other HUD keeps ignoring the
mouse entirely, and the click itself never activates Spotter — opening the editor window is what
brings the app forward. The manager retains the last capture (raw pixels plus the corner treatment
the clipboard copy received) until the next capture or until the plugin is disabled, which also
closes the editor.

The editor is a resizable auxiliary window through `AppCore.showPluginWindow`, sized to the capture
at native points and clamped to 85% of the visible frame; each capture reopens it fresh on the
latest image. The toolbar offers five tools — arrow, rectangle, ellipse, freehand and text — an
eight-color palette, three stroke presets, and undo/redo (⌘Z / ⇧⌘Z). Marks are committed on
mouse-up; a sub-3-point drag is discarded as a misclick. The text tool places an inline field at the
click point (Return commits, Escape discards), rendered bold with a soft dark halo for legibility.

All annotation geometry lives in image pixel space with a top-left origin, so the live canvas and
the export share every coordinate: the SwiftUI `Canvas` hands its CGContext to the same pure
`ScreenshotAnnotationRenderer` that `flatten` uses for export, scaled by the current fit factor.
Stroke widths and font sizes are chosen in view points and resolved into image pixels at creation
time, so what is drawn at fit scale is what exports. The palette is a fixed set of content colors
baked into the pixels — deliberately not `Theme` tokens, since an exported mark must look identical
in both appearances. Copy (⌘↩) flattens off the main actor, reuses the capture pipeline's TIFF
processing and internal-type marker (including the original's corner treatment) and closes the
window; Save… (⌘S) writes a PNG through `NSSavePanel`, preserving corner transparency. Flattening
zero annotations returns the capture untouched. The harness pins the arrow-head geometry and the
flattened rectangle's edge and interior pixels.

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
