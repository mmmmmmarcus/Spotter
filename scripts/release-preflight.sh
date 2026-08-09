#!/bin/bash
# Validate release version mirrors; add --publish for stable publication prerequisites.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

EXPECTED=""
PUBLISH=false
while [ "$#" -gt 0 ]; do
    case "$1" in
        --expected)
            [ "$#" -ge 2 ] || { echo "✗ --expected requires a version." >&2; exit 2; }
            EXPECTED="$2"
            shift 2
            ;;
        --publish)
            PUBLISH=true
            shift
            ;;
        *)
            echo "Usage: $0 --expected x.y.z [--publish]" >&2
            exit 2
            ;;
    esac
done

if [[ ! "$EXPECTED" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "✗ --expected must be a numeric x.y.z version." >&2
    exit 2
fi

SOURCE_VERSIONS="$(sed -nE 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"([^"]+)".*/\1/p' project.yml)"
SOURCE_COUNT="$(printf '%s\n' "$SOURCE_VERSIONS" | sed '/^$/d' | wc -l | tr -d ' ')"
if [ "$SOURCE_COUNT" -ne 1 ] || [ "$SOURCE_VERSIONS" != "$EXPECTED" ]; then
    echo "✗ project.yml must contain exactly MARKETING_VERSION: \"$EXPECTED\"." >&2
    exit 1
fi

PBX_VERSIONS="$(sed -nE 's/^[[:space:]]*MARKETING_VERSION = ([^;]+);/\1/p' \
    Spotter.xcodeproj/project.pbxproj | sort -u)"
if [ "$PBX_VERSIONS" != "$EXPECTED" ]; then
    echo "✗ Spotter.xcodeproj is out of sync; run xcodegen generate." >&2
    exit 1
fi

WEBSITE_VERSION="$(sed -nE 's/^[[:space:]]*version:[[:space:]]*"v([^"]+)",/\1/p' \
    website/src/data/site.ts)"
if [ "$WEBSITE_VERSION" != "$EXPECTED" ]; then
    echo "✗ website/src/data/site.ts must contain version: \"v$EXPECTED\"." >&2
    exit 1
fi

if [ "$PUBLISH" = true ]; then
    command -v gh >/dev/null || { echo "✗ gh is required for publication checks." >&2; exit 1; }
    if ! git diff --quiet || ! git diff --cached --quiet; then
        echo "✗ Publication requires a clean worktree." >&2
        exit 1
    fi

    REPOSITORY="$(gh repo view --json nameWithOwner --jq '.nameWithOwner')"
    DEFAULT_BRANCH="$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')"
    CURRENT_BRANCH="$(git branch --show-current)"
    if [ "$CURRENT_BRANCH" != "$DEFAULT_BRANCH" ]; then
        echo "✗ Stable publication must run from $DEFAULT_BRANCH, not $CURRENT_BRANCH." >&2
        exit 1
    fi
    if git ls-remote --exit-code --tags origin "refs/tags/v$EXPECTED" >/dev/null 2>&1; then
        echo "✗ Tag v$EXPECTED already exists." >&2
        exit 1
    fi

    SECRET_NAMES="$(gh secret list --repo "$REPOSITORY" | awk '{print $1}')"
    for required in DEVELOPER_ID_P12_BASE64 DEVELOPER_ID_P12_PASSWORD \
        APPLE_NOTARY_APPLE_ID APPLE_NOTARY_PASSWORD; do
        if ! grep -Fxq "$required" <<< "$SECRET_NAMES"; then
            echo "✗ Missing GitHub Actions secret: $required" >&2
            exit 1
        fi
    done
fi

echo "✓ Release preflight passed for $EXPECTED."
