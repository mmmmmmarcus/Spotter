# Signing

Spotter uses one long-lived self-signed code-signing identity named `Spotter Self-Signed`. It is not
an Apple Developer ID, but the certificate, bundle identifier and installed path remain constant.
That lets macOS treat Debug and Release rebuilds as updates of the same app instead of unrelated
ad-hoc binaries.

The identity is used for:

- local Debug and Release builds installed at `/Applications/Spotter.app`; and
- CI releases, exported into two GitHub secrets.

Losing or replacing the identity changes Spotter's designated requirement and requires the user to
grant protected permissions again. Back it up before relying on it.

## 1. Create and back up the identity once

From the repository root:

```sh
./Tools/setup-signing.sh
```

The script creates a ten-year code-signing certificate, records its trust in the login keychain, and
imports the same identity into `~/Library/Keychains/spotter-signing.keychain-db`. The dedicated
keychain grants signing access only to Apple's signing-tool partitions and can be unlocked
automatically by the local build wrapper. macOS may ask for the login password once while recording
trust for the certificate. The script also writes an encrypted backup:

```text
~/Documents/Spotter Signing Backup/Spotter Self-Signed.p12
```

The generated backup password is stored in the login keychain under
`Spotter Signing Backup Password`; retrieve it when moving the backup to a separate secure location:

```sh
security find-generic-password -s "Spotter Signing Backup Password" -w
```

Keep the `.p12` and its password in separate secure backups. Never add either to this repository.

Verify the identity:

```sh
security find-identity -v -p codesigning | grep "Spotter Self-Signed"
```

## 2. Configure CI with the same identity

Use the encrypted backup created above rather than generating a new certificate:

```sh
P12="$HOME/Documents/Spotter Signing Backup/Spotter Self-Signed.p12"
P12_PASSWORD="$(security find-generic-password -s "Spotter Signing Backup Password" -w)"
base64 -i "$P12" | tr -d '\n' > "${TMPDIR:-/tmp}/spotter-signing.p12.base64"

gh secret set SIGNING_P12_BASE64 \
  --repo mmmmmmarcus/Spotter < "${TMPDIR:-/tmp}/spotter-signing.p12.base64"
gh secret set SIGNING_P12_PASSWORD \
  --repo mmmmmmarcus/Spotter --body "$P12_PASSWORD"
```

Delete the temporary base64 file after the secrets are set. The release workflow imports this exact
certificate and builds both beta and stable labels as `Spotter.app` / `com.spotter.app`, so either
one updates the same installed app and protected-permission identity.

## Local permission lifecycle

Run Spotter through `Tools/run-local.sh` or VS Code F5. Both replace and launch only
`/Applications/Spotter.app`. The first transition from the former `Spotter Dev.app` uses a new bundle
identifier and signature, so Accessibility must be granted once. Later Debug and Release updates keep
the same path, identifier and certificate, so macOS can retain the grant.

An ad-hoc build (`CODE_SIGN_IDENTITY=-`), a recreated certificate, or launching a DerivedData product
breaks that identity. The runtime rejects non-installed launches as a second line of defense.

## Quarantine

Quarantine is separate from signing. A self-signed app downloaded from the internet may still be
blocked by Gatekeeper until its quarantine attribute is cleared:

```sh
xattr -dr com.apple.quarantine "/Applications/Spotter.app"
```
