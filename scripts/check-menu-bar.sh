#!/usr/bin/env bash
# Launches the bundled app and verifies that macOS creates a visible-width menu-bar item.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="${1:-$ROOT_DIR/dist/Vhrase.app}"
CHECK_DIR="$ROOT_DIR/.cache/menu-bar-check"
CHECK_BINARY="$CHECK_DIR/menu-bar-window-check"
SNAPSHOT="$CHECK_DIR/status-windows-before.json"
APP_PID=""

mkdir -p "$CHECK_DIR"

if pgrep -x Vhrase >/dev/null 2>&1; then
  echo "Quit the running Vhrase instance before checking the menu-bar item." >&2
  exit 1
fi

swiftc "$ROOT_DIR/scripts/checks/menu-bar-window-check.swift" -o "$CHECK_BINARY"
"$CHECK_BINARY" snapshot "$SNAPSHOT"

quit_app() {
  if [[ -n "$APP_PID" ]]; then
    kill "$APP_PID" >/dev/null 2>&1 || true
  fi
}
trap quit_app EXIT

/usr/bin/open -n "$APP_DIR"
for _ in {1..20}; do
  APP_PID="$(pgrep -x Vhrase | head -n 1 || true)"
  if [[ -n "$APP_PID" ]]; then
    break
  fi
  sleep 0.1
done

if [[ -z "$APP_PID" ]]; then
  echo "Vhrase did not start." >&2
  exit 1
fi

for _ in {1..20}; do
  if "$CHECK_BINARY" assert-visible "$SNAPSHOT" >/dev/null 2>&1; then
    echo "menu bar item visible"
    exit 0
  fi
  sleep 0.1
done

"$CHECK_BINARY" assert-visible "$SNAPSHOT"
