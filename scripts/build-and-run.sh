#!/usr/bin/env bash
# Builds, bundles, and launches one signed Vhrase menu-bar app instance.

set -euo pipefail

MODE="${1:-run}"
APP_NAME="Vhrase"
BUNDLE_ID="local.codex.Vhrase"
DEVELOPMENT_ENVIRONMENT_ARGUMENT="--development-environment-file"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
ENV_FILE="$ROOT_DIR/.env"

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
  /usr/bin/open -n "$APP_BUNDLE" --args "$DEVELOPMENT_ENVIRONMENT_ARGUMENT" "$ENV_FILE"
}

stop_running_app
build_app

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY" "$DEVELOPMENT_ENVIRONMENT_ARGUMENT" "$ENV_FILE"
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
      if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
        exit 0
      fi
      sleep 0.1
    done
    echo "$APP_NAME did not start." >&2
    exit 1
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
