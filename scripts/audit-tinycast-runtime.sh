#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
upstream="${1:?Pass the path to a Tinycast checkout}"
expected=71279c8de18fe77c56aa1cfaaeb68bf07748bbdd
actual=$(git -C "$upstream" rev-parse HEAD)
if [[ "$actual" != "$expected" ]]; then
  echo "Unexpected Tinycast revision: $actual; review upstream changes before updating attribution." >&2
  exit 1
fi
diff -qr "$upstream/Scripts/raycast-runtime/src" scripts/raycast-runtime/src
diff -u <(sed 's/com\.tinycast/com.spotter/g' "$upstream/Tinycast/Features/Extensions/Service/ExtensionRuntime.swift") Spotter/Plugins/RaycastExtensions/Service/ExtensionRuntime.swift
echo "Tinycast JavaScript sources and Swift runtime match $expected (host queue label adapted)."
