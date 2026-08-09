# Signing and notarization

Spotter uses two signing identities for two different purposes:

- Debug builds use the stable self-signed `Spotter Self-Signed` identity. This lets every contributor
  build locally while keeping Accessibility and Input Monitoring grants stable across rebuilds.
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

## 3. Configure local notarization

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
./build-dmg.sh
```

Set the release version in `project.yml`; the script deliberately rejects command-line version
overrides so the signed artifact, generated Xcode project and CI release cannot drift apart.

Set `NOTARY_KEYCHAIN_PROFILE` only when using a non-default profile name.

## 4. Configure GitHub Actions secrets

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

## 5. Verify a release manually

The build scripts run these checks automatically; they are also useful when inspecting a downloaded
release:

```sh
codesign --verify --deep --strict --verbose=2 "/Applications/Spotter.app"
codesign -dv --verbose=4 "/Applications/Spotter.app"
spctl --assess --type execute --verbose=2 "/Applications/Spotter.app"
xcrun stapler validate "/Applications/Spotter.app"
```

The detailed signature must show `TeamIdentifier=SM96W8VVK9` and the `runtime` flag. Gatekeeper must
report an accepted Developer ID origin, and `stapler` must validate the attached ticket.

## Migrating installations older than 1.4.0

Spotter 1.4.0 is the first Developer ID release. Older self-signed copies cannot install it through
the in-app updater, which correctly rejects a bundle signed by a different identity. Those users
must install 1.4.0 or later from the DMG and may need to grant Accessibility and Input Monitoring
once more. After that one-time migration, releases with the same bundle identifier and Developer ID
designated requirement update normally.

Unlike the old self-signed release, a Developer ID-signed and notarized DMG passes Gatekeeper when
downloaded directly. Users must not be instructed to remove quarantine attributes.
