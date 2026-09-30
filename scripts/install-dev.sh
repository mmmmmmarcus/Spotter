#!/bin/bash
# An atomic replacement avoids an uninstall gap; it cannot guarantee macOS retains TCC grants.
set -euo pipefail

NEW_APP=${1:?usage: install-dev.sh <path to built Spotter.app>}
DEST=/Applications/Spotter.app

[ -d "$NEW_APP" ] || { echo "no such bundle: $NEW_APP" >&2; exit 1; }
codesign --verify --deep --strict "$NEW_APP"

# Check identity before quitting or touching the installed bundle.
if [ -d "$DEST" ]; then
  REQUIREMENT=$(codesign -d -r- "$DEST" 2>&1 | sed -n 's/^designated => //p')
  if [ -z "$REQUIREMENT" ]; then
    echo "Cannot read the installed app's signing requirement; refusing replacement." >&2
    exit 1
  fi
  if ! codesign --verify --deep --strict --all-architectures -R "=$REQUIREMENT" "$NEW_APP"; then
    echo "Signing identity differs from the installed app; refusing replacement to avoid losing privacy grants." >&2
    exit 1
  fi
fi

# Wait for a real exit so recently written preferences are flushed.
osascript -e 'tell application "Spotter" to quit' >/dev/null 2>&1 || true
for _ in $(seq 1 50); do pgrep -x Spotter >/dev/null || break; sleep 0.2; done
if pgrep -x Spotter >/dev/null; then
  echo "Spotter did not quit in 10s; refusing to swap under a live process" >&2
  exit 1
fi

if [ -d "$DEST" ]; then
  STAGE="/Applications/.spotter-install-$$-Spotter.app"
  rm -rf "$STAGE"
  cp -R "$NEW_APP" "$STAGE"
  python3 - "$STAGE" "$DEST" <<'PY'
import ctypes, ctypes.util, sys
libc = ctypes.CDLL(ctypes.util.find_library("c"), use_errno=True)
libc.renamex_np.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
RENAME_SWAP = 0x0002
rc = libc.renamex_np(sys.argv[1].encode(), sys.argv[2].encode(), RENAME_SWAP)
if rc != 0:
    sys.exit("atomic swap failed, errno %d" % ctypes.get_errno())
PY
  rm -rf "$STAGE"
  echo "swapped atomically with a compatible signing identity; TCC retention requires runtime verification"
else
  cp -R "$NEW_APP" "$DEST"
  echo "first install (no previous bundle)"
fi

open "$DEST"
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$DEST/Contents/Info.plist"
