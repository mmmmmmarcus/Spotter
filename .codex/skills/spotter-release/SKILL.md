---
name: spotter-release
description: Prepare, validate, build, sign, notarize, publish, and verify Spotter beta or stable releases. Use when bumping Spotter's version, preparing release commits, producing Developer ID DMGs, running the GitHub Release workflow, checking release credentials, updating Homebrew release metadata, or auditing a published Spotter release.
---

# Spotter Release

Use `project.yml` as the only authoritative release version. Keep the generated Xcode project and
website fallback synchronized, and never pass an ad hoc version to the build or workflow.

## Establish context

1. Read `AGENTS.md`, `docs/development.md`, and `docs/signing.md` completely.
2. Inspect the branch, remote, tags, latest GitHub release, worktree, signing identities, and only
   the names of configured GitHub Actions secrets. Never print or request secret values in chat.
3. Distinguish a preparation request from authorization to publish. Building locally, dispatching a
   workflow, creating a GitHub Release, updating a tap, and announcing externally are separate
   state-changing actions; perform only those the user requested.

## Manage the version

1. Read `MARKETING_VERSION` from `project.yml`. Require exactly one numeric `x.y.z` value.
2. For a requested bump, update `project.yml` and the offline fallback in
   `website/src/data/site.ts`, then run `xcodegen generate`. Do not hand-edit
   `Spotter.xcodeproj/project.pbxproj`.
3. Do not invent the next semantic version when compatibility intent is ambiguous. Use the version
   the user names or ask for the missing decision.
4. Run `scripts/release-preflight.sh --expected <version>` after regeneration. Treat any mismatch
   as a blocker rather than overriding a version at build time.

## Validate and package

1. Review the complete intended diff and preserve unrelated user work. Run every standalone harness
   listed in `docs/development.md`; run website lint/build when website files changed.
2. For a local release artifact, verify the Developer ID identity and `spotter-notary` keychain
   profile, then run `./build-dmg.sh`. This notarizes the app and DMG, so do it only when the request
   authorizes a release build.
3. Confirm the resulting app and DMG version, Developer ID Team ID `SM96W8VVK9`, Hardened Runtime,
   secure timestamp, stapled tickets, Gatekeeper acceptance, filenames, and SHA-256.
4. Install and relaunch only when requested or required by `AGENTS.md`, replacing exactly
   `/Applications/Spotter.app` only after the new artifact passes all checks.

## Publish through GitHub Actions

1. Commit and push the prepared source before publishing. Stable releases must use the clean default
   branch; beta releases may use an explicitly selected branch.
2. Run `scripts/release-preflight.sh --expected <version> --publish`. It checks branch cleanliness,
   required secret names, version mirrors, and that the stable tag does not already exist.
3. Dispatch `.github/workflows/release.yml` with only `channel=beta` or `channel=stable`. The workflow
   reads the base version from `project.yml`; never create the release or tag separately.
4. Watch the workflow through completion. If it fails, inspect logs, fix the source/configuration,
   and create a new commit; do not manually publish partially verified artifacts.
5. Verify the GitHub Release tag, prerelease flag, DMG and updater zip names, checksums, downloadable
   signature/notarization status, Homebrew cask result, and optional Discord step. Report skipped
   integrations when their optional secrets are absent.

## Audit an existing release

Download its assets into a temporary directory, verify checksums and the mounted app's Developer ID,
Team ID, Hardened Runtime, notarization ticket, Gatekeeper assessment, bundle identifier, version and
channel naming. Move disposable audit artifacts to Trash or a scoped temporary directory; never
alter the installed app during a read-only audit.
