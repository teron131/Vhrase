#!/usr/bin/env bash
# Assembles the built Vhrase executable and resources into a macOS application bundle.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_CONFIG="${1:-debug}"
APP_DIR="$ROOT/dist/Vhrase.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
BINARY="$ROOT/.build/$BUILD_CONFIG/Vhrase"
ICON_SOURCE="$ROOT/Resources/VhraseAppIcon.png"
ICONSET="$ROOT/.cache/Vhrase.iconset"
APP_ICON="$RESOURCES/Vhrase.icns"

export CLANG_MODULE_CACHE_PATH="$ROOT/.build/ModuleCache"

render_app_icon() {
  mkdir -p "$ICONSET"
  while read -r size filename; do
    sips -z "$size" "$size" "$ICON_SOURCE" --out "$ICONSET/$filename" >/dev/null
  done <<'SIZES'
16 icon_16x16.png
32 icon_16x16@2x.png
32 icon_32x32.png
64 icon_32x32@2x.png
128 icon_128x128.png
256 icon_128x128@2x.png
256 icon_256x256.png
512 icon_256x256@2x.png
512 icon_512x512.png
1024 icon_512x512@2x.png
SIZES
  iconutil -c icns "$ICONSET" -o "$APP_ICON"
}

if [[ "$BUILD_CONFIG" == "debug" ]]; then
  swift build
else
  swift build -c "$BUILD_CONFIG"
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"
cp "$BINARY" "$MACOS/Vhrase"
cp -R "$ROOT/.build/$BUILD_CONFIG/Vhrase_VhraseApp.bundle" "$RESOURCES/"
cp "$ROOT/.build/checkouts/CSpeex/LICENSE.txt" "$RESOURCES/Speex-LICENSE.txt"
render_app_icon

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>Vhrase</string>
  <key>CFBundleIconFile</key>
  <string>Vhrase.icns</string>
  <key>CFBundleIdentifier</key>
  <string>local.codex.Vhrase</string>
  <key>CFBundleName</key>
  <string>Vhrase</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.11.6</string>
  <key>CFBundleVersion</key>
  <string>26</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>Vhrase records your speech so it can transcribe and insert text.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSScreenCaptureUsageDescription</key>
  <string>Vhrase can include a screenshot as context when adjusting transcript text.</string>
</dict>
</plist>
PLIST

bash "$ROOT/scripts/sign-app.sh" "$APP_DIR"

echo "$APP_DIR"
