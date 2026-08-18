#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
TEAM_ID="SM96W8VVK9"
BUNDLE_ID="com.spotter.app1"
CLOUD_CONTAINER="iCloud.com.spotter.app"
PROFILE_DIRECTORY="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
DERIVED_DATA="$ROOT/build/CloudDevDerivedData"
ENTITLEMENTS_PATH="Spotter/Spotter.Development.entitlements"
INSTALLED_APP="/Applications/Spotter.app"
PROFILE_UUID=""
PROFILE_NAME=""

inspect_directory="$(mktemp -d /tmp/spotter-cloud-dev-profile.XXXXXX)"
backup_directory=""
cleanup() {
    find "$inspect_directory" -depth -delete 2>/dev/null || true
    if [ -n "$backup_directory" ] && [ -d "$backup_directory" ]; then
        find "$backup_directory" -depth -delete 2>/dev/null || true
    fi
}
trap cleanup EXIT

signing_identities="$(security find-identity -v -p codesigning)"
if ! grep -Fq 'Apple Development:' <<< "$signing_identities"; then
    echo "✗ No Apple Development signing identity is available." >&2
    exit 1
fi

shopt -s nullglob
profiles=("$PROFILE_DIRECTORY"/*.provisionprofile)
shopt -u nullglob
for profile in "${profiles[@]}"; do
    plist="$inspect_directory/$(basename "$profile").plist"
    security cms -D -i "$profile" > "$plist" 2>/dev/null || continue
    team="$(/usr/libexec/PlistBuddy -c 'Print :TeamIdentifier:0' "$plist" 2>/dev/null || true)"
    app_id="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.application-identifier' "$plist" 2>/dev/null || true)"
    push="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.aps-environment' "$plist" 2>/dev/null || true)"
    containers="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.icloud-container-identifiers' "$plist" 2>/dev/null || true)"
    environments="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.icloud-container-environment' "$plist" 2>/dev/null || true)"
    if [ "$team" = "$TEAM_ID" ] && [ "$app_id" = "$TEAM_ID.$BUNDLE_ID" ] \
        && [ "$push" = "development" ] && grep -Fq "$CLOUD_CONTAINER" <<< "$containers" \
        && grep -Fq 'Development' <<< "$environments"; then
        PROFILE_UUID="$(/usr/libexec/PlistBuddy -c 'Print :UUID' "$plist")"
        PROFILE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :Name' "$plist")"
        break
    fi
done

if [ -z "$PROFILE_UUID" ]; then
    echo "✗ No development provisioning profile authorizes $BUNDLE_ID and $CLOUD_CONTAINER." >&2
    exit 1
fi

echo "▸ Building CloudKit dev app with profile: $PROFILE_NAME"
xcodebuild -project "$ROOT/Spotter.xcodeproj" -scheme Spotter -configuration Debug \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_ENTITLEMENTS="$ENTITLEMENTS_PATH" build

staged_app="$DERIVED_DATA/Build/Products/Debug/Spotter.app"
if [ ! -d "$staged_app" ]; then
    echo "✗ CloudKit dev app was not produced." >&2
    exit 1
fi
if [ ! -f "$staged_app/Contents/embedded.provisionprofile" ]; then
    echo "✗ Development provisioning profile was not embedded." >&2
    exit 1
fi

codesign --verify --deep --strict --verbose=2 "$staged_app"
signature="$(codesign -dv --verbose=4 "$staged_app" 2>&1)"
signed_team="$(sed -n 's/^TeamIdentifier=//p' <<< "$signature")"
if [ "$signed_team" != "$TEAM_ID" ]; then
    echo "✗ Expected TeamIdentifier $TEAM_ID, found ${signed_team:-none}." >&2
    exit 1
fi

signed_entitlements="$(codesign -d --entitlements :- "$staged_app" 2>/dev/null)"
if ! grep -Fq "$CLOUD_CONTAINER" <<< "$signed_entitlements" \
    || ! grep -Fq '<string>Development</string>' <<< "$signed_entitlements" \
    || ! grep -Fq '<string>development</string>' <<< "$signed_entitlements"; then
    echo "✗ Signed app is missing the Development CloudKit or push entitlement." >&2
    exit 1
fi

version="$(defaults read "$staged_app/Contents/Info" CFBundleShortVersionString)"
signed_bundle_id="$(defaults read "$staged_app/Contents/Info" CFBundleIdentifier)"
if [[ "$version" != *-dev ]] || [ "$signed_bundle_id" != "$BUNDLE_ID" ]; then
    echo "✗ Expected a -dev $BUNDLE_ID app, found $version / $signed_bundle_id." >&2
    exit 1
fi

osascript -e 'tell application id "com.spotter.app1" to quit' 2>/dev/null || true
for _ in {1..40}; do
    if ! pgrep -x Spotter >/dev/null; then break; fi
    sleep 0.1
done

backup_directory="$(mktemp -d /tmp/spotter-cloud-dev-install.XXXXXX)"
if [ -d "$INSTALLED_APP" ]; then
    mv "$INSTALLED_APP" "$backup_directory/Spotter.app"
fi
if ! ditto "$staged_app" "$INSTALLED_APP"; then
    if [ -d "$backup_directory/Spotter.app" ]; then
        mv "$backup_directory/Spotter.app" "$INSTALLED_APP"
    fi
    echo "✗ Could not install the CloudKit dev app; the previous app was restored." >&2
    exit 1
fi

if ! codesign --verify --deep --strict --verbose=2 "$INSTALLED_APP"; then
    find "$INSTALLED_APP" -depth -delete 2>/dev/null || true
    if [ -d "$backup_directory/Spotter.app" ]; then
        mv "$backup_directory/Spotter.app" "$INSTALLED_APP"
    fi
    echo "✗ Installed verification failed; the previous app was restored." >&2
    exit 1
fi
open "$INSTALLED_APP"
echo "✓ Installed and launched Spotter $version with Development CloudKit."
