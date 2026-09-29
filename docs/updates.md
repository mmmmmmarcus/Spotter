# In-app updates

Spotter checks and installs releases from the public GitHub Releases feed. The updater is deliberately
small: feed parsing is pure Foundation code, network state belongs to `UpdateStore`, and the user must
click before any installation starts.

## Channels and versions

- Stable (`com.spotter.app1`) considers only non-prerelease GitHub Releases.
- Beta (`com.spotter.app1.beta`) considers only prereleases, so it never offers a stable bundle with a
  different identifier and designated requirement.
- Tags use semantic versions: stable `v1.4.0`, beta `v1.4.0-beta.<Actions run number>`.
- A release must be strictly newer than the running `CFBundleShortVersionString`.

`project.yml` is the release version's single source of truth. CI publishes both
`Spotter-<version>.dmg` for manual installation and `Spotter-<version>.zip` for the in-app updater.
The zip contains the same Developer ID-signed, notarized and stapled app as the DMG.
CI creates a draft, uploads and checks both assets, then publishes it. If GitHub's releases list
still omits the ZIP, the updater queries that release's dedicated assets endpoint before offering
manual installation. A failed asset lookup reports a retryable check failure instead of pretending
the release has no updater. Automatic consent and cancellation are checked around both requests.

## Consent and network behavior

**Check for Updates** in the launcher and **Settings → General → Check for Updates** are consent for
one update check, including an asset lookup when the release list omits the updater ZIP. The launcher command opens the complete Software Update flow inside the palette: it checks immediately,
reports the active channel and current result, offers the verified in-app install when a zip exists,
and falls back to the release page for a DMG-only release. Escape and the header back button both
return to a fresh launcher root. The automatic daily check ships disabled;
enabling it presents a dialog naming GitHub, its cadence and the data sent. Its saved choice enters
trusted v3 backups and automatic sync; trusting that file is the consent act on another Mac.

Automatic checks verify consent immediately before the request and again after its `await`. Turning
the toggle off cancels the loop and prevents an in-flight response from changing updater state. All
requests use a private ephemeral `URLSession` with no URL cache.

## Installation and trust

When an update has a zip asset, installation follows this sequence:

1. Stream the archive into a temporary file and unpack it with `ditto`.
2. Read the running app's code-signing designated requirement.
3. Require the downloaded bundle, including nested code and all architectures, to satisfy it.
4. Copy the verified app beside the current installation.
5. Exchange the staged and installed bundles in one atomic `renamex_np(RENAME_SWAP)` and relaunch
   through the normal application shutdown path. The installed path is never empty for even an
   instant — tccd watches app deletions and invalidates Full Disk Access for a bundle it saw
   removed, which is exactly what the earlier remove-then-rename swap looked like once per update.
   A filesystem without `RENAME_SWAP` falls back to remove-and-rename, trading that TCC guarantee
   for still completing the update; the retired bundle is deleted under its staging name.

## Progress reporting and palette rows

Software Update uses the shared palette row appearance, with no centered status screen. A known
new version adds an Upgrade row first; Check for Updates is always present, followed by a
non-selectable Current Version row. Up/down, Return and clicks act on the selected command. A check
that discovers a new version preserves the selected Check row rather than turning the next Return
into an installation. Busy operations cannot start a second check/install. Errors appear beneath
Check for Updates, and a known release remains available for retry after failure.

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
