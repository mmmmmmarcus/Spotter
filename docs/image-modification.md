# Image Modification plugin

Image Modification is the native counterpart of Raycast's Image Modification (`sips`) extension. It
provides commands for filters, conversion, image creation, horizontal/vertical flips, optimization,
padding, background removal, resizing, rotation, scaling and EXIF/metadata stripping.

The filter picker is built from the compatible Core Image blur, color, distortion, halftone, sharpen,
stylize and tile categories available on the current macOS release. Create Image includes the same
nine generator families as the reference: checkerboard, constant color, lenticular halo, linear and
radial gradients, random noise, star shine, stripes and sunbeams.

## Pipeline

Inputs come from Finder's current selection, copied image/file data, or `NSOpenPanel`. Finder selection
is queried only when Finder was the source application and uses the macOS Automation grant. Operations
run in a detached task through Core Image, Vision and ImageIO; no JS runtime, helper daemon or network
request is involved. Vision's foreground mask powers background removal.

Outputs can be written beside the original, to Desktop or Downloads, opened in Preview, copied to the
clipboard, or used to replace the original. Replace Original always confirms the resolved batch count.
Temporary clipboard/Preview output lives under the current bundle identifier's cache directory, so
Debug, beta and stable channels remain isolated.

Spotter exposes ImageIO's full native writable set: JPEG, PNG, GIF, TIFF, JPEG 2000, ATX, KTX/KTX2,
ASTC, DDS, HEIC/HEICS, AVIF, ICO, BMP, ICNS, PSD, PDF, TGA, EXR, PBM and PVR. macOS may decode
additional inputs such as WebP or SVG. Unlike the reference extension,
Spotter does not bundle `cwebp`, `potrace`, libavif or another command-line codec; this preserves the
signed-native, zero-dependency architecture and avoids subprocess/runtime overhead for normal edits.
