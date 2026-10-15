#!/bin/bash
# Pin the complete native runtime; model weights are downloaded only after in-app consent.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REVISION=f9b8106ffb8308b4f48b76149d270f7c2e6b4918
CACHE="$ROOT/build/SemanticHelper/$REVISION"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
STAMP="$REVISION $(shasum -a 256 "$ROOT/scripts/semantic-helper-package.swift" | cut -d ' ' -f 1) $(uname -m)"
if [[ ! -x "$CACHE/.build/release/digup" || "$(cat "$CACHE/.spotter-build" 2>/dev/null || true)" != "$STAMP" ]]; then
  command -v cmake >/dev/null || { echo "Install CMake before building the local embedding helper." >&2; exit 1; }
  mkdir -p "$(dirname "$CACHE")"
  if [[ ! -d "$CACHE/.git" ]]; then
    git init -q "$CACHE"
    git -C "$CACHE" remote add origin https://github.com/ARahim3/DigUp.git
    git -C "$CACHE" fetch -q --depth 1 origin "$REVISION"
    git -C "$CACHE" checkout -q --detach FETCH_HEAD
  fi
  [[ "$(git -C "$CACHE" rev-parse HEAD)" == "$REVISION" ]]
  cp "$ROOT/scripts/semantic-helper-package.swift" "$CACHE/Package.swift"
  (cd "$CACHE" && bash scripts/build-llama.sh && swift build -c release --product digup)
  echo "$STAMP" > "$CACHE/.spotter-build"
fi
if [[ -n "${TARGET_BUILD_DIR:-}" ]]; then
  DEST="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers"
  mkdir -p "$DEST"
  cp "$CACHE/.build/release/digup" "$DEST/spotter-embed"
  if [[ "${CODE_SIGNING_ALLOWED:-YES}" != NO ]]; then
    SIGN_ARGS=(--force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" --options runtime)
    SIGN_ARGS+=(--identifier "${PRODUCT_BUNDLE_IDENTIFIER:-com.spotter.app1}.embedding-helper")
    if [[ "${CONFIGURATION:-Debug}" == Release ]]; then SIGN_ARGS+=(--timestamp); fi
    codesign "${SIGN_ARGS[@]}" "$DEST/spotter-embed"
  fi
fi
