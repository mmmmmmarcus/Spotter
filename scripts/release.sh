#!/bin/bash
# Deterministic orchestration for stable Spotter release preparation, publication and audit.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

usage() {
    cat >&2 <<'EOF'
Usage:
  scripts/release.sh context
  scripts/release.sh prepare [x.y.z]
  scripts/release.sh publish [x.y.z]
  scripts/release.sh audit [x.y.z]
EOF
}

require_command() {
    command -v "$1" >/dev/null || { echo "✗ $1 is required." >&2; exit 1; }
}

source_version() {
    local versions
    local count
    versions="$(sed -nE 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"([^"]+)".*/\1/p' project.yml)"
    count="$(printf '%s\n' "$versions" | sed '/^$/d' | wc -l | tr -d ' ')"
    if [ "$count" -ne 1 ] || [[ ! "$versions" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "✗ project.yml must contain exactly one numeric MARKETING_VERSION." >&2
        exit 1
    fi
    printf '%s\n' "$versions"
}

requested_version() {
    local requested="${1:-}"
    local current
    current="$(source_version)"
    if [ -n "$requested" ] && [ "$requested" != "$current" ]; then
        echo "✗ Expected $requested, found $current in project.yml." >&2
        exit 1
    fi
    printf '%s\n' "$current"
}

audit_version() {
    local requested="${1:-}"
    if [ -z "$requested" ]; then
        source_version
        return
    fi
    if [[ ! "$requested" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "✗ Audit version must use numeric x.y.z format." >&2
        exit 1
    fi
    printf '%s\n' "$requested"
}

latest_stable_tag() {
    local tag
    while IFS= read -r tag; do
        if [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            printf '%s\n' "$tag"
            return 0
        fi
    done < <(git tag --sort=-version:refname)
    return 1
}

website_needs_build() {
    local baseline
    local changed
    baseline="$(latest_stable_tag || true)"
    if [ -n "$baseline" ]; then
        changed="$(
            git diff --name-only "$baseline" -- website
            git ls-files --others --exclude-standard -- website
        )"
    else
        changed="$(
            git status --porcelain=v1 --untracked-files=all -- website \
                | sed -E 's/^[^ ]+ +//'
        )"
    fi
    printf '%s\n' "$changed" \
        | sed '/^$/d' \
        | grep -Fvx 'website/src/data/site.ts' \
        | grep -q .
}

run_context() {
    require_command gh
    git fetch --prune --tags origin >/dev/null

    local version
    local repository
    local default_branch
    local current_branch
    local counts
    local latest_release
    version="$(source_version)"
    repository="$(gh repo view --json nameWithOwner --jq '.nameWithOwner')"
    default_branch="$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')"
    current_branch="$(git branch --show-current)"
    counts="$(git rev-list --left-right --count "HEAD...origin/$default_branch")"
    latest_release="$(gh release view --json tagName,isPrerelease,publishedAt,url \
        --jq '[.tagName, .isPrerelease, .publishedAt, .url] | @tsv')"

    echo "Repository: $repository"
    echo "Version: $version"
    echo "Branch: $current_branch (default: $default_branch; ahead/behind: $counts)"
    echo "Latest release: $latest_release"
    echo "Configured Actions secrets:"
    gh secret list --repo "$repository" | awk '{print "  " $1}' | sort
    echo "Worktree:"
    if [ -z "$(git status --short)" ]; then
        echo "  clean"
    else
        git status --short | sed 's/^/  /'
    fi
}

run_prepare() {
    local version
    local jobs
    version="$(requested_version "${1:-}")"
    jobs="${SPOTTER_TEST_JOBS:-4}"

    scripts/release-preflight.sh --expected "$version"
    scripts/test-all.sh --jobs "$jobs"
    if website_needs_build; then
        echo "▸ Website changes beyond the release version mirror require validation…"
        if [ ! -d website/node_modules ]; then
            (cd website && npm ci)
        fi
        (cd website && npm run lint && npm run build)
    else
        echo "✓ Website build skipped; no website changes beyond the checked version mirror."
    fi
    git diff --check
    echo "✓ Release $version preparation passed."
}

wait_for_new_run() {
    local head_sha="$1"
    local default_branch="$2"
    local previous_id="$3"
    local attempt
    local run_id

    for attempt in $(seq 1 30); do
        run_id="$(gh run list --workflow release.yml --branch "$default_branch" \
            --event workflow_dispatch --limit 20 --json databaseId,headSha \
            --jq "(map(select(.headSha == \"$head_sha\" and .databaseId > $previous_id)) | sort_by(.databaseId) | last | .databaseId) // empty")"
        if [ -n "$run_id" ]; then
            printf '%s\n' "$run_id"
            return 0
        fi
        sleep 2
    done
    echo "✗ GitHub did not expose the dispatched Release run within 60 seconds." >&2
    return 1
}

wait_for_jobs() {
    local run_id="$1"
    local attempt
    local state
    local workflow_status
    local workflow_conclusion
    local total
    local incomplete
    local failed

    for attempt in $(seq 1 240); do
        state="$(gh run view "$run_id" --json status,conclusion,jobs --jq \
            '[.status, (if .conclusion == "" then "pending" else .conclusion end), (.jobs | length), ( [.jobs[] | select(.status != "completed")] | length ), ( [.jobs[] | select(.status == "completed" and .conclusion != "success")] | length )] | @tsv')"
        IFS=$'\t' read -r workflow_status workflow_conclusion total incomplete failed <<< "$state"
        if [ "$failed" -ne 0 ]; then
            echo "✗ Release workflow $run_id failed." >&2
            gh run view "$run_id" --log-failed || true
            return 1
        fi
        if [ "$total" -gt 0 ] && [ "$incomplete" -eq 0 ]; then
            echo "✓ Every Release job completed successfully."
            return 0
        fi
        if [ "$workflow_status" = completed ]; then
            echo "✗ Release workflow completed as ${workflow_conclusion:-unknown} without successful jobs." >&2
            gh run view "$run_id" --log-failed || true
            return 1
        fi
        if [ $((attempt % 4)) -eq 1 ]; then
            gh run view "$run_id" --json jobs \
                --jq '.jobs[] | "  \(.name): \(.status) \(.conclusion // "")"'
        fi
        sleep 15
    done
    echo "✗ Release jobs did not complete within one hour." >&2
    return 1
}

verify_signature() {
    local app="$1"
    local version="$2"
    local signature
    local team
    local bundle
    local built_version

    codesign --verify --deep --strict --verbose=2 "$app"
    signature="$(codesign -dv --verbose=4 "$app" 2>&1)"
    team="$(sed -n 's/^TeamIdentifier=//p' <<< "$signature")"
    [ "$team" = "SM96W8VVK9" ] \
        || { echo "✗ $app has unexpected TeamIdentifier ${team:-none}." >&2; return 1; }
    grep -q 'flags=.*runtime' <<< "$signature" \
        || { echo "✗ $app is missing Hardened Runtime." >&2; return 1; }
    grep -q '^Timestamp=' <<< "$signature" \
        || { echo "✗ $app is missing a secure timestamp." >&2; return 1; }
    xcrun stapler validate "$app"
    spctl --assess --type execute --verbose=2 "$app"
    bundle="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")"
    built_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
    [ "$bundle" = "com.spotter.app1" ] \
        || { echo "✗ $app has bundle identifier $bundle." >&2; return 1; }
    [ "$built_version" = "$version" ] \
        || { echo "✗ $app has version $built_version, expected $version." >&2; return 1; }
}

AUDIT_DIR=""
AUDIT_MOUNT=""
AUDIT_MOUNTED=false
cleanup_audit() {
    if [ "$AUDIT_MOUNTED" = true ] && [ -n "$AUDIT_MOUNT" ]; then
        hdiutil detach "$AUDIT_MOUNT" >/dev/null 2>&1 || true
    fi
    case "$AUDIT_DIR" in
        /tmp/spotter-release-audit.*) rm -rf "$AUDIT_DIR" ;;
    esac
}

run_audit() {
    require_command gh
    require_command codesign
    require_command xcrun

    local version
    local tag
    local dmg_name
    local zip_name
    local metadata
    local release_tag
    local draft
    local prerelease
    local release_name
    local asset_names
    local repository
    local dmg_digest
    local zip_digest
    local dmg_sha
    local zip_sha
    local dmg
    local zip
    local signature
    local team

    version="$(audit_version "${1:-}")"
    tag="v$version"
    dmg_name="Spotter-$version.dmg"
    zip_name="Spotter-$version.zip"

    metadata="$(gh release view "$tag" --json tagName,isDraft,isPrerelease,name,assets \
        --jq '[.tagName, .isDraft, .isPrerelease, .name, ([.assets[].name] | sort | join(","))] | @tsv')"
    IFS=$'\t' read -r release_tag draft prerelease release_name asset_names <<< "$metadata"
    [ "$release_tag" = "$tag" ] || { echo "✗ Expected release tag $tag." >&2; exit 1; }
    [ "$draft" = false ] || { echo "✗ $tag is still a draft." >&2; exit 1; }
    [ "$prerelease" = false ] || { echo "✗ $tag is marked prerelease." >&2; exit 1; }
    [ "$release_name" = "Spotter $version" ] \
        || { echo "✗ Unexpected release name: $release_name" >&2; exit 1; }
    [ "$asset_names" = "$dmg_name,$zip_name" ] \
        || { echo "✗ Unexpected release assets: $asset_names" >&2; exit 1; }

    repository="$(gh repo view --json nameWithOwner --jq '.nameWithOwner')"
    dmg_digest="$(gh api "repos/$repository/releases/tags/$tag" \
        --jq ".assets[] | select(.name == \"$dmg_name\") | .digest")"
    zip_digest="$(gh api "repos/$repository/releases/tags/$tag" \
        --jq ".assets[] | select(.name == \"$zip_name\") | .digest")"
    [[ "$dmg_digest" =~ ^sha256:[0-9a-f]{64}$ ]] \
        || { echo "✗ GitHub did not report a SHA-256 digest for $dmg_name." >&2; exit 1; }
    [[ "$zip_digest" =~ ^sha256:[0-9a-f]{64}$ ]] \
        || { echo "✗ GitHub did not report a SHA-256 digest for $zip_name." >&2; exit 1; }

    AUDIT_DIR="$(mktemp -d /tmp/spotter-release-audit.XXXXXX)"
    AUDIT_MOUNT="$AUDIT_DIR/mount"
    mkdir "$AUDIT_MOUNT" "$AUDIT_DIR/zip"
    trap cleanup_audit EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    gh release download "$tag" --dir "$AUDIT_DIR" \
        --pattern "$dmg_name" --pattern "$zip_name"
    dmg="$AUDIT_DIR/$dmg_name"
    zip="$AUDIT_DIR/$zip_name"
    dmg_sha="$(shasum -a 256 "$dmg" | awk '{print $1}')"
    zip_sha="$(shasum -a 256 "$zip" | awk '{print $1}')"
    [ "sha256:$dmg_sha" = "$dmg_digest" ] || { echo "✗ DMG digest mismatch." >&2; exit 1; }
    [ "sha256:$zip_sha" = "$zip_digest" ] || { echo "✗ ZIP digest mismatch." >&2; exit 1; }

    codesign --verify --strict --verbose=2 "$dmg"
    signature="$(codesign -dv --verbose=4 "$dmg" 2>&1)"
    team="$(sed -n 's/^TeamIdentifier=//p' <<< "$signature")"
    [ "$team" = "SM96W8VVK9" ] || { echo "✗ DMG has unexpected TeamIdentifier." >&2; exit 1; }
    grep -q '^Timestamp=' <<< "$signature" || { echo "✗ DMG is missing a secure timestamp." >&2; exit 1; }
    xcrun stapler validate "$dmg"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"

    diskutil image attach --readOnly --nobrowse --mountPoint "$AUDIT_MOUNT" "$dmg" >/dev/null
    AUDIT_MOUNTED=true
    verify_signature "$AUDIT_MOUNT/Spotter.app" "$version"
    ditto -x -k "$zip" "$AUDIT_DIR/zip"
    verify_signature "$AUDIT_DIR/zip/Spotter.app" "$version"

    echo "✓ Audited stable release $tag."
    echo "  DMG SHA-256: $dmg_sha"
    echo "  ZIP SHA-256: $zip_sha"
}

run_publish() {
    require_command gh

    local version
    local default_branch
    local current_branch
    local counts
    local ahead
    local behind
    local head_sha
    local previous_id
    local run_id
    local run_url
    version="$(requested_version "${1:-}")"
    default_branch="$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')"
    current_branch="$(git branch --show-current)"
    [ "$current_branch" = "$default_branch" ] \
        || { echo "✗ Stable publishing requires $default_branch." >&2; exit 1; }

    git fetch --prune --tags origin
    counts="$(git rev-list --left-right --count "HEAD...origin/$default_branch")"
    read -r ahead behind <<< "$counts"
    [ "$behind" -eq 0 ] \
        || { echo "✗ Local $default_branch is behind origin/$default_branch; stop instead of overwriting history." >&2; exit 1; }
    scripts/release-preflight.sh --expected "$version" --publish
    if [ "$ahead" -gt 0 ]; then
        git push origin "$default_branch"
    fi
    [ "$(git rev-parse HEAD)" = "$(git rev-parse "origin/$default_branch")" ] \
        || { echo "✗ Local and remote $default_branch do not match after push." >&2; exit 1; }

    head_sha="$(git rev-parse HEAD)"
    previous_id="$(gh run list --workflow release.yml --branch "$default_branch" \
        --event workflow_dispatch --limit 20 --json databaseId,headSha \
        --jq "map(select(.headSha == \"$head_sha\") | .databaseId) | max // 0")"
    gh workflow run release.yml --ref "$default_branch" -f channel=stable
    run_id="$(wait_for_new_run "$head_sha" "$default_branch" "$previous_id")"
    run_url="$(gh run view "$run_id" --json url --jq '.url')"
    echo "▸ Watching Release jobs: $run_url"
    wait_for_jobs "$run_id"
    run_audit "$version"
    echo "✓ Stable Spotter $version is published and verified."
    echo "  Workflow: $run_url"
    echo "  Release: https://github.com/$(gh repo view --json nameWithOwner --jq '.nameWithOwner')/releases/tag/v$version"
}

COMMAND="${1:-}"
case "$COMMAND" in
    context)
        [ "$#" -eq 1 ] || { usage; exit 2; }
        run_context
        ;;
    prepare)
        [ "$#" -le 2 ] || { usage; exit 2; }
        run_prepare "${2:-}"
        ;;
    publish)
        [ "$#" -le 2 ] || { usage; exit 2; }
        run_publish "${2:-}"
        ;;
    audit)
        [ "$#" -le 2 ] || { usage; exit 2; }
        run_audit "${2:-}"
        ;;
    *)
        usage
        exit 2
        ;;
esac
