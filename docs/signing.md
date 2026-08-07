# Signing

Spotter is signed with a **stable self-signed identity** called `Spotter Self-Signed`. It's not an
Apple Developer ID (there's no paid Apple account), but keeping the *same* identity on every build is
what makes macOS remember the Accessibility permission across rebuilds and updates — ad-hoc signing
changes every build and macOS forgets the grant.

You create this identity **once**. The same identity is used for:

- **local dev builds** — so Accessibility persists while you develop (the Xcode project signs with it), and
- **CI releases** — exported into two GitHub secrets the release workflow imports.

## 1. Create the `Spotter Self-Signed` identity (once)

Run these in a terminal. They generate a self-signed code-signing certificate and import it into your
login keychain:

```sh
# Generate a self-signed code-signing cert (10-year, codeSigning use).
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout /tmp/spotter-key.pem -out /tmp/spotter-cert.pem \
  -subj "/CN=Spotter Self-Signed" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning"

# Bundle it as a .p12 (the non-empty password keeps `security import` happy).
openssl pkcs12 -export -inkey /tmp/spotter-key.pem -in /tmp/spotter-cert.pem \
  -name "Spotter Self-Signed" -out /tmp/spotter.p12 -passout pass:spotter

# Import into the login keychain so codesign can use it without prompting.
security import /tmp/spotter.p12 -k ~/Library/Keychains/login.keychain-db \
  -P spotter -A -T /usr/bin/codesign

rm -f /tmp/spotter-key.pem /tmp/spotter-cert.pem /tmp/spotter.p12
```

Verify it's there:

```sh
security find-identity -p codesigning | grep "Spotter Self-Signed"
```

Now local builds (Xcode, VS Code F5, `xcodebuild`) sign with it, and you grant Accessibility once.

## 2. Generate the CI secrets

The release workflow needs the same identity as two repo secrets. Export it, base64-encode it, and
pick a password:

> ⚠️ **`security export -t identities` exports *every* identity in the keychain, not just
> Spotter's.** If your login keychain also holds an Apple Developer ID (or any other) certificate,
> the naive export bundles those private keys too — and uploading that to a repo secret leaks them.
> The recipe below extracts **only** `Spotter Self-Signed` and verifies it before you upload.

```sh
# Work in a private scratch directory.
D="$(mktemp -d)"; chmod 700 "$D"; cd "$D"

# Export everything the keychain has, then keep only the Spotter identity's cert + key.
EXPORT_PW="$(openssl rand -base64 24)"
security export -t identities -f pkcs12 \
  -k ~/Library/Keychains/login.keychain-db \
  -P "$EXPORT_PW" -o all.p12
openssl pkcs12 -in all.p12 -passin pass:"$EXPORT_PW" -nodes -legacy -out all.pem
awk '/friendlyName: Spotter Self-Signed/,/-----END/' all.pem > spotter.pem

# Repackage just that identity.
P12_PASSWORD="$(openssl rand -base64 24)"; echo "password: $P12_PASSWORD"
openssl pkcs12 -export -in spotter.pem -inkey spotter.pem \
  -name "Spotter Self-Signed" -out signing.p12 -passout pass:"$P12_PASSWORD" -legacy

# VERIFY before uploading: this must print exactly one certificate, CN=Spotter Self-Signed.
openssl pkcs12 -in signing.p12 -passin pass:"$P12_PASSWORD" -nokeys -legacy | grep subject=

base64 -i signing.p12 | tr -d '\n' > signing.p12.base64
```

Then set the two secrets on the repo (via `gh`, authed as the repo owner, or paste them in the GitHub
UI under **Settings → Secrets and variables → Actions**):

```sh
gh secret set SIGNING_P12_BASE64   --repo mmmmmmarcus/Spotter < signing.p12.base64
gh secret set SIGNING_P12_PASSWORD --repo mmmmmmarcus/Spotter --body "$P12_PASSWORD"

# Everything in this directory is private key material — remove the whole thing.
cd /; rm -rf "$D"
```

If you ever lose the secrets, just re-run this section — as long as the `Spotter Self-Signed`
identity is still in your keychain, the exported identity is the same, so users are unaffected. If you
lose the identity entirely, recreate it (step 1) and re-do this; existing users will re-grant
Accessibility once on their next update, then it's stable again — but note the in-app updater
verifies each downloaded bundle against the *running* app's designated requirement before
installing (`Core/UpdateStore.swift`), so a rotated identity also breaks in-app updates for every
already-installed copy: those users must download the new build manually once.

## Quarantine (separate from signing)

macOS quarantines anything downloaded from the internet, and Gatekeeper blocks even a correctly
self-signed app with an "unverified developer" warning. The Homebrew cask runs
`xattr -dr com.apple.quarantine` in `postflight`, so **brew users never touch it**. People who
download the DMG directly clear it once by hand.
