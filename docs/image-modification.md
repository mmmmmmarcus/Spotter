# Image Modification

Enabled by default; registration declares the Automation permission (for reading Finder's selection),
so it appears in System → Permissions. The output-location and format preferences sync through
`SettingsBackup.PluginPrefs.ImageModification`. The Replace Original confirmation is the one dialog
that deliberately stays a window-modal alert: it belongs to the Image Modification workspace, not the
palette. plugin

Image Modification is the native counterpart of Raycast's Image Modification (`sips`) extension. Its
launcher commands run immediately without opening a plugin workspace. They cover filtering,
conversion, image creation, horizontal/vertical flips, optimization, padding, background removal,
resizing, rotation, scaling and EXIF/metadata stripping.

Choosing Convert Image opens a searchable second-level palette containing every writable target
format. No input resolution or pixel work starts until the user explicitly selects one of those rows.
The other commands use the plugin's configured output plus their operation defaults, while Create
Image uses the configured created-image format.
Generated images default to a 1200×800 linear gradient, resizing fits within 1200×800, rotation uses
90 degrees, scaling uses 0.5×, padding uses 40 transparent pixels, optimization uses 82% quality and
Apply Filter uses Core Image's Chrome photo effect.

## Pipeline

Inputs resolve in order from Finder's current selection, copied image/file data, then `NSOpenPanel`
when neither source has an image. Finder selection is queried only when Finder was the source
application and uses the macOS Automation grant. Operations run in a detached task through Core
Image, Vision and ImageIO; no JS runtime, helper daemon or network request is involved. Vision's
foreground mask powers background removal.

Outputs can be written beside the original, to Desktop or Downloads, opened in Preview, copied to the
clipboard, or used to replace the original. Replace Original always confirms the resolved batch count.
When Beside Original has no durable original, Create Image opens its result in Preview and copied pixel
data is replaced with the processed result on the clipboard.
Temporary clipboard/Preview output lives under the current bundle identifier's cache directory, so
Debug, beta and stable channels remain isolated.

Spotter exposes ImageIO's full native writable set: JPEG, PNG, GIF, TIFF, JPEG 2000, ATX, KTX/KTX2,
ASTC, DDS, HEIC/HEICS, AVIF, ICO, BMP, ICNS, PSD, PDF, TGA, EXR, PBM and PVR. macOS may decode
additional inputs such as WebP or SVG. Unlike the reference extension,
Spotter does not bundle `cwebp`, `potrace`, libavif or another command-line codec; this preserves the
signed-native, zero-dependency architecture and avoids subprocess/runtime overhead for normal edits.
