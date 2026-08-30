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
Pressing the shortcut again while a selection is up **cancels** it: the overlay is deliberately
near-invisible, so the shortcut that opened it is what a stuck user reaches for, and a no-op there is
a dead end. Presses within 0.4s of the selection opening are still ignored — that is key repeat,
which must not tear the panels down and rebuild them under the pointer. A press during the pixel
capture that follows a selection is ignored too.
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
previous cursor on every exit path. The pointers are built once from SF Symbols — `dot.crosshair`
for the screenshot and OCR modes, `eyedropper` for the colour picker — at 24-point `.medium`, tinted
`#2076FF` through a palette symbol configuration (OCR keeps the crosshair and only swaps the tint to
orange). Spotter generates the one-point external white outline by
stamping the same glyph in white around a 24-step circle before drawing the body on top, so any
symbol outlines correctly without a hand-transcribed path. A two-point, 28%-black drop shadow sits
one point below that artwork, with three points of transparent canvas padding keeping the blur
unclipped. The glyphs are ink-centered in their own canvas, so the hotspot is simply the canvas
center — except the eyedropper, which samples at its tip: its hotspot is scanned to the solid-ink
pixel nearest the artwork's bottom-left corner, a scan that survives any SF Symbol redraw while the
soft shadow stays below the alpha threshold. There is no runtime SVG parsing or
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
During a drag, the selected rectangle is replaced with an exact 5% overlay so its extent is
clear without obscuring the source. Both that fill and the selection border follow the system
appearance — white on dark, black on light — since a black outline disappears into a dark desktop. With Rounded Corners on, both that fill and the selection border
use a four-physical-pixel radius on every display scale. Releasing the button accepts any region at
least one point in both dimensions. Escape or a zero-area click cancels without touching the
clipboard — a right click deliberately does not: it is the window capture (below) — and every exit
path restores the cursor before removing the panels. Escape
arrives two ways: the selection view's own `keyDown`, which only fires when the overlay actually
holds keyboard focus, and — because that depends on what was frontmost when the shortcut fired — a
transient Carbon key held for the life of the selection and released with the panels, the same
mechanism the preview thumbnail uses for Return.

## One picking mode, three outputs

Space cycles what the session produces — screenshot → OCR → colour picker → back around — as often
as the user likes, and every capture starts in screenshot mode: no mode is sticky across
invocations. The gestures live inside the mode rather than being modes themselves: in screenshot
mode a left drag selects a region, a right click captures the window under the pointer, and each
display's glass button captures that whole screen. OCR and the colour picker have their own
sections below.

Switching mode swaps the pointer outright rather than animating between symbols. The pointer *is*
the mode indicator, so it has to be legible the instant the key lands — including for a pointer that
is not moving. Rebuilding the cursor rects is what stops a later pointer move from restoring the
previous symbol, but AppKit drops the live pointer to the arrow while it rebuilds and only re-applies
a rect's cursor once the pointer enters it, so the cursor is set again after the rebuild as well as
before it. Without that second pass a stationary pointer sat on the plain arrow until the user
twitched the mouse. The manager owns the mode and pushes it to every panel at once, so the
displays never disagree.

## Window capture

A right click captures the window under the pointer instantly — no hover highlight and no
confirmation pass, because a right click is a fast action, so the hit test runs once at the click
itself. It is inert mid-drag, outside screenshot mode, and over nothing eligible, which is a no-op
that leaves the selection up rather than a cancel.

Hit testing reads `CGWindowListCopyWindowInfo` (on-screen, desktop elements excluded) and keeps the
window server's front-to-back order, so the first match under the pointer is the
top-most window. The pure `ScreenshotWindowPicker` applies the filters and both coordinate flips:
Spotter's own overlay panels are excluded by process id, only layer-0 windows qualify, and windows
that are effectively invisible (alpha under 0.05) or smaller than 24 points on a side are skipped.
Window rectangles arrive top-origin relative to the primary display and are flipped into AppKit's
global space.

Capture resolves the picked window id against `SCShareableContent` and uses
`SCContentFilter(desktopIndependentWindow:)`, so the window is captured from its own content rather
than from screen pixels: occluded parts come through, and the overlay panels can never appear in the
result. Shadows are excluded for a tight crop, the window's own rounded alpha corners are preserved,
and the Rounded Corners setting is deliberately not reapplied to a window capture. If the window
disappears between the click and the request, the capture fails through the same HUD as any other
failure.

## The whole-screen button

Each display's overlay carries one Liquid Glass square — a 56-point rounded rect holding a small
`display` glyph — and clicking it captures that display in full, through the same display-capture
path a dragged region uses with the source rectangle set to the display's full bounds. The
Resolution setting therefore applies identically, and nothing is rounded: a full display has no
corners to clip. That also makes the button the quickest end-to-end check of the Resolution
setting: a Retina capture of a whole display should match its framebuffer exactly (point size times
backing scale), and `1x` should match its point size.

The button sits inset from the right edge of the display's usable width — a Dock on the right edge
pushes it inward — and vertically centred on the Dock strip when the Dock is on that display's
bottom edge, resting at a fixed height above the bottom when it is not. The pure
`ScreenshotGeometry.screenButtonFrame` owns that placement and the harness pins it. The button
shows only in screenshot mode: whole-screen capture is a picture, not an OCR or colour action. Its
hosting view accepts the first click like the overlay around it, its clicks never start a drag, and
the pointer over its footprint is the plain arrow rather than the mode pointer — enforced both
through cursor rects and on every pointer-move set, since the overlay otherwise reasserts the mode
pointer continuously.

The pure `ScreenshotGeometry` normalizes drag direction, clamps local points and flips a display-local
AppKit rectangle into ScreenCaptureKit's display-local top-origin space. Its standalone harness pins
normal, reverse, clamped and secondary-display coordinates without depending on the display's global
origin.

## Naming and clipboard history

A capture is named after the app it came from: `Claude_SpotterScreenshot_2608041812` — app, marker,
then `yyMMddHHmm`, which sorts chronologically as plain text and stays short enough to read in a Save
dialog. The frontmost application is recorded when the selection opens, before any overlay can take
its place, and rides on the payload with its bundle identifier. Non-alphanumerics are stripped from
the app name, and a capture with no identifiable app keeps the marker and the stamp alone. The pure
`ScreenshotFileName` owns both the format and the `isScreenshot` test, and its harness pins them.

That name is what puts the capture in clipboard history *as a screenshot*. `AppCore` inserts the
entry directly after a successful capture rather than letting the poller find it — the pasteboard
copy keeps its internal marker, so the poller stays out of it and the file keeps the name Spotter
chose instead of a UUID. `ClipboardItem.isScreenshot` reads that name back, which is what the
**Screenshots Only** filter matches on; see [clipboard.md](clipboard.md). Captures from an app
excluded from clipboard history are excluded here too, and the insert does not happen at all when the
Clipboard plugin is off. Two captures inside the same minute would collide on one path, so the store
uniquifies the stem rather than overwriting the pixels an existing row points at — counting names
handed out this session as taken, since the blob write is detached and the previous file does not
exist yet when the next call asks. Only the capture itself is recorded; a marked-up copy made in the
editor is a deliberate edit of an entry history already holds.

## Text recognition (OCR mode)

OCR mode turns the selection orange: the pointer keeps the `dot.crosshair` and only changes colour
to `screenshotCrosshairTextFill`, because text recognition *is* a region drag — the shape says what
the gesture is and the colour says what comes out of it. The drag behaves exactly as a region drag —
the two share `isDragSelection`. A right click and the whole-screen button are inert here: there is
no sensible whole-window or whole-display version of "read this bit of text". On release the pixels are captured
only to be read: Vision recognizes the text, the image is dropped, and the text alone goes to the
clipboard. "Text Copied" reports through the plain command HUD, and a selection with nothing legible
in it reports "No Text Found" as a no-op without touching the clipboard.

Recognition always captures at Retina regardless of the **Resolution** setting: accuracy tracks pixel
density and no image is kept, so honouring `1x` here would cost accuracy and save nothing. Vision
runs off the main actor and returns a plain `String`. Language is auto-detected rather than pinned to
a list, so mixed Latin and CJK text reads correctly with nothing to configure.

Unlike every other Spotter clipboard write, recognized text is **not** stamped with the internal
marker, so it enters clipboard history (owner decision, Aug 2026). It is the user's own text and
history is exactly where it belongs, whereas an image capture already has a thumbnail, a pin and an
editor to return to.

Nothing here needs a new permission or a consent gate: Vision is on-device and offline, and it reads
exactly the pixels the existing Screen Recording grant already covers.

The pure `ScreenshotTextLayout` puts the fragments back in reading order — Vision returns them in no
useful order, so joining them as they arrive scrambles anything longer than a line. It groups by
vertical overlap measured against the *shorter* fragment, so a tall heading does not swallow the row
beneath it, then sorts lines top-to-bottom and each line left-to-right. Its harness pins the
ordering, the empty cases and the heading-versus-body grouping.

## Colour picker

The third Space stop samples a colour instead of pixels or text. The pointer becomes an eyedropper
whose hotspot is its tip, a left click reads the point under it, and the value lands on the
clipboard as uppercase `#RRGGBB` — confirmed by a "Copied #A1B2C3" command HUD. Dragging and right
clicks are inert; Escape still cancels. There is no loupe: click-to-copy ships first, and a zoomed
preview would need live screen streaming that the idle-between-invocations architecture deliberately
avoids.

The sample is one point captured through the ordinary display path at `1x` regardless of the
Resolution setting — one point is the colour the user sees, and the single pixel ScreenCaptureKit
distils from its Retina quad is the honest value for it. The overlay panels come down first and the
capture waits the same one-frame beat as a region, since the hit surface's single alpha step would
otherwise tint the reading. The pure `ScreenshotColorSampler` converts the pixel to sRGB before
formatting — a raw byte read off a Display-P3 capture would name a colour every other app renders
differently — and the pure `ScreenshotGeometry.colorSampleRect` keeps an edge click on the display;
the harness pins both.

Like recognized text, the hex value is written **unmarked** and enters clipboard history: it is the
user's own value, not a picture with a thumbnail and an editor (owner decision, Aug 2026).

## Capture options

Four preferences shape what a capture produces. All persist under bundle-scoped
`screenshot.*` keys, ride the trusted v3 backup/sync snapshot and apply live.

- **Resolution** — `Retina` (default) captures at the display's own backing scale; `1x` asks
  ScreenCaptureKit for one pixel per point, which is what a screenshot bound for the web usually
  wants. The pure `ScreenshotCaptureScale` resolves the pixel dimensions for both the region and
  window paths and never rounds a visible region down to nothing.
- **Window Shadow** — off by default, preserving the tight crop. A window filter's `contentRect`
  already reserves the shadow margin, so only `ignoreShadowsSingleWindow` decides whether the shadow
  is drawn into that margin or cropped away. Region drags are unaffected: a dragged rectangle has no
  shadow to include.
- **Hide Spotter While Capturing** — off by default. On, the launcher is dismissed and
  `closeAuxiliaryWindows()` closes Settings, About and every plugin workspace before the selection
  panels appear, so none of Spotter's own windows can land in the shot. Off, they all stay — which
  takes more than skipping the dismissal: the overlay takes key across every display, and the
  launcher hides on `windowDidResignKey`. `PaletteWindowController` therefore ignores a resign while
  `screenshot.isCapturing`, read live rather than through a flag so no exit path can leave it stuck.
  The HUDs are short-lived enough not to matter. It closes rather than merely hiding, so window state stays consistent — which
  includes the mark-up editor, discarding any annotations not yet copied or saved. That is the same
  thing that already happens when a new capture's thumbnail reopens the editor, so it is not a new
  hazard, but it is why the setting ships off.
- **Thumbnail Duration** — how many seconds the capture thumbnail stays up, typed into a field
  rather than picked from a menu: the useful value depends on how fast the user works, and the
  sensible range is wider than a menu would hold. Clamped to 1–60 seconds on commit rather than
  rejected, so a typed `0` or `900` becomes the nearest value the app will honour. Hovering still
  holds a thumbnail open past its countdown, and the Return grace below is deliberately *not* tied
  to this number.
- **File Format** — `PNG` (default) or `JPG`, used by the editor's Save. The clipboard copy stays
  TIFF in both cases: it is lossless and the format every app pastes, and a file-size choice buys
  nothing there. JPEG carries no alpha, so a rounded corner would encode as a hard black wedge — a
  JPEG is squared instead of being matted onto an invented background color. JPEG quality is fixed
  at 0.9, high enough to keep text and UI edges clean.

## Rounded corners

Rounded Corners is on by default and persists under the bundle-scoped
`screenshot.rounded-corners` preference. It is included in trusted Settings Backup/Sync and applied
live through `ScreenshotManager`. Turning it off makes both the selection border and copied image
square.

When enabled, `ScreenshotImageProcessor` clips the captured `CGImage` to a four-pixel rounded path
and encodes a TIFF with transparent corner pixels off the main actor. Regions narrower than eight
pixels clamp the radius to half their shortest side rather than producing invalid geometry.

## Preview and mark-up editor

Captures taken in quick succession each get their own thumbnail, laid out in a row along the bottom
of the screen, oldest to the left, gapped by 12 points and aligned on their bottom edges so
differently-shaped captures sit on one line. The row stays centred, so an arriving thumbnail slides
the others aside rather than landing on top of them, and a departing one closes the gap. A new
capture also restarts the countdown on the thumbnails already up, so the row lives and dies together
instead of the oldest vanishing mid-row; a hovered thumbnail is skipped, since the pointer already
holds it and rescheduling would dismiss it out from under the pointer. The manager
owns the row and the Return key — which always opens the newest — because a per-thumbnail key would
have each registration clobbering the last. The row's screen is fixed while it is non-empty, so a
new thumbnail cannot drag the others onto whichever display the pointer happens to be over.

Each thumbnail drifts in 8 points from the direction of the area it was captured from: a capture in
the top-right corner starts the thumbnail up and to the right of its slot and settles it down-left
into place, leading the eye from the captured area to its result. Vertical signs flip on the way in
because AppKit's y grows upward and SwiftUI's grows downward.

The post-capture thumbnail is the entry point. `ScreenshotPreviewHUD` is a separate surface from the
worded `CommandHUD`: it carries no text, symbol or button, just the capture itself in a 4-point white
frame with a 4-point radius and a `0/4/16` 40%-black shadow spread by 4, aspect-fitted into a
124×73-point box and centered at the command HUD's `hudBottomMargin` (120) above the visible frame's
bottom edge. The frame stays white in both appearances — it is part of the artwork, like the macOS
capture thumbnail, not palette chrome. It resolves from a 10-point blur to sharp over 0.26s and
blurs back out over 0.18s before the panel orders out — a focus-in, with no scale or offset, so
nothing about the thumbnail moves as it appears. The blur applies to the card alone and the shadow is
cast after it: the shadow hangs below the card, so blurring a composite that includes it smears that
dark mass asymmetrically and the bright card reads as drifting downward. Layout is settled at the
final geometry before the appear animation starts, so no first frame renders at a stale size. The
shadow padding absorbs the blur, which spreads the artwork past its own bounds while it resolves. The pure
`ScreenshotThumbnail` resolves the outer size, so a tall or one-pixel-tall capture still gets a
visible thumbnail rather than a letterboxed box. Its hosting view installs through `PanelHosting` as
a subview, never the panel's `contentView` — the animated blur during a display-cycle flush is
exactly the timing macOS 26's content-view extrema path crashes on.

Clicking it opens the mark-up editor on the retained capture. **Return** opens it too: the panel
never becomes key — Spotter must not take focus from the app the capture came from — so Return
arrives through a transient Carbon key held by `HotKeyManager.holdTransientKey` only while the
thumbnail is on screen. That key is not a user binding: nothing persists, it never reaches Settings
or a conflict check, and Carbon *consumes* Return system-wide while it is held.

**Return belongs to the moment right after the capture, not to the thumbnail's whole life.** Held for
as long as the thumbnail was visible, it ate the Return that sends a message in the app the user
captured from — and since Spotter never activates, the frontmost app never changes, so nothing else
took the key back. The claim therefore ends at the first of: a click anywhere outside Spotter, the
row emptying, or a five-second grace window. That grace is deliberately independent of Thumbnail
Duration: a thumbnail can be left up for a minute without Return being unavailable for a minute.
The click is read through a passive `NSEvent` global mouse-down monitor that is installed only while
the key is held and torn down the moment it fires; it reads nothing off the event — not the location,
not the window — and there is no keyboard monitoring, which would need Accessibility and a consent
gate of its own. **Dragging the thumbnail off pins it.** Eight points of travel tears it out of the HUD into a
`ScreenshotPinWindow`: a borderless floating panel three times the thumbnail's size, centred on the
pointer and staying above every app. It is one uninterrupted gesture — the pin follows the pointer
until the button comes up. That works because the thumbnail's panel is only made invisible at the
tear-off, not ordered out: AppKit keeps delivering a drag to the view that received the mouse-down,
so ordering the panel out would end the gesture. It is dismissed properly on mouse-up. For the same
reason the pin scales up through SwiftUI rather than through an animated window frame, which would
fight the drag: the frame is final from the first moment while the content grows into it over 0.24s.

Dragging a pin's body moves it and dragging any corner resizes it — aspect-locked, holding the
corner opposite the one being dragged, with both axes contributing so a diagonal drag tracks the
pointer instead of answering only to horizontal movement, and the system frame-resize cursors mark
the grab regions. A click opens that pin's own capture in the editor, which is not necessarily the
newest one, and closes the pin as it goes — the capture is about to appear in a window that can
actually edit it, so leaving the floating copy behind would be two of the same thing on screen.
Other pins are untouched; each holds its own capture. Scrolling behaves exactly as it does on the thumbnail through the shared
`ScreenshotScrollFlick`: lift to open the editor, push down to dismiss, over 0.16s. Several pins can
float at once, each dropping out of the manager's list as it closes, and all of them close when the
plugin is disabled.

Every pointer decision on a pin — move, resize, click, flick — is resolved in AppKit rather than
SwiftUI, because one press on one surface has to become a click, a drag or a resize depending on
where it lands and how far it travels. The thumbnail's own press handling moved there for the same
reason: a tap gesture cannot tell a click from a tear-off. Corner hit-testing reads `isFlipped`
rather than assuming: `NSHostingView` is flipped, so a converted point already has a top-left
origin, and flipping it again silently swapped the vertical corners and anchored the wrong side.

Scrolling over the thumbnail works it like a notification banner: push it down to dismiss, lift it up
to open the editor, after 24 points of travel so a stray twitch does nothing. That reads the physical
gesture rather than the content-scroll sign — `isDirectionInvertedFromDevice` is unwound, so the same
finger movement means the same thing whether or not natural scrolling is on, and a wheel's notches
map to the same two directions. SwiftUI has no scroll hook for a view that is not a scroll view, so
the panel's hosting view overrides `scrollWheel` and hands the event to the HUD. The thumbnail
dismisses when the user activates another app
(`NSWorkspace.didActivateApplicationNotification`), after 3.5 seconds, on click, or on a downward
scroll; hovering holds it. The manager retains the last capture (raw pixels plus the corner treatment
the clipboard copy received) until the next capture or until the plugin is disabled, which also
dismisses the thumbnail and closes the editor.

The editor is a resizable auxiliary window through `AppCore.showPluginWindow`, sized to the capture
at native points and clamped to 85% of the visible frame; each capture reopens it fresh on the
latest image. It is the one plugin window that passes `movableByBackground: false`: AppKit claims a
mouse-down for a window drag whenever the hit view reports `mouseDownCanMoveWindow`, which SwiftUI
clears for controls but not for a `Canvas` carrying only a `DragGesture` — so a stroke on the capture
also moved the window. The toolbar strip carries an explicit `WindowDragGesture()` instead, making it
the one deliberate handle; its controls take their own clicks first, so only the gaps between them
drag. Four tools stack in a floating card at the canvas's bottom-left — Rectangle (R), Oval (O),
Pencil (P) and Text (T) — and the eight-color palette mirrors it at the bottom-right; the three stroke
weights sit under the colors in that same card, each with a full-cell hit target — a `.clear` fill
takes no hits, so before that an unselected weight was only clickable on its 4-point dot. The top bar is only actions, all `.controlSize(.extraLarge)` with `.imageScale(.large)` so the
glyphs grow with them, in a 68-point bar shared with the window sizing: a
capsule **Cancel** at the leading edge, then undo/redo, Save (⌘S) and Copy (⌘↩) as circular
icon-only Liquid Glass buttons with Copy prominent. Undo and redo sit in a `GlassEffectContainer`
spaced two points apart, so their glass shapes merge and read as one control. Each icon button
carries a `Label`, so the same string is its tooltip and its VoiceOver name. The bar remains the
window's drag handle.

The window hides its traffic lights (`hidesStandardButtons`) and closes through that Cancel button
instead, which is why the button is load-bearing rather than decorative. It also opens with nothing
focused (`clearsInitialFocus`): AppKit otherwise hands first responder to the first control in the
key-view loop, ringing a button the user never chose. Only the initial focus is dropped — Tab still
moves focus and still draws its ring. Escape triggers it, but only
while no text annotation is being typed — otherwise Escape would close the window out from under a
half-written mark instead of discarding it, the same gating the tool letters use. The window is
`transparent`, filled by an `NSVisualEffectView` `.hudWindow` on `.behindWindow` blending and clipped
to `Radius.window`: a SwiftUI `Material` blurs only what is inside the app, so the desktop would stay
opaque behind it.
Each tool's bare letter selects it, attached as a key equivalent only while no text annotation is
being typed, since a bare letter would otherwise fire mid-word. There is no separate arrow tool: the
rectangle tool draws a rectangle with the left button and an arrow with the right, which is why the
canvas listens through an AppKit overlay — SwiftUI's `DragGesture` only speaks the primary button.
Marks are committed on mouse-up; a sub-3-point drag is discarded as a misclick. The text tool places an inline field at the
click point (Return commits, Escape discards), rendered bold with a soft dark halo for legibility.

The canvas never enlarges the capture: the fit is capped at `1 / displayScale`, one image pixel per
device pixel. Without that cap a small capture was stretched to fill the window's minimum size — on a
Retina screen a 400×300 shot drew at 2×, soft enough to read as a bad capture rather than a zoomed
preview. A capture smaller than the window now sits at 1:1 in the middle of it, and enlarging the
window no longer softens anything. The minimum is 620×400, which is what the action bar needs.

All annotation geometry lives in image pixel space with a top-left origin, so the live canvas and
the export share every coordinate: the SwiftUI `Canvas` hands its CGContext to the same pure
`ScreenshotAnnotationRenderer` that `flatten` uses for export, scaled by the current fit factor.
Stroke widths and font sizes are chosen in view points and resolved into image pixels at creation
time, so what is drawn at fit scale is what exports. The palette is a fixed set of content colors
baked into the pixels — deliberately not `Theme` tokens, since an exported mark must look identical
in both appearances. Copy (⌘↩) flattens off the main actor, reuses the capture pipeline's TIFF
processing and internal-type marker (including the original's corner treatment) and closes the
window; Save… (⌘S) writes the configured format through `NSSavePanel`, naming the file by
its own extension. Flattening
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
