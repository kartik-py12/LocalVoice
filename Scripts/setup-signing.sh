#!/bin/bash
set -euo pipefail
umask 077

SIGNING_IDENTITY="LocalVoice Local Signer"
LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
INSTALLED_APP="$HOME/Applications/LocalVoice.app"
TASK_TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/localvoice-signing.XXXXXX")"
TASK_CERT_HASH=""
TASK_COMPLETE=0

cleanup() {
    if [[ "$TASK_COMPLETE" != 1 && -n "$TASK_CERT_HASH" ]]; then
        security delete-identity -Z "$TASK_CERT_HASH" "$LOGIN_KEYCHAIN" >/dev/null 2>&1 || true
        security delete-certificate -Z "$TASK_CERT_HASH" -t "$LOGIN_KEYCHAIN" >/dev/null 2>&1 || true
        security remove-trusted-cert "$TASK_TEMP_DIR/LocalVoice.cer" >/dev/null 2>&1 || true
    fi
    rm -rf "$TASK_TEMP_DIR"
}
trap cleanup EXIT

if security find-identity -p codesigning "$LOGIN_KEYCHAIN" | grep -Fq "\"$SIGNING_IDENTITY\""; then
    echo "LocalVoice signing identity is already installed."
    TASK_COMPLETE=1
    exit 0
fi

openssl req -x509 -newkey rsa:3072 -sha256 -nodes \
    -keyout "$TASK_TEMP_DIR/LocalVoice.key" \
    -out "$TASK_TEMP_DIR/LocalVoice.cer" \
    -days 3650 \
    -subj "/CN=$SIGNING_IDENTITY/" \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,digitalSignature,keyCertSign" \
    -addext "extendedKeyUsage=critical,codeSigning"
cat "$TASK_TEMP_DIR/LocalVoice.cer" "$TASK_TEMP_DIR/LocalVoice.key" > "$TASK_TEMP_DIR/LocalVoice.pem"

TASK_CERT_HASH="$(openssl x509 -in "$TASK_TEMP_DIR/LocalVoice.cer" -noout -fingerprint -sha1 | sed 's/.*=//; s/://g')"
security import "$TASK_TEMP_DIR/LocalVoice.pem" -t agg -f pemseq -x -T /usr/bin/codesign -k "$LOGIN_KEYCHAIN"
security add-trusted-cert -r trustRoot -p codeSign -a "$INSTALLED_APP" -k "$LOGIN_KEYCHAIN" "$TASK_TEMP_DIR/LocalVoice.cer"

if ! security find-identity -p codesigning "$LOGIN_KEYCHAIN" | grep -Fq "\"$SIGNING_IDENTITY\""; then
    echo "The LocalVoice signing identity could not be validated." >&2
    exit 1
fi

TASK_COMPLETE=1
echo "Installed app-scoped LocalVoice signing identity in the login keychain."
