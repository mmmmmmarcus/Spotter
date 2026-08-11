#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
cd "$ROOT"

EXPECTED=""
PUBLISH=false
while [ "$#" -gt 0 ]; do
    case "$1" in
        --expected)
            EXPECTED="${2:-}"
            shift 2
            ;;
        --publish)
            PUBLISH=true
            shift
            ;;
        *)
            echo "Usage: $0 [--expected x.y.z] [--publish]" >&2
            exit 2
            ;;
    esac
done

VERSION_LINES="$(sed -nE 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"([^"]+)".*/\1/p' project.yml)"
VERSION_COUNT="$(printf '%s\n' "$VERSION_LINES" | sed '/^$/d' | wc -l | tr -d ' ')"
if [ "$VERSION_COUNT" -ne 1 ]; then
    echo "✗ project.yml must contain exactly one MARKETING_VERSION." >&2
    exit 1
fi
VERSION="$VERSION_LINES"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "✗ MARKETING_VERSION must use numeric x.y.z format: $VERSION" >&2
    exit 1
fi
if [ -n "$EXPECTED" ] && [ "$VERSION" != "$EXPECTED" ]; then
    echo "✗ Expected $EXPECTED, found $VERSION in project.yml." >&2
    exit 1
fi
if [ "$(grep -Fc 'SPOTTER_VERSION_SUFFIX: "-dev"' project.yml)" -ne 1 ]; then
    echo "✗ project.yml must keep exactly one Debug SPOTTER_VERSION_SUFFIX: \"-dev\"." >&2
    exit 1
fi

PBX_VERSIONS="$(sed -nE 's/^[[:space:]]*MARKETING_VERSION = ([^;]+);/\1/p' Spotter.xcodeproj/project.pbxproj | sort -u)"
if [ "$PBX_VERSIONS" != "$VERSION" ]; then
    echo "✗ Generated Xcode project version is '${PBX_VERSIONS:-missing}', expected $VERSION; run xcodegen generate." >&2
    exit 1
fi
if [ "$(grep -Fc 'SPOTTER_VERSION_SUFFIX = "-dev";' Spotter.xcodeproj/project.pbxproj)" -ne 1 ]; then
    echo "✗ Generated Xcode project is missing the Debug -dev suffix; run xcodegen generate." >&2
    exit 1
fi
SITE_VERSION="$(sed -nE 's/^[[:space:]]*version: "v([^"]+)",/\1/p' website/src/data/site.ts)"
if [ "$SITE_VERSION" != "$VERSION" ]; then
    echo "✗ Website fallback version is '${SITE_VERSION:-missing}', expected $VERSION." >&2
    exit 1
fi
if ! grep -Fq '<string>$(MARKETING_VERSION)$(SPOTTER_VERSION_SUFFIX)</string>' Spotter/Info.plist; then
    echo "✗ Spotter/Info.plist no longer combines the base version with its build-channel suffix." >&2
    exit 1
fi
if grep -Fq 'inputs.version' .github/workflows/release.yml; then
    echo "✗ Release workflow still accepts a second, drifting version input." >&2
    exit 1
fi

if [ "$PUBLISH" = true ]; then
    if ! git diff --quiet || ! git diff --cached --quiet || [ -n "$(git status --short)" ]; then
        echo "✗ Publish preflight requires a clean worktree." >&2
        exit 1
    fi
    DEFAULT_BRANCH="$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')"
    CURRENT_BRANCH="$(git branch --show-current)"
    if [ "$CURRENT_BRANCH" != "$DEFAULT_BRANCH" ]; then
        echo "✗ Stable publishing requires $DEFAULT_BRANCH; current branch is $CURRENT_BRANCH." >&2
        exit 1
    fi
    SECRET_NAMES="$(gh secret list | awk '{print $1}')"
    for NAME in DEVELOPER_ID_P12_BASE64 DEVELOPER_ID_P12_PASSWORD APPLE_NOTARY_APPLE_ID APPLE_NOTARY_PASSWORD; do
        if ! grep -Fxq "$NAME" <<< "$SECRET_NAMES"; then
            echo "✗ Missing GitHub Actions secret: $NAME" >&2
            exit 1
        fi
    done
    if git ls-remote --exit-code --tags origin "refs/tags/v${VERSION}" >/dev/null 2>&1; then
        echo "✗ Stable tag v${VERSION} already exists." >&2
        exit 1
    fi
fi

echo "✓ Spotter release version $VERSION is synchronized."
