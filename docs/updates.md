# In-app updates

Spotter checks and installs releases from the public GitHub Releases feed. The updater is deliberately
small: feed parsing is pure Foundation code, network state belongs to `UpdateStore`, and the user must
click before any installation starts.

## Channels and versions

- Stable (`com.spotter.app`) considers only non-prerelease GitHub Releases.
- Beta (`com.spotter.app.beta`) considers only prereleases, so it never offers a stable bundle with a
  different identifier and designated requirement.
- Tags use semantic versions: stable `v1.4.0`, beta `v1.4.0-beta.<Actions run number>`.
- A release must be strictly newer than the running `CFBundleShortVersionString`.

`project.yml` is the release version's single source of truth. CI publishes both
`Spotter-<version>.dmg` for manual installation and `Spotter-<version>.zip` for the in-app updater.
The zip contains the same Developer ID-signed, notarized and stapled app as the DMG.

## Consent and network behavior

**Check for Updates** in the launcher and **Settings → General → Check for Updates** are consent for
one feed request. The launcher command opens the complete Software Update flow: it checks immediately,
reports the active channel and current result, offers the verified in-app install when a zip exists,
and falls back to the release page for a DMG-only release. The automatic daily check ships disabled;
enabling it presents a dialog naming GitHub, its cadence and the data sent. Its flag is local-only and
is never included in settings export or sync.

Automatic checks verify consent immediately before the request and again after its `await`. Turning
the toggle off cancels the loop and prevents an in-flight response from changing updater state. All
requests use a private ephemeral `URLSession` with no URL cache.

## Installation and trust

When an update has a zip asset, installation follows this sequence:

1. Download into a temporary location and unpack with `ditto`.
2. Read the running app's code-signing designated requirement.
3. Require the downloaded bundle, including nested code and all architectures, to satisfy it.
4. Copy the verified app beside the current installation before removing the old bundle.
5. Rename the staged bundle into place and relaunch through the normal application shutdown path.

The signature check ties an update to both Spotter's bundle identifier and Developer ID. A stable
bundle cannot replace beta, beta cannot replace stable, and an unrelated or differently signed app
is rejected. Releases without a zip asset show **View release** and leave installation to the DMG.

Spotter 1.4.0 is the first Developer ID release. Users migrating from an older self-signed build must
install a current DMG once; later releases with the same designated requirement can update in place.

## Verification

The standalone harness compiles the real parser and covers semantic-version ordering, malformed or
draft releases, zip discovery, and both directions of channel isolation:

```sh
swiftc -swift-version 6 Spotter/Core/UpdateFeed.swift Tools/update-test.swift \
  -o /tmp/update-test && /tmp/update-test
```

For a published release, also confirm the GitHub API returns the expected channel flag and both
assets. Signature, notarization and Gatekeeper checks are listed in [signing.md](signing.md).
