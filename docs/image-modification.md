# Image Modification

Always available; registration declares Automation permission for reading Finder's selection.
The output-location preference syncs through `SettingsBackupPluginPrefs.ImageModification`. The
retired created-image format is ignored when reading older backups. Pad Image and Create Image,
including their processing code and settings, have been removed.

## Parameters

Convert Image, Resize Image, Scale Image and Optimize Image open a second-level Palette with presets
and a shared search field for custom parameters. No input resolution or processing starts until a
parameter row is activated. Convert lists only formats the current macOS ImageIO encoder can write.

The same commands accept parameters directly in the launcher:

| Query | Result |
| --- | --- |
| `Convert JPG` / `Convert to PNG` / `Convert TIF` | Convert to the selected format |
| `Resize 1920x1080` | Fit inside a 1920 × 1080 bounding box, preserving aspect ratio |
| `Resize 800` | Fit inside an 800 × 800 bounding box |
| `Scale1.5` / `Scale 150%` | Multiply both dimensions by 1.5 |
| `Optimize 80%` / `Optimize 0.8` | Re-encode at 80% quality where supported |

`ImageCommand.swift` is Foundation-only. Its bounded parser accepts numeric parameters rather than
maintaining an exhaustive list of commands. Both entry paths use the same parsed value. The transient
launcher row reuses its base command's ID, visibility and shortcut; shortcuts without parameters open
the parameter palette. Invalid or incomplete parameters never start processing.

Scale accepts any finite positive factor; resize dimensions are positive integers. The engine checks
actual output dimensions before rendering: at least one pixel per side, at most 32,768 per side and
100 megapixels total. Optimize accepts 5–100% quality. The encoder's lossy quality setting applies to
formats such as JPG; PNG is re-encoded losslessly and a smaller file is not guaranteed.

The remaining direct commands cover filtering, horizontal/vertical flips, background removal,
rotation and EXIF/metadata stripping. Rotation uses 90 degrees and Apply Filter uses Core Image's
Chrome photo effect.

## Pipeline

Inputs resolve in order from Finder's current selection, copied image/file data, then `NSOpenPanel`
when neither source has an image. Finder selection is queried only when Finder was the source
application and uses the macOS Automation grant. Operations run in a detached task through Core
Image, Vision and ImageIO; no JS runtime, helper daemon or network request is involved. Vision's
foreground mask powers background removal.

After inputs and any Replace Original confirmation are resolved, every operation returns Spotter to
the launcher and starts a background-task row. Multi-image batches update the row after each output;
Done or Failed remains visible until dismissed. Cancelling before input or confirmation creates no
row.

Outputs can be written beside the original, to Desktop or Downloads, opened in Preview, copied to the
clipboard, or used to replace the original. Replace Original retains its native confirmation alert
and always confirms the resolved batch count. When Beside Original has no durable original, copied
pixel data is replaced with the processed result on the clipboard. Temporary clipboard/Preview
output lives under the current bundle identifier's cache directory.

Formats are filtered from Spotter's format catalog against `CGImageDestinationCopyTypeIdentifiers()`;
JPG/JPEG and TIF/TIFF are accepted aliases. macOS may decode additional inputs such as WebP or SVG.
Spotter bundles no command-line codecs or helper processes.
