#!/bin/bash
# Removes one-off build folders and old DMGs under build/, keeping the folders the scripts reuse.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD="$ROOT/build"
KEEP=(DerivedData LocalInstallDerivedData SemanticHelper)

DRY_RUN=0
case "${1:-}" in
  --dry-run|-n) DRY_RUN=1 ;;
  "") ;;
  *) echo "usage: clean-build.sh [--dry-run]" >&2; exit 2 ;;
esac

[ -d "$BUILD" ] || { echo "Nothing to clean: $BUILD does not exist."; exit 0; }

# Deleting a folder an active build is writing into corrupts that build.
if pgrep -f "xcodebuild.*$BUILD" >/dev/null; then
  echo "An xcodebuild is writing into $BUILD; try again when it finishes." >&2
  exit 1
fi

shopt -s nullglob dotglob
removed=0
for entry in "$BUILD"/*; do
  name=$(basename "$entry")
  for kept in "${KEEP[@]}"; do
    [ "$name" = "$kept" ] && continue 2
  done
  size=$(du -sh "$entry" 2>/dev/null | cut -f1)
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "would remove  $size  build/$name"
  else
    rm -rf -- "$entry"
    echo "removed  $size  build/$name"
  fi
  removed=$((removed + 1))
done

[ "$removed" -eq 0 ] && echo "build/ is already clean."
echo "build/ is $(du -sh "$BUILD" | cut -f1)"
