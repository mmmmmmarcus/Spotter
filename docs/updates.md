# In-app updates

Spotter reads static JSON metadata from GitHub Pages. Installation packages remain in GitHub
Releases. The app and website never query the GitHub REST API to check versions; the publishing
workflow alone uses an authenticated API request to generate the public metadata.

## Channels and versions

- Stable (`com.spotter.app1`) reads `https://mmmmmmarcus.github.io/Spotter/updates/stable.json`.
- Beta (`com.spotter.app1.beta`) reads the separate `updates/beta.json` file.
- Schema 1 contains `schemaVersion`, `channel`, and `releases`; each entry has `version`,
  `releaseURL`, `zipURL`, `dmgURL`, and Markdown `releaseNotes`.
- The app validates the schema, channel, version and exact HTTPS release/asset paths in the Spotter
  repository, then chooses the newest version strictly newer than the running app.
- Incompatible or malformed metadata is an error, never a successful up-to-date response or a
  reason to fall back to the REST API. No client-side assets lookup remains.

`project.yml` remains the source version. Published metadata comes only from completed, non-draft
GitHub Releases, never from a version bump that has not shipped. The generator keeps up to ten
releases per channel and refuses to advertise a newest release without both uploaded ZIP and DMG.
The website reads this same stable JSON and keeps its existing offline version fallback.

## Publication and migration

`scripts/generate-update-feed.py` runs in the Pages workflow with `GITHUB_TOKEN`. It reads releases
and their dedicated asset endpoints, validates exact names/URLs and writes both manifests into
`website/public/updates/` before the Vite build. Generated files are not committed. This is one
publishing-side authenticated operation, not a request from each visitor or app installation.

The release workflow publishes and verifies the GitHub artifacts first, then calls the reusable
website workflow with the expected release tag. Publication fails if that tag is absent from the
manifest. Pages deployments serialize across ordinary website pushes and releases, and public
manifests are fetched anonymously and compared byte-for-byte with the deployment artifact. The
release script waits for the app build, website build and verified Pages deployment before reporting
success. If feed deployment fails after the GitHub release is public, rerun the failed Pages job;
do not recreate the release or replace already-published packages.

Existing clients still contain their GitHub REST URL. Keep publishing GitHub release metadata and
ZIP/DMG files so they can install the transition version once, or use the manual Releases download.
Only after installing that version will they use Pages. This removes anonymous API quota dependence
from update checks, not the dependency on GitHub for package downloads or all network failures.

## Consent and network behavior

Manual Check for Updates is consent for one static-feed request. Daily automatic checks remain
opt-in; the dialog identifies GitHub Pages and explains what is sent. No account, identifier or
clipboard content is sent. Existing GitHub-provider consent remains applicable; the hosting provider
has not changed. The owning store checks consent before and after awaits, and uses a cacheless,
ephemeral URLSession. Packages install only after an explicit action.

All entry points share an in-flight guard and a 30-second cooldown after completed checks,
including failures. HTTP 429 and quota-related 403 responses respect Retry-After and rate-limit
reset headers with a minimum 60-second backoff. The retry deadline is bundle-keyed, device-local,
excluded from backup/sync and retained across relaunch. The old REST API deadline is ignored so
an exhausted API quota cannot block the new static host. HTTP, transport and parsing failures have
distinct messages. Both update surfaces offer a manual Releases link on failure. Diagnostics log
trigger source and response status/limit headers without response bodies.

## Installation and trust

When an update has a zip asset, installation follows this sequence:

1. Stream the archive into a temporary file and unpack it with `ditto`.
2. Read the running app's code-signing designated requirement.
3. Require the downloaded bundle, including nested code and all architectures, to satisfy it.
4. Copy the verified app beside the current installation.
5. Launch the verified incoming executable in versioned installer-helper mode, before AppKit starts.
   Wait for its readiness marker, then request normal application shutdown.
6. The helper watches the old PID with `kqueue/NOTE_EXIT` (120-second limit). Only after exit does it
   reverify signing identity and atomically exchange both paths with `renamex_np(RENAME_SWAP)`.
   The installed path stays occupied. Verification, timeout or exchange failure preserves the old app.
7. Relaunch through `/usr/bin/open -n`, then remove the retired bundle. Failure after the swap leaves
   the new app installed and records recovery guidance. The helper does not depend on Python.

The bounded `Logs/update-installer.log` under the bundle-keyed Application Support directory is
included in exported Diagnostics. Matching signatures and this shutdown barrier reduce permission
reset risks, but do not prove FDA retention on another Mac. The transition from an older version
still executes that older updater; this sequence applies to subsequent updates from 1.7.14 onward.

## Progress reporting and palette rows

Software Update uses one persistent command row. It shows Checking during a request, Download and Install Update when an update is available, and You’re on the latest version when current. The available state shows the installed and target versions on the second line; Return immediately acts on that same selected row. Busy and up-to-date states cannot trigger an installation. Failures retain a retry action. Current Version remains a non-selectable row below it.

Release notes below Current Version render the selected channel's latest static-feed
releaseNotes directly as Markdown, without an extra version heading. It is also available in Settings after a check, including
when already up to date. Missing or blank legacy notes show an explicit empty message and a release
page link. Notes are read from the existing feed response, without a separate request. Failed checks retain the last successful notes. This content adds no selectable
command row, so keyboard selection and installation behavior remain unchanged.

Every new release includes `docs/releases/<version>.md`; preflight and CI require it, and CI publishes
it as the release body before making the release public. See the tracked `spotter-release` skill.

The download uses `download(for:delegate:)` on the private ephemeral session. Its per-task
`URLSessionDownloadDelegate` reports actual received/expected bytes at most ten times per second,
including when the expected length is unknown. The upgrade row and Settings control show the real
fraction when available; unknown lengths use an indeterminate ring with no invented percentage.
`UpdateInstallProgress` advances only at real operation boundaries: downloading, unpacking,
signature verification, installing and relaunching. Post-download stages show a small spinning ring
and their phase name. There is no simulated overall installation percentage. The shared ring's
rotation is clock-driven, so switching from a measured download back to a spinner cannot leave it
stuck at the end of an earlier animation.

`UpdateStore` guards each progress delivery with the current installation identity and status;
`UpdateInstallProgress.accepts` rejects delayed byte callbacks and backward phase changes. A failed
or completed attempt cannot overwrite a newer attempt. `UpdatePresentation` keeps row ordering,
action availability and selection preservation pure and Foundation-only.

The signature check ties an update to both Spotter's bundle identifier and Developer ID. A stable
bundle cannot replace beta, beta cannot replace stable, and an unrelated or differently signed app
is rejected. Releases without a zip asset show **View release** and leave installation to the DMG.

Spotter 1.4.0 is the first Developer ID release. Users migrating from an older self-signed build must
install a current DMG once; later releases with the same designated requirement can update in place.

The first `com.spotter.app1` release is another one-time DMG migration because the former
`com.spotter.app` identifier could not be registered for CloudKit. Its first launch copies preferences,
Application Support content and caches from the former identity without deleting them, while omitting
the onboarding marker so macOS permissions are requested again. After that migration, updates retain
the new identifier and designated requirement and install in place normally.

## Verification

The standalone harness compiles the real parser and covers semantic-version ordering, malformed or
draft releases, zip discovery, channel isolation, palette action selection, retry availability,
measured progress, unknown lengths and delayed/out-of-order installation callbacks:

```sh
swiftc -swift-version 6 Spotter/Core/UpdateFeed.swift Spotter/Core/UpdatePresentation.swift Tools/update-test.swift \
  -o /tmp/update-test && /tmp/update-test
```

For a published release, also confirm the GitHub API returns the expected channel flag and both
assets. Signature, notarization and Gatekeeper checks are listed in [signing.md](signing.md).

Release note content is displayed directly, without an additional Release Notes heading.

The `update-network` case in `scripts/test-all.sh` compiles the real UpdateStore with an isolated
URLProtocol fixture and injected clock/defaults. It covers sequential and concurrent request
suppression, primary/secondary limits, retry deadlines across relaunch, malformed/HTTP failures,
static-host isolation, API-deadline migration and consent withdrawal. No live GitHub requests or real preferences are used.

`Tools/update-feed-generator-test.py` verifies draft/channel filtering, numeric ordering, required
artifacts, trusted URLs, expected-version checks and exclusion of private metadata.
