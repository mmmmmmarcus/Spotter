---
name: spotter-release
description: Prepare, validate, build, sign, notarize, publish, and verify stable Spotter releases end to end. Use when cutting a release, bumping Spotter's version, preparing or publishing a release, producing Developer ID DMGs, running the GitHub Release workflow, checking release credentials, or auditing a published Spotter release.
---

# Spotter Release

Use `project.yml` as the only authoritative release version. Keep the generated Xcode project and
website fallback synchronized, and never pass an ad hoc version to the build or workflow.

## Scope and context

1. Follow the supplied project instructions; do not reread `AGENTS.md` when it is already in context.
2. Run `scripts/release.sh context` for branch, remote, release, worktree and Actions-secret-name
   checks. Never print or request secret values.
3. Treat a request to release through this skill as authorization for the complete stable workflow:
   prepare, validate, commit, push, dispatch and verify. Do not stop to ask whether preparation is
   sufficient or whether publishing should begin. An explicitly read-only audit, local artifact or
   prepare-only request remains limited to that scope.
4. Publish only `stable`. Never ask which channel to use and never dispatch `beta`. Stable versions
   remain plain numeric `x.y.z` values; the Debug-only `SPOTTER_VERSION_SUFFIX` is never published.
5. Signing uses Developer ID team `HRG32XJ29R`. Before dispatching, confirm `scripts/release.sh
   context` lists `DEVELOPER_ID_P12_BASE64`, `DEVELOPER_ID_P12_PASSWORD`, `APPLE_NOTARY_APPLE_ID`
   and `APPLE_NOTARY_PASSWORD`, and that the stored certificate and notary account belong to that
   team. The workflow asserts the built app's `TeamIdentifier`, so a certificate from another team
   fails the build rather than publishing something unexpected. Never print secret values. Treat a
   certificate or notary account that does not match as a blocker; it cannot be worked around here.
6. `DEVELOPER_ID_PROFILE_BASE64_STABLE` and `_BETA` are obsolete. Releases carry no restricted
   entitlements and embed no provisioning profile, so delete those secrets rather than refreshing
   them, and do not reintroduce profile handling into the workflow.

## Manage the version

1. Read `MARKETING_VERSION` from `project.yml`. Require exactly one numeric `x.y.z` value.
2. For a requested bump, update `project.yml` and the offline fallback in
   `website/src/data/site.ts`, then run `xcodegen generate`. Do not hand-edit
   `Spotter.xcodeproj/project.pbxproj`.
3. Use a version named by the user. Otherwise, use `project.yml` when it is newer than the latest
   stable release; if it is not newer, increment the latest stable patch version. Do not ask the user
   to select a version or channel.
4. Write the required release notes below before running preflight.
5. Run `scripts/release-preflight.sh --expected <version>` after regeneration. Treat any mismatch
   as a blocker rather than overriding a version at build time.

## Write release notes — required for every release

1. Before validation or publication, write `docs/releases/<version>.md` for the version in
   `project.yml`. Commit it with the release; never publish first and add the notes afterward.
2. Review changes since the previous stable tag and describe the actual user-visible additions,
   improvements and fixes in concise Markdown bullets. Include migration or compatibility guidance
   when relevant. Generic build metadata, placeholders or an automatic commit list are not release
   notes. Do not claim checks or fixes that were not completed.
3. Keep notes readable inside Spotter's update screen: use short headings, paragraphs and bullets,
   with no embedded images or HTML. This file is the complete GitHub Release body and also appears
   in the in-app Release Notes area; do not include internal logs or credentials.
4. Preflight and CI require this version's notes with at least one non-empty change bullet. The
   workflow publishes through `--notes-file` and verifies the uploaded body before leaving draft.
5. After publication, verify the public release body matches the committed notes as part of the
   release audit. A release is incomplete if its notes are missing or describe the wrong version.
6. The first stable release signed by `HRG32XJ29R` changes the designated requirement, so the in-app
   updater correctly refuses it. Its notes must tell existing users to install that version from the
   DMG once and to re-grant Accessibility, Input Monitoring, Screen Recording and Full Disk Access,
   which macOS keys to the signing identity. See *Migrating from the former signing team* in
   `docs/signing.md`. Later releases from the same team update in place normally.

## Validate

The repository keeps a single branch: work lands on `main` directly, so a release ships whatever
`main` already holds. There is no pull request to merge or verify first, and no CI runs on pushes —
this phase is the only gate.

1. Release from `main`. Confirm the checkout is on it, clean, and level with `origin/main`.
2. Review the complete intended diff once and preserve unrelated user work. Review it against the
   `AGENTS.md` invariants, since nothing else reviews the code before it ships.
3. Run `scripts/release.sh prepare <version>`. It executes every standalone harness with four bounded
   workers, validates version mirrors and runs website lint/build only for website changes beyond the
   checked version fallback. Do not replace this full gate with change-selected tests.
4. Complete a Debug `xcodebuild` build with `-derivedDataPath build/LocalInstallDerivedData`, the
   shared install folder, never a new per-release path (`AGENTS.md`). `prepare` compiles the
   standalone harnesses but never the app itself, so this is the only check that catches a broken
   build before it is published.
5. Review the final diff after preparation and before committing.

## Publish through GitHub Actions

1. Commit the complete intended release as `Release <version>` without staging unrelated work.
2. Run `scripts/release.sh publish <version>`. This fetches and stops on divergence, runs publication
   preflight, pushes the default branch, dispatches only `channel=stable`, waits for the actual jobs
   instead of delayed workflow-finalization metadata, and audits both downloadable assets.
3. If publication fails, inspect the reported job logs, fix the source/configuration and create a new
   commit. Never manually publish a partial artifact or create the release/tag separately.
4. Do not pause at preparation, commit, push or dispatch boundaries. Stop only for a genuine blocker.

## Local release artifact

Only for an explicitly requested local Developer ID artifact, read `docs/development.md` and
`docs/signing.md` completely, verify the Developer ID identity and `spotter-notary` keychain profile,
then run `./build-dmg.sh`, which takes no arguments and resolves the Developer ID from the keychain
by Team ID. Confirm version, Team ID `HRG32XJ29R`, Hardened Runtime, timestamp, stapled tickets,
Gatekeeper, filenames and SHA-256. A Release build embeds no provisioning profile, so do not look
for one. Install only when explicitly requested or required
by project instructions, replacing exactly `/Applications/Spotter.app` after checks pass.
`./build-dmg.sh` reuses `build/DerivedData` and writes the DMG to `build/`; once the artifact is
handed over, run `scripts/clean-build.sh` so superseded DMGs and any stray build folders don't pile up.

## Audit an existing release

Run `scripts/release.sh audit <version>`. It verifies stable metadata, exact asset names and GitHub
digests, then independently checks the DMG and updater ZIP app for Developer ID, Team ID, Hardened
Runtime, timestamp, stapled ticket, Gatekeeper acceptance, bundle identifier and version. It uses a
scoped temporary directory and never alters the installed app.
