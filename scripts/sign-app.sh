#!/usr/bin/env bash
# Signs and validates a locally bundled Vhrase application.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="${1:-$ROOT/dist/Vhrase.app}"
ENTITLEMENTS="$ROOT/Vhrase.entitlements"
LOCAL_IDENTITY="${VHRASE_LOCAL_CODESIGN_IDENTITY:-Vhrase Local Development}"
SIGN_IDENTITY="${VHRASE_CODESIGN_IDENTITY:-}"

if [[ ! -d "$APP_DIR" ]]; then
  echo "App bundle not found: $APP_DIR" >&2
  exit 1
fi

if [[ ! -f "$ENTITLEMENTS" ]]; then
  echo "Entitlements file not found: $ENTITLEMENTS" >&2
  exit 1
fi

identity_exists() {
  local identity="$1"
  /usr/bin/security find-identity -v -p codesigning 2>/dev/null | /usr/bin/grep -F "\"$identity\"" >/dev/null
}

if [[ -z "$SIGN_IDENTITY" ]]; then
  if identity_exists "$LOCAL_IDENTITY"; then
    SIGN_IDENTITY="$LOCAL_IDENTITY"
  else
    SIGN_IDENTITY="-"
    echo "warn: signing Vhrase ad-hoc; run scripts/ensure-local-codesign-identity.sh once to keep macOS permissions stable across rebuilds." >&2
  fi
fi

/usr/bin/codesign \
  --force \
  --deep \
  --options runtime \
  --entitlements "$ENTITLEMENTS" \
  --sign "$SIGN_IDENTITY" \
  "$APP_DIR"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_DIR"

SIGNED_ENTITLEMENTS="$(/usr/bin/codesign -d --entitlements :- "$APP_DIR" 2>/dev/null)"
if [[ "$(/usr/bin/plutil -extract 'com\.apple\.security\.device\.audio-input' raw -o - - <<<"$SIGNED_ENTITLEMENTS")" != "true" ]]; then
  echo "Signed app is missing the microphone entitlement." >&2
  exit 1
fi
