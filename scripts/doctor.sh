#!/usr/bin/env bash
# Reports whether the local Vhrase bundle, tools, permissions, and Keychain credentials are ready.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/dist/Vhrase.app"
APP_EXEC="$APP_DIR/Contents/MacOS/Vhrase"
APP_ICON="$APP_DIR/Contents/Resources/Vhrase.icns"
PLIST="$APP_DIR/Contents/Info.plist"

usage() {
  cat <<'USAGE'
Usage: bash scripts/doctor.sh [--strict]

Checks local Vhrase readiness without recording audio, calling providers,
opening settings, or prompting for permissions.

Options:
  --strict  Exit non-zero when any required check is missing.
USAGE
}

STRICT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --strict)
      STRICT=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

FAILURES=0

check() {
  local status="$1"
  local label="$2"
  local detail="${3:-}"
  if [[ "$status" == "ok" ]]; then
    printf "ok   %s" "$label"
  elif [[ "$status" == "warn" ]]; then
    printf "warn %s" "$label"
  else
    printf "miss %s" "$label"
    FAILURES=$((FAILURES + 1))
  fi
  if [[ -n "$detail" ]]; then
    printf " - %s" "$detail"
  fi
  printf "\n"
}

# Prints where a credential is found, Keychain before the environment, without reading its value; prints nothing when neither has it.
key_value() {
  local name="$1"
  if /usr/bin/security find-generic-password -s Vhrase -a "$name" >/dev/null 2>&1; then
    echo "macOS Keychain"
    return
  fi

  if [[ -n "${!name:-}" ]]; then
    echo "environment fallback"
  fi
}

# Prints Vhrase's TCC auth_value for a service, 2 meaning allowed; prints nothing when this shell cannot read TCC.db or Vhrase has no entry.
permission_status() {
  local service="$1"
  sqlite3 "$HOME/Library/Application Support/com.apple.TCC/TCC.db" \
    "select auth_value from access where service='$service' and client='local.codex.Vhrase' limit 1;" \
    2>/dev/null || true
}

echo "Vhrase doctor"
echo "Root: $ROOT"
echo

if [[ -d "$APP_DIR" ]]; then
  check ok "app bundle" "$APP_DIR"
else
  check missing "app bundle" "run bash scripts/bundle-app.sh"
fi

if [[ -x "$APP_EXEC" ]]; then
  check ok "app executable"
else
  check missing "app executable" "$APP_EXEC"
fi

if [[ -f "$PLIST" ]] && plutil -lint "$PLIST" >/dev/null 2>&1; then
  check ok "Info.plist"
else
  check missing "Info.plist"
fi

if [[ -s "$APP_ICON" ]]; then
  check ok "app icon"
else
  check missing "app icon" "$APP_ICON"
fi

if [[ -d "$APP_DIR" ]] && codesign --verify --deep --strict "$APP_DIR" >/dev/null 2>&1; then
  SIGNATURE_DETAIL="$(codesign -dv --verbose=4 "$APP_DIR" 2>&1 || true)"
  if [[ "$SIGNATURE_DETAIL" == *"Signature=adhoc"* ]]; then
    check warn "code signature" "ad-hoc; run scripts/ensure-local-codesign-identity.sh once to keep permissions stable"
  else
    check ok "code signature"
  fi
elif [[ -d "$APP_DIR" ]]; then
  check missing "code signature" "run bash scripts/verify.sh"
else
  check warn "code signature" "bundle missing"
fi

if command -v swift >/dev/null 2>&1; then
  SWIFT_VERSION="$(swift --version 2>&1 | head -n 1)"
  check ok "Swift toolchain" "$SWIFT_VERSION"
else
  check missing "Swift toolchain"
fi

if command -v say >/dev/null 2>&1 && command -v afconvert >/dev/null 2>&1; then
  check ok "generated-audio tools" "say and afconvert"
else
  check missing "generated-audio tools" "say and afconvert are required for generated smoke audio"
fi

if command -v uv >/dev/null 2>&1; then
  check ok "realtime smoke runner" "uv"
else
  check missing "realtime smoke runner" "uv is required for realtime WebSocket smoke tests"
fi

if command -v ffmpeg >/dev/null 2>&1; then
  check ok "microphone smoke recorder" "ffmpeg"
else
  check warn "microphone smoke recorder" "install ffmpeg to run scripts/live-mic-stt-smoke.sh"
fi

if command -v opencc >/dev/null 2>&1 || [[ -x /opt/homebrew/bin/opencc || -x /usr/local/bin/opencc || -x /usr/bin/opencc ]]; then
  check ok "OpenCC s2t" "final transcript conversion available"
else
  check warn "OpenCC s2t" "install opencc for final transcript s2t conversion"
fi

XAI_SOURCE="$(key_value XAI_API_KEY)"
if [[ -n "$XAI_SOURCE" ]]; then
  check ok "xAI key" "$XAI_SOURCE"
else
  check warn "xAI key" "add XAI_API_KEY in System or environment"
fi

ELEVEN_SOURCE="$(key_value ELEVENLABS_API_KEY)"
if [[ -n "$ELEVEN_SOURCE" ]]; then
  check ok "ElevenLabs key" "$ELEVEN_SOURCE"
else
  check warn "ElevenLabs key" "add ELEVENLABS_API_KEY in System or environment"
fi

GEMINI_SOURCE="$(key_value GEMINI_API_KEY)"
if [[ -n "$GEMINI_SOURCE" ]]; then
  check ok "Gemini key" "$GEMINI_SOURCE"
else
  check warn "Gemini key" "add GEMINI_API_KEY in System or environment"
fi

OPENAI_SOURCE="$(key_value OPENAI_API_KEY)"
if [[ -n "$OPENAI_SOURCE" ]]; then
  check ok "OpenAI key" "$OPENAI_SOURCE"
else
  check warn "OpenAI key" "add OPENAI_API_KEY in System or environment"
fi

GATEWAY_SOURCE="$(key_value AI_GATEWAY_API_KEY)"
if [[ -n "$GATEWAY_SOURCE" ]]; then
  check ok "Vercel AI Gateway key" "$GATEWAY_SOURCE"
else
  check warn "Vercel AI Gateway key" "add AI_GATEWAY_API_KEY in System or environment"
fi

if [[ -f "$HOME/Library/Application Support/Vhrase/Models/parakeet-tdt-0.6b-v3/.vhrase-complete" ]]; then
  check ok "Parakeet model" "downloaded for on-device transcription"
else
  check warn "Parakeet model" "download it in Transcription or System to transcribe on this Mac"
fi

# Each downloaded Hugging Face model folder carries the same completion marker.
if compgen -G "$HOME/Library/Application Support/Vhrase/Models/huggingface/hub/models--*/.vhrase-complete" >/dev/null; then
  check ok "Hugging Face model" "downloaded for on-device transcription"
else
  check warn "Hugging Face model" "download it in Transcription or System to transcribe on this Mac"
fi

# Hugging Face models run in a Python environment that uv builds; the app looks in these same places.
if [[ -x /opt/homebrew/bin/uv || -x /usr/local/bin/uv || -x "$HOME/.local/bin/uv" || -x "$HOME/.cargo/bin/uv" ]]; then
  check ok "uv" "available to build the Hugging Face runtime"
else
  check warn "uv" "install uv (brew install uv) to run Hugging Face models"
fi

MIC_STATUS="$(permission_status kTCCServiceMicrophone)"
case "$MIC_STATUS" in
  2)
    check ok "microphone permission" "granted"
    ;;
  0|1|3|4)
    check warn "microphone permission" "not granted in TCC yet"
    ;;
  *)
    check warn "microphone permission" "unknown until the app requests it"
    ;;
esac

INPUT_STATUS="$(permission_status kTCCServiceListenEvent)"
ACCESSIBILITY_STATUS="$(permission_status kTCCServiceAccessibility)"
if [[ "$ACCESSIBILITY_STATUS" == "2" ]]; then
  check ok "text insertion access" "granted by Accessibility"
elif [[ "$ACCESSIBILITY_STATUS" =~ ^[0134]$ ]]; then
  check warn "text insertion access" "grant Accessibility so transcripts return to the originating app"
else
  check warn "text insertion access" "unknown to the shell; confirm Accessibility in Vhrase"
fi

if [[ "$INPUT_STATUS" == "2" || "$ACCESSIBILITY_STATUS" == "2" ]]; then
  check ok "Fn/Globe event access" "granted by Accessibility or Input Monitoring"
elif [[ "$INPUT_STATUS" =~ ^[0134]$ || "$ACCESSIBILITY_STATUS" =~ ^[0134]$ ]]; then
  check warn "Fn/Globe event access" "grant Accessibility, or Input Monitoring if the shortcut still does not respond"
else
  check warn "Fn/Globe event access" "unknown to the shell; confirm Accessibility or Input Monitoring in Vhrase"
fi

SCREEN_STATUS="$(permission_status kTCCServiceScreenCapture)"
case "$SCREEN_STATUS" in
  2)
    check ok "screen recording permission" "granted"
    ;;
  0|1|3|4)
    check warn "screen recording permission" "not granted in TCC yet"
    ;;
  *)
    check warn "screen recording permission" "unknown until screenshot context is used"
    ;;
esac

echo
if [[ "$FAILURES" -eq 0 ]]; then
  echo "Required local checks passed."
  exit 0
fi

echo "$FAILURES required check(s) missing."
if [[ "$STRICT" -eq 1 ]]; then
  exit 1
fi
