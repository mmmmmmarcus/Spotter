#!/bin/bash
set -euo pipefail

IDENTITY="Spotter Self-Signed"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
SIGNING_KEYCHAIN="$HOME/Library/Keychains/spotter-signing.keychain-db"
BACKUP_DIR="$HOME/Documents/Spotter Signing Backup"
BACKUP_PATH="$BACKUP_DIR/Spotter Self-Signed.p12"
PASSWORD_SERVICE="Spotter Signing Backup Password"

TEMP_DIR="$(mktemp -d)"
cleanup() {
    rm -f "$TEMP_DIR/spotter-key.pem" "$TEMP_DIR/spotter-cert.pem" "$TEMP_DIR/spotter.p12"
    rmdir "$TEMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT
umask 077

if [ -f "$BACKUP_PATH" ] \
    && security find-generic-password -s "$PASSWORD_SERVICE" \
        "$HOME/Library/Keychains/login.keychain-db" >/dev/null 2>&1
then
    PASSWORD="$(
        security find-generic-password -s "$PASSWORD_SERVICE" -w \
            "$HOME/Library/Keychains/login.keychain-db"
    )"
else
    PASSWORD="$(openssl rand -base64 36 | tr -d '\n')"
    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
        -keyout "$TEMP_DIR/spotter-key.pem" -out "$TEMP_DIR/spotter-cert.pem" \
        -subj "/CN=$IDENTITY" \
        -addext "basicConstraints=critical,CA:false" \
        -addext "keyUsage=critical,digitalSignature" \
        -addext "extendedKeyUsage=critical,codeSigning"
    openssl pkcs12 -legacy -export \
        -inkey "$TEMP_DIR/spotter-key.pem" -in "$TEMP_DIR/spotter-cert.pem" \
        -name "$IDENTITY" -out "$TEMP_DIR/spotter.p12" -passout "pass:$PASSWORD"
    security import "$TEMP_DIR/spotter.p12" -k "$KEYCHAIN" \
        -P "$PASSWORD" -A -T /usr/bin/codesign
    security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" \
        "$TEMP_DIR/spotter-cert.pem"

    mkdir -p "$BACKUP_DIR"
    cp "$TEMP_DIR/spotter.p12" "$BACKUP_PATH"
    chmod 600 "$BACKUP_PATH"
    security add-generic-password -a "$USER" -s "$PASSWORD_SERVICE" -w "$PASSWORD" -U
fi

if [ ! -f "$SIGNING_KEYCHAIN" ]; then
    security create-keychain -p "$PASSWORD" "$SIGNING_KEYCHAIN"
fi
security set-keychain-settings -lut 21600 "$SIGNING_KEYCHAIN"
security unlock-keychain -p "$PASSWORD" "$SIGNING_KEYCHAIN"
if ! security find-certificate -c "$IDENTITY" "$SIGNING_KEYCHAIN" >/dev/null 2>&1; then
    security import "$BACKUP_PATH" -k "$SIGNING_KEYCHAIN" \
        -P "$PASSWORD" -A -T /usr/bin/codesign
fi
security set-key-partition-list -S "apple-tool:,apple:" -s -t private \
    -l "$IDENTITY" -k "$PASSWORD" "$SIGNING_KEYCHAIN" >/dev/null

EXISTING_KEYCHAINS=()
while IFS= read -r item; do
    item="$(printf "%s" "$item" | sed -E 's/^[[:space:]]*"//; s/"[[:space:]]*$//')"
    if [ -f "$item" ] && [ "$item" != "$SIGNING_KEYCHAIN" ]; then
        EXISTING_KEYCHAINS+=("$item")
    fi
done < <(security list-keychains -d user)
security list-keychains -d user -s "$SIGNING_KEYCHAIN" "${EXISTING_KEYCHAINS[@]}"

echo "✓ Created '$IDENTITY'."
echo "  Encrypted backup: $BACKUP_PATH"
echo "  Dedicated keychain: $SIGNING_KEYCHAIN"
echo "  Its password is stored in Keychain as '$PASSWORD_SERVICE'."
