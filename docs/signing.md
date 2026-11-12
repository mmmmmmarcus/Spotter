# Signing and notarization

Spotter signs everything with one identity where possible:

- Ordinary Debug builds are local `-dev` versions signed with the same
  `Developer ID Application: … (Q9MD524YL5)` identity releases
  use. macOS keys TCC grants (Full Disk Access, Accessibility, Input Monitoring) to the signing
  requirements, so sharing a compatible designated requirement avoids identity changes during
  rebuilds and dev↔stable swaps of `/Applications/Spotter.app`. This is not a guarantee of TCC
  retention. `scripts/install-dev.sh` checks the new app against the installed app's requirement
  before quitting or replacing it, and rejects incompatible builds. The opt-in CloudKit dev installer uses Apple
  Development signing instead.
- Release builds additionally enable Hardened Runtime, include a secure timestamp and are notarized
  by Apple.
- On a machine without the company certificate, fall back to the self-signed `Spotter Self-Signed`
  identity (section 1) by overriding `CODE_SIGN_IDENTITY` — grants then survive rebuilds but reset
  whenever the identity flips against a Developer ID build.

Never commit a certificate private key, `.p12`, Apple Account password or any associated secret.
Release credentials belong in the login keychain locally and encrypted GitHub Actions secrets in CI.

## 1. Create the fallback local identity once (machines without the Developer ID certificate)

Run these commands to generate and import the self-signed development identity:

```sh
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout /tmp/spotter-key.pem -out /tmp/spotter-cert.pem \
  -subj "/CN=Spotter Self-Signed" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning"

openssl pkcs12 -export -inkey /tmp/spotter-key.pem -in /tmp/spotter-cert.pem \
  -name "Spotter Self-Signed" -out /tmp/spotter.p12 -passout pass:spotter

security import /tmp/spotter.p12 -k ~/Library/Keychains/login.keychain-db \
  -P spotter -A -T /usr/bin/codesign

rm -f /tmp/spotter-key.pem /tmp/spotter-cert.pem /tmp/spotter.p12
security find-identity -p codesigning | grep "Spotter Self-Signed"
```

This identity is never used for a public release.

## 2. Install the Release identity

The Release identity must be imported from a password-protected `.p12` containing both the
Developer ID certificate and its private key. Import it into the login keychain, then verify:

```sh
security find-identity -v -p codesigning \
  | grep "Developer ID Application" | grep "(Q9MD524YL5)"
```

Do not import a `.cer` alone: it has no private key and cannot sign builds. The certificate is a
personal credential; keep an encrypted backup under your own control and never commit it.

## 3. Release builds carry no restricted entitlements

A Release build signs with the Developer ID certificate alone: no App ID registration, no iCloud
container and no provisioning profile. `Spotter/Spotter.Release.entitlements` declares only
`allow-jit`, sandbox-off and the calendars entitlement, and Apple gates none of those behind a
profile. So `./build-dmg.sh` takes no profile argument, the CI workflow stores no profile secret, and
the signed app embeds no `embedded.provisionprofile`.

Notes' CloudKit pipeline is retired and its entitlements left the Release build with it (owner
decision, Nov 2026). The Apple Development CloudKit installer that exercised it went at the same
time, so nothing in the repository registers an App ID or an iCloud container any more, and no build
embeds a provisioning profile. Reconnecting the feature would mean registering all of that again and
restoring both the entitlements and the pipeline's profile verification. See AGENTS.md and
[`notes.md`](notes.md).

Switching between Developer ID, Apple Development and self-signed signatures may require re-granting
Accessibility and Input Monitoring, because macOS keys TCC grants to the signing identity.

## 4. Configure local notarization

Create a dedicated app-specific password named `Spotter Notarization` for an Apple Account that can
notarize software for team `Q9MD524YL5`. Store it in the login keychain under the profile name used
by `build-dmg.sh`:

```sh
xcrun notarytool store-credentials "spotter-notary" \
  --apple-id "<APPLE_ACCOUNT_EMAIL>" \
  --team-id "Q9MD524YL5"
```

Enter the app-specific password at the secure prompt. Do not pass it as a command-line argument,
because the shell may retain that argument in its history.

The local release command then performs the complete pipeline: Developer ID signing, Hardened
Runtime verification, app notarization and stapling, DMG signing, DMG notarization and final
Gatekeeper checks.

```sh
./build-dmg.sh
```

Set the release version in `project.yml`; the script deliberately rejects command-line version
overrides so the signed artifact, generated Xcode project and CI release cannot drift apart.

Set `NOTARY_KEYCHAIN_PROFILE` only when using a non-default profile name.

## 5. Configure GitHub Actions secrets

Export only the Developer ID identity from Keychain Access:

1. Open **Keychain Access → login → My Certificates**.
2. Expand the Developer ID certificate and confirm its private key is attached.
3. Export that one identity as a password-protected `.p12`.
4. Verify the exported file contains exactly one certificate with the expected Team ID.

```sh
openssl pkcs12 -in DeveloperID.p12 -passin stdin -nokeys -legacy \
  | openssl x509 -noout -subject
```

The subject must contain `UID=Q9MD524YL5`. Configure these repository secrets under
**Settings → Secrets and variables → Actions**:

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | Base64 of the selected `.p12` |
| `DEVELOPER_ID_P12_PASSWORD` | Password used when exporting the `.p12` |
| `APPLE_NOTARY_APPLE_ID` | Apple Account email used for notarization |
| `APPLE_NOTARY_PASSWORD` | Dedicated app-specific password |

Base64-encode the `.p12` without line wrapping before pasting it:

```sh
base64 -i DeveloperID.p12 | tr -d '\n' > DeveloperID.p12.base64
```

Delete the temporary base64 file after the secrets are saved. GitHub Actions imports the certificate
into an ephemeral keychain and fails before publishing if signing or notarization verification does
not pass. Changing or resetting the Apple Account's primary password revokes all app-specific
passwords, so `APPLE_NOTARY_PASSWORD` must then be replaced before the next release.

## 6. Verify a release manually

The build scripts run these checks automatically; they are also useful when inspecting a downloaded
release:

```sh
codesign --verify --deep --strict --verbose=2 "/Applications/Spotter.app"
codesign -dv --verbose=4 "/Applications/Spotter.app"
codesign -d --entitlements :- "/Applications/Spotter.app"
spctl --assess --type execute --verbose=2 "/Applications/Spotter.app"
xcrun stapler validate "/Applications/Spotter.app"
```

The detailed signature must show `TeamIdentifier=Q9MD524YL5` and the `runtime` flag. A Release build
embeds no provisioning profile, so `Contents/embedded.provisionprofile` must be absent and the
entitlements must not mention iCloud. Gatekeeper must report an accepted Developer ID origin, and
`stapler` must validate the attached ticket.

## Migrating installations older than 1.4.0

Spotter 1.4.0 is the first Developer ID release. Older self-signed copies cannot install it through
the in-app updater, which correctly rejects a bundle signed by a different identity. Those users
must install 1.4.0 or later from the DMG and may need to grant Accessibility and Input Monitoring
once more. After that one-time migration, releases with the same bundle identifier and Developer ID
designated requirement update normally.

Unlike the old self-signed release, a Developer ID-signed and notarized DMG passes Gatekeeper when
downloaded directly. Users must not be instructed to remove quarantine attributes.

## Migrating from the former Bundle ID

The former Developer ID releases used `com.spotter.app`, which Apple would not register as an
explicit App ID for CloudKit. The first `com.spotter.app1` release therefore requires a manual DMG
installation because the updater correctly rejects the changed designated requirement. On first
launch Spotter copies the former preferences, Application Support content and caches without deleting
them. It deliberately reruns onboarding so the user can grant Accessibility and Input Monitoring to
the new identity. Later `com.spotter.app1` releases update in place normally.

## Migrating from the former signing team

Releases through 1.7.36 were signed by `Developer ID Application: Round Technology (Shanghai)
Co.,Ltd (SM96W8VVK9)`. Signing moved to team `Q9MD524YL5`, which changes the designated requirement,
so the first release from the new team requires a manual DMG installation: `UpdateStore` correctly
refuses a bundle that no longer satisfies the running app's requirement. Announce it the way 1.4.0
and the `com.spotter.app1` rename were announced. The bundle identifier does not change, so
preferences, clipboard history and Notes are untouched; macOS keys TCC grants to the signing
identity, so Accessibility, Input Monitoring, Screen Recording and Full Disk Access must be granted
once more. Later releases from `Q9MD524YL5` update in place normally.

The same break applies to the local dev install, once. `scripts/install-dev.sh` compares the new
build against the installed bundle's designated requirement and refuses a mismatch, which is exactly
what it should do, and it has no override. For the one-time flip, quit Spotter, move
`/Applications/Spotter.app` aside — to the Trash, so it can be restored — and run the installer
against the new build; with no bundle at the destination it takes its first-install path. Moving the
old copy aside costs nothing here because the identity change resets those grants anyway. Do not
make this a habit: every later install must go through the atomic swap.
