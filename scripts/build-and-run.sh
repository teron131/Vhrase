#!/usr/bin/env bash
# Builds, bundles, and launches one signed Vhrase menu-bar app instance.

set -euo pipefail

MODE="${1:-run}"
APP_NAME="Vhrase"
BUNDLE_ID="local.codex.Vhrase"
IMPORT_CREDENTIALS_ARGUMENT="--import-environment-credentials"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

stop_running_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  for _ in {1..20}; do
    if ! pgrep -x "$APP_NAME" >/dev/null 2>&1; then
      return
    fi
    sleep 0.1
  done
  echo "Unable to stop the existing $APP_NAME process." >&2
  exit 1
}

build_app() {
  bash "$ROOT_DIR/scripts/bundle-app.sh"
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE" --args "$IMPORT_CREDENTIALS_ARGUMENT"
}

# Confirms every nonempty supported launch override has a Keychain item without reading secret values.
credential_sync_complete() {
  local key_name
  for key_name in XAI_API_KEY ELEVENLABS_API_KEY AI_GATEWAY_API_KEY; do
    if [[ -z "${!key_name:-}" ]]; then
      continue
    fi
    security find-generic-password -s Vhrase -a "$key_name" >/dev/null 2>&1 || return 1
  done
}

stop_running_app
build_app

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY" "$IMPORT_CREDENTIALS_ARGUMENT"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    for _ in {1..20}; do
      if pgrep -x "$APP_NAME" >/dev/null 2>&1 && credential_sync_complete; then
        exit 0
      fi
      sleep 0.1
    done
    echo "$APP_NAME did not start or synchronize its launch credentials." >&2
    exit 1
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
