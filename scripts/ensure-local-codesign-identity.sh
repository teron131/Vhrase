#!/usr/bin/env bash
# Ensures a reusable local code-signing identity exists for Vhrase development builds.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IDENTITY="${VHRASE_LOCAL_CODESIGN_IDENTITY:-Vhrase Local Development}"
KEYCHAIN="${VHRASE_CODESIGN_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
WORK_DIR="$ROOT/.cache/codesign"

identity_exists() {
  /usr/bin/security find-identity -v -p codesigning 2>/dev/null | /usr/bin/grep -F "\"$IDENTITY\"" >/dev/null
}

if identity_exists; then
  echo "Codesigning identity already exists: $IDENTITY"
  exit 0
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "openssl is required to create the local Vhrase codesigning identity." >&2
  exit 1
fi

mkdir -p "$WORK_DIR"
chmod 700 "$WORK_DIR"

CONFIG="$WORK_DIR/local-codesign.cnf"
KEY="$WORK_DIR/local-codesign.key"
CERT="$WORK_DIR/local-codesign.crt"
P12="$WORK_DIR/local-codesign.p12"
P12_PASSWORD="$(openssl rand -hex 32)"

cleanup() {
  rm -f "$CONFIG" "$KEY" "$CERT" "$P12"
}
trap cleanup EXIT

cat > "$CONFIG" <<CONFIG
[req]
distinguished_name = dn
x509_extensions = codesign
prompt = no

[dn]
CN = $IDENTITY

[codesign]
basicConstraints = critical, CA:true
keyUsage = critical, digitalSignature, keyCertSign
extendedKeyUsage = codeSigning
CONFIG

openssl req \
  -newkey rsa:2048 \
  -nodes \
  -x509 \
  -days 3650 \
  -keyout "$KEY" \
  -out "$CERT" \
  -config "$CONFIG" >/dev/null 2>&1

openssl pkcs12 \
  -export \
  -legacy \
  -inkey "$KEY" \
  -in "$CERT" \
  -name "$IDENTITY" \
  -out "$P12" \
  -passout "pass:$P12_PASSWORD" >/dev/null 2>&1

/usr/bin/security import "$P12" \
  -k "$KEYCHAIN" \
  -P "$P12_PASSWORD" \
  -T /usr/bin/codesign \
  -T /usr/bin/security >/dev/null
unset P12_PASSWORD

/usr/bin/security add-trusted-cert \
  -r trustRoot \
  -p codeSign \
  -k "$KEYCHAIN" \
  "$CERT" >/dev/null

if ! identity_exists; then
  echo "Created '$IDENTITY', but macOS does not list it as a valid codesigning identity yet. Open Keychain Access and trust it for Code Signing, then rerun this script." >&2
  exit 1
fi

echo "Created local Vhrase codesigning identity: $IDENTITY"
