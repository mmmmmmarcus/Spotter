#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIGURATION="${1:-Debug}"
MODE="${2:-launch}"
IDENTITY="Spotter Self-Signed"
SIGNING_KEYCHAIN="$HOME/Library/Keychains/spotter-signing.keychain-db"
DERIVED="$ROOT/build/DerivedData"
SOURCE_APP="$DERIVED/Build/Products/$CONFIGURATION/Spotter.app"
INSTALLED_APP="/Applications/Spotter.app"
BACKUP_ROOT="$HOME/Library/Caches/com.spotter.local-install"
PREVIOUS_APP="$BACKUP_ROOT/Spotter.previous.app"

case "$CONFIGURATION" in
    Debug|Release) ;;
    *)
        echo "Usage: $0 [Debug|Release] [launch|--install-only]" >&2
        exit 2
        ;;
esac

case "$MODE" in
    launch|--install-only) ;;
    *)
        echo "Usage: $0 [Debug|Release] [launch|--install-only]" >&2
        exit 2
        ;;
esac

if [ -f "$SIGNING_KEYCHAIN" ]; then
    SIGNING_PASSWORD="$(
        security find-generic-password -s 'Spotter Signing Backup Password' -w \
            "$HOME/Library/Keychains/login.keychain-db"
    )"
    security unlock-keychain -p "$SIGNING_PASSWORD" "$SIGNING_KEYCHAIN"
fi

if ! security find-identity -v -p codesigning | grep -F "\"$IDENTITY\"" >/dev/null; then
    echo "✗ '$IDENTITY' is not a valid code-signing identity." >&2
    echo "  Run ./Tools/setup-signing.sh once, then retry." >&2
    exit 1
fi

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
LOG_PATH="${TMPDIR:-/tmp}/spotter-build.log"

echo "▸ Building Spotter ($CONFIGURATION)…"
set +e
xcodebuild -project Spotter.xcodeproj -scheme Spotter \
    -configuration "$CONFIGURATION" -derivedDataPath "$DERIVED" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" \
    OTHER_CODE_SIGN_FLAGS="--timestamp=none" build 2>&1 | tee "$LOG_PATH"
BUILD_STATUS=${PIPESTATUS[0]}
set -e
if command -v xcode-build-server >/dev/null 2>&1; then
    xcode-build-server parse -a -o .compile < "$LOG_PATH" >/dev/null 2>&1 || true
fi
if [ "$BUILD_STATUS" -ne 0 ]; then
    exit "$BUILD_STATUS"
fi

test -d "$SOURCE_APP"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SOURCE_APP/Contents/Info.plist")" = "com.spotter.app"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$SOURCE_APP/Contents/Info.plist")" = "Spotter"
codesign --verify --deep --strict "$SOURCE_APP"
codesign -dv --verbose=4 "$SOURCE_APP" 2>&1 | grep -F "Authority=$IDENTITY" >/dev/null

echo "▸ Stopping every existing Spotter process…"
killall "Spotter Dev" >/dev/null 2>&1 || true
killall "Spotter" >/dev/null 2>&1 || true
for _ in {1..50}; do
    if ! pgrep -x "Spotter Dev" >/dev/null && ! pgrep -x "Spotter" >/dev/null; then
        break
    fi
    sleep 0.1
done
if pgrep -x "Spotter Dev" >/dev/null || pgrep -x "Spotter" >/dev/null; then
    echo "✗ Spotter did not quit cleanly; installation stopped without replacing the app." >&2
    exit 1
fi

echo "▸ Migrating the old Dev channel once (network consent excluded)…"
xcrun swift "$ROOT/Tools/migrate-dev-state.swift"

mkdir -p "$BACKUP_ROOT"
STAGE_ROOT="$(mktemp -d /Applications/.spotter-install.XXXXXX)"
STAGED_APP="$STAGE_ROOT/Spotter.app"
rollback() {
    if [ -d "$INSTALLED_APP" ] && [ -d "$PREVIOUS_APP" ]; then
        mv "$INSTALLED_APP" "$STAGE_ROOT/Spotter.failed.app"
        mv "$PREVIOUS_APP" "$INSTALLED_APP"
    elif [ -d "$INSTALLED_APP" ]; then
        mv "$INSTALLED_APP" "$STAGE_ROOT/Spotter.failed.app"
    elif [ -d "$PREVIOUS_APP" ]; then
        mv "$PREVIOUS_APP" "$INSTALLED_APP"
    fi
    if [ -d "$STAGE_ROOT" ]; then
        rm -rf "$STAGE_ROOT"
    fi
}
trap rollback EXIT

ditto "$SOURCE_APP" "$STAGED_APP"
codesign --verify --deep --strict "$STAGED_APP"

if [ -d "$PREVIOUS_APP" ]; then
    rm -rf "$PREVIOUS_APP"
fi
if [ -d "$INSTALLED_APP" ]; then
    mv "$INSTALLED_APP" "$PREVIOUS_APP"
fi
mv "$STAGED_APP" "$INSTALLED_APP"

codesign --verify --deep --strict "$INSTALLED_APP"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INSTALLED_APP/Contents/Info.plist")" = "com.spotter.app"
test "$(stat -f '%N' "$INSTALLED_APP")" = "/Applications/Spotter.app"
rmdir "$STAGE_ROOT"
trap - EXIT

LEGACY_BUILT_APP="$DERIVED/Build/Products/Debug/Spotter Dev.app"
if [ -d "$LEGACY_BUILT_APP" ]; then
    rm -rf "$LEGACY_BUILT_APP"
    echo "▸ Removed the obsolete DerivedData Spotter Dev.app."
fi

if [ "$MODE" = "--install-only" ]; then
    echo "✓ Installed $INSTALLED_APP; it is stopped and ready for the debugger."
    exit 0
fi

echo "▸ Launching only ${INSTALLED_APP}…"
open -n "$INSTALLED_APP"
for _ in {1..100}; do
    PID="$(pgrep -x "Spotter" | head -n 1 || true)"
    if [ -n "$PID" ]; then
        break
    fi
    sleep 0.1
done

PIDS="$(pgrep -x "Spotter" || true)"
if [ "$(printf '%s\n' "$PIDS" | sed '/^$/d' | wc -l | tr -d ' ')" != "1" ]; then
    echo "✗ Expected exactly one Spotter process, found: ${PIDS:-none}" >&2
    exit 1
fi
PROCESS_PATH="$(ps -p "$PIDS" -o command=)"
case "$PROCESS_PATH" in
    /Applications/Spotter.app/Contents/MacOS/Spotter*) ;;
    *)
        echo "✗ Spotter launched from the wrong path: $PROCESS_PATH" >&2
        exit 1
        ;;
esac

echo "✓ Running one installed Spotter process: PID $PIDS"
