# Signing and notarization

Spotter uses two signing identities for two different purposes:

- Ordinary Debug builds are local `-dev` versions signed with the stable self-signed
  `Spotter Self-Signed` identity. This keeps Accessibility and Input Monitoring grants stable across
  rebuilds. The opt-in CloudKit dev installer uses Apple Development signing instead.
- Release builds use `Developer ID Application: Round Technology (Shanghai) Co.,Ltd (SM96W8VVK9)`,
  enable Hardened Runtime, include a secure timestamp and are notarized by Apple.

Never commit a certificate private key, `.p12`, Apple Account password or any associated secret.
Release credentials belong in the login keychain locally and encrypted GitHub Actions secrets in CI.

## 1. Create the local Debug identity once

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
  | grep "Developer ID Application: Round Technology (Shanghai) Co.,Ltd (SM96W8VVK9)"
```

Do not import a `.cer` alone: it has no private key and cannot sign builds. The certificate is a
company credential; transfer it only through an approved secure channel and keep an encrypted
backup under the certificate owner's control.

## 3. Configure CloudKit and Developer ID profiles

Notes sync uses the production private database in `iCloud.com.spotter.app`. In Certificates,
Identifiers & Profiles:

1. Create that iCloud container and enable CloudKit.
2. Enable iCloud/CloudKit and Push Notifications for both `com.spotter.app1` and
   `com.spotter.app1.beta`, associating both App IDs with the shared container.
3. Create one Developer ID provisioning profile for each App ID with those capabilities, then
   download both profiles. A certificate alone cannot authorize these restricted entitlements.
4. Exercise the development environment with an Apple Development-signed scratch build, then deploy
   the `SpotterNote` record schema to Production in CloudKit Console before publishing. The record
   uses encrypted `content`, `createdAt`, `updatedAt` and `deletedAt` fields in the `SpotterNotes`
   custom zone.

For a local stable release, pass the downloaded stable profile to the release script:

```sh
SPOTTER_DEVELOPER_ID_PROFILE=/secure/path/Spotter.provisionprofile ./build-dmg.sh
```

The script verifies the team, stable App ID and shared container before temporarily installing the
profile for `xcodebuild`; it then verifies that the finished app embeds both the profile and CloudKit
entitlement. The self-signed Debug configuration intentionally continues using
`Spotter/Spotter.entitlements` without CloudKit so its stable local TCC identity is unchanged.

An installed development-environment build uses the checked-in
`Spotter/Spotter.Development.entitlements` through:

```sh
scripts/install-cloud-dev.sh
```

The installer selects a matching development profile from Xcode's provisioning-profile directory,
builds with the current team's Apple Development identity, verifies the Development CloudKit and push
entitlements, then replaces only `/Applications/Spotter.app`. Development and Production CloudKit
engine state files are separate. Switching between Apple Development, self-signed Debug and Developer
ID signatures may require re-granting Accessibility and Input Monitoring.

## 4. Configure local notarization

Create a dedicated app-specific password named `Spotter Notarization` for an Apple Account that can
notarize software for team `SM96W8VVK9`. Store it in the login keychain under the profile name used
by `build-dmg.sh`:

```sh
xcrun notarytool store-credentials "spotter-notary" \
  --apple-id "<APPLE_ACCOUNT_EMAIL>" \
  --team-id "SM96W8VVK9"
```

Enter the app-specific password at the secure prompt. Do not pass it as a command-line argument,
because the shell may retain that argument in its history.

The local release command then performs the complete pipeline: Developer ID signing, Hardened
Runtime verification, app notarization and stapling, DMG signing, DMG notarization and final
Gatekeeper checks.

```sh
SPOTTER_DEVELOPER_ID_PROFILE=/secure/path/Spotter.provisionprofile ./build-dmg.sh
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

The subject must contain `UID=SM96W8VVK9`. Configure these repository secrets under
**Settings → Secrets and variables → Actions**:

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | Base64 of the selected `.p12` |
| `DEVELOPER_ID_P12_PASSWORD` | Password used when exporting the `.p12` |
| `DEVELOPER_ID_PROFILE_BASE64_STABLE` | Base64 of the Developer ID profile for `com.spotter.app1` |
| `DEVELOPER_ID_PROFILE_BASE64_BETA` | Base64 of the Developer ID profile for `com.spotter.app1.beta` |
| `APPLE_NOTARY_APPLE_ID` | Apple Account email used for notarization |
| `APPLE_NOTARY_PASSWORD` | Dedicated app-specific password |

Base64-encode the `.p12` and both provisioning profiles without line wrapping before pasting them:

```sh
base64 -i DeveloperID.p12 | tr -d '\n' > DeveloperID.p12.base64
base64 -i Spotter.provisionprofile | tr -d '\n' > Spotter.provisionprofile.base64
base64 -i SpotterBeta.provisionprofile | tr -d '\n' > SpotterBeta.provisionprofile.base64
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

The detailed signature must show `TeamIdentifier=SM96W8VVK9` and the `runtime` flag; entitlements must
contain `iCloud.com.spotter.app`, and `Contents/embedded.provisionprofile` must exist. Gatekeeper must
report an accepted Developer ID origin, and `stapler` must validate the attached ticket.

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
