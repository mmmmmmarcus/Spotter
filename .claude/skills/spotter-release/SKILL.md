---
name: spotter-release
description: Prepare, validate, build, sign, notarize, publish, and verify stable Spotter releases end to end, optionally merging release-ready pull requests first. Use when merging a PR and cutting a release, bumping Spotter's version, preparing or publishing a release, producing Developer ID DMGs, running the GitHub Release workflow, checking release credentials, or auditing a published Spotter release.
---

# Spotter Release

Use `project.yml` as the only authoritative release version. Keep the generated Xcode project and
website fallback synchronized, and never pass an ad hoc version to the build or workflow.

## Scope and context

1. Follow the supplied project instructions; do not reread `AGENTS.md` when it is already in context.
2. Run `scripts/release.sh context` for branch, remote, release, worktree and Actions-secret-name
   checks. Never print or request secret values.
3. Treat a request to release through this skill as authorization for the complete stable workflow:
   merge requested pull requests, prepare, validate, commit, push, dispatch and verify. Do not stop
   to ask whether preparation is sufficient or whether publishing should begin. An explicitly
   read-only audit, local artifact, merge-only or prepare-only request remains limited to that scope.
4. Publish only `stable`. Never ask which channel to use and never dispatch `beta`. Stable versions
   remain plain numeric `x.y.z` values; the Debug-only `SPOTTER_VERSION_SUFFIX` is never published.

## Merge pull requests

Run this phase when the request includes merging — "merge and release", a named PR, or open pull
requests the user wants shipped. Do not pause between a completed merge and the release phases.

1. Resolve the merge set: the pull requests the user names, otherwise every open PR. State the set
   before acting.
2. Verify each PR before merging — the repository runs no CI on PR branches, and a PR description's
   claims are not verification. In a detached scratch worktree at the PR head, outside the working
   tree: require the head to sit on top of `origin/main`, review the full diff against `AGENTS.md`
   invariants, run `scripts/test-all.sh --jobs 4`, and complete a Debug `xcodebuild` build.
3. Squash-merge each verified PR (`gh pr merge <n> --squash`) to keep `main` linear, then delete its
   remote branch. Skip a PR that fails verification and report its blocker; a failed PR blocks only
   itself — but when it is the reason for the release, stop instead of publishing without it.
4. Fast-forward the local `main` checkout, remove the scratch worktree, and continue with the
   release so the merged work ships in the published version.

## Manage the version

1. Read `MARKETING_VERSION` from `project.yml`. Require exactly one numeric `x.y.z` value.
2. For a requested bump, update `project.yml` and the offline fallback in
   `website/src/data/site.ts`, then run `xcodegen generate`. Do not hand-edit
   `Spotter.xcodeproj/project.pbxproj`.
3. Use a version named by the user. Otherwise, use `project.yml` when it is newer than the latest
   stable release; if it is not newer, increment the latest stable patch version. Do not ask the user
   to select a version or channel.
4. Run `scripts/release-preflight.sh --expected <version>` after regeneration. Treat any mismatch
   as a blocker rather than overriding a version at build time.

## Validate

1. Review the complete intended diff once and preserve unrelated user work.
2. Run `scripts/release.sh prepare <version>`. It executes every standalone harness with four bounded
   workers, validates version mirrors and runs website lint/build only for website changes beyond the
   checked version fallback. Do not replace this full gate with change-selected tests.
3. Review the final diff after preparation and before committing.

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
then run `./build-dmg.sh`. Confirm version, Team ID `SM96W8VVK9`, Hardened Runtime, timestamp,
stapled tickets, Gatekeeper, filenames and SHA-256. Install only when explicitly requested or required
by project instructions, replacing exactly `/Applications/Spotter.app` after checks pass.

## Audit an existing release

Run `scripts/release.sh audit <version>`. It verifies stable metadata, exact asset names and GitHub
digests, then independently checks the DMG and updater ZIP app for Developer ID, Team ID, Hardened
Runtime, timestamp, stapled ticket, Gatekeeper acceptance, bundle identifier and version. It uses a
scoped temporary directory and never alters the installed app.
