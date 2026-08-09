#!/bin/bash
# Build, notarize and package the version declared in project.yml. Usage: ./build-dmg.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"; cd "$ROOT"
if [ "$#" -ne 0 ]; then
    echo "✗ Version overrides are not accepted; update MARKETING_VERSION in project.yml." >&2
    exit 1
fi
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
IDENTITY="Developer ID Application: Round Technology (Shanghai) Co.,Ltd (SM96W8VVK9)"
TEAM_ID="SM96W8VVK9"
NOTARY_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-spotter-notary}"
DERIVED="build/DerivedData"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

IDENTITIES="$(security find-identity -p codesigning)"
if ! grep -Fq "$IDENTITY" <<< "$IDENTITIES"; then
    echo "✗ '$IDENTITY' code-signing identity not found — import it first (docs/signing.md)." >&2
    exit 1
fi

echo "▸ Building signed Spotter.app (Release)…"
xcodebuild -project Spotter.xcodeproj -scheme Spotter -configuration Release \
    -derivedDataPath "$DERIVED" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="$TEAM_ID" \
    ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS="--timestamp" \
    build

APP="$DERIVED/Build/Products/Release/Spotter.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
SOURCE_VERSION="$(sed -nE 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"([^"]+)".*/\1/p' project.yml)"
if [ "$VERSION" != "$SOURCE_VERSION" ]; then
    echo "✗ Built version $VERSION does not match project.yml $SOURCE_VERSION; run xcodegen generate." >&2
    exit 1
fi
DMG="build/Spotter-${VERSION}.dmg"

echo "▸ Verifying Developer ID signature…"
codesign --verify --deep --strict --verbose=2 "$APP"
SIGNATURE_INFO="$(codesign -dv --verbose=4 "$APP" 2>&1)"
TEAM="$(sed -n 's/^TeamIdentifier=//p' <<< "$SIGNATURE_INFO")"
if [ "$TEAM" != "$TEAM_ID" ]; then
    echo "✗ Expected TeamIdentifier $TEAM_ID, found ${TEAM:-none}." >&2
    exit 1
fi
if ! grep -q 'flags=.*runtime' <<< "$SIGNATURE_INFO"; then
    echo "✗ Hardened Runtime is not present in the app signature." >&2
    exit 1
fi

echo "▸ Notarizing and stapling Spotter.app…"
ditto -c -k --keepParent "$APP" "$SCRATCH/Spotter-notarization.zip"
xcrun notarytool submit "$SCRATCH/Spotter-notarization.zip" \
    --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"

echo "▸ Packaging ${DMG}"
STAGE="$SCRATCH/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
diskutil image create from "$STAGE" --format UDZO --volumeName "Spotter" "$DMG" >/dev/null
codesign --sign "$IDENTITY" --timestamp "$DMG"

echo "▸ Notarizing and stapling ${DMG}…"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"

echo "✓ Signed and notarized: $DMG"
