#!/usr/bin/env bash
# Runs upload or realtime STT against generated or supplied audio without exposing credentials.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE_DIR="$ROOT/.cache/live-stt-smoke"
SMOKE_BIN=""
PHRASE="Custom dictation live smoke test for OpenAI, xAI, and ElevenLabs."
PROVIDER=""
MODE="upload"
AUDIO_FILE=""
EXTRA_ARGS=()

export CLANG_MODULE_CACHE_PATH="$ROOT/.build/ModuleCache"

usage() {
  cat <<'USAGE'
Usage: bash scripts/live-stt-smoke.sh --provider xai|elevenlabs [options]

Options:
  --mode upload|realtime           Defaults to upload.
  --audio path.wav                 Use an existing audio file instead of generated speech.
  --phrase "text"                  Text to synthesize with macOS say when --audio is omitted.
  --language en                    Language code passed to the provider.
  --keyterm "OpenAI"               Repeatable provider keyterm.
  --expect "custom dictation"      Case-insensitive transcript expectation.
  --elevenlabs-commit-strategy x   manual or vad.
  --elevenlabs-no-verbatim         ElevenLabs no-verbatim cleanup.
  --elevenlabs-vad-silence-threshold n
  --elevenlabs-vad-threshold n
  --elevenlabs-min-speech-duration n
  --elevenlabs-min-silence-duration n
  --verbose                        Print realtime WebSocket diagnostics.

Credentials use a nonempty XAI_API_KEY / ELEVENLABS_API_KEY override, then the saved Vhrase Keychain item.
ElevenLabs uses fixed scribe_v2 upload and scribe_v2_realtime models, matching Vhrase.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --provider)
      PROVIDER="${2:-}"
      shift 2
      ;;
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    --audio)
      AUDIO_FILE="${2:-}"
      shift 2
      ;;
    --phrase)
      PHRASE="${2:-}"
      shift 2
      ;;
    --language|--keyterm|--expect|--elevenlabs-commit-strategy|--elevenlabs-vad-silence-threshold|--elevenlabs-vad-threshold|--elevenlabs-min-speech-duration|--elevenlabs-min-silence-duration)
      EXTRA_ARGS+=("$1" "${2:-}")
      shift 2
      ;;
    --elevenlabs-no-verbatim)
      EXTRA_ARGS+=("$1")
      shift
      ;;
    --verbose)
      EXTRA_ARGS+=("$1")
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

if [[ -z "$PROVIDER" ]]; then
  echo "--provider is required." >&2
  usage >&2
  exit 2
fi

mkdir -p "$CACHE_DIR"
SMOKE_BIN="$CACHE_DIR/live-stt-smoke-$PROVIDER-$MODE"

if [[ -z "$AUDIO_FILE" ]]; then
  GENERATED_NAME="${PROVIDER}-${MODE}"
  AIFF_FILE="$CACHE_DIR/$GENERATED_NAME.aiff"
  AUDIO_FILE="$CACHE_DIR/$GENERATED_NAME.wav"
  say -o "$AIFF_FILE" "$PHRASE"
  afconvert -f WAVE -d LEI16@16000 -c 1 "$AIFF_FILE" "$AUDIO_FILE"
fi

if [[ "$MODE" == "realtime" ]]; then
  uv run --python /usr/bin/python3 --with websockets python "$ROOT/scripts/live-realtime-stt-smoke.py" \
    --provider "$PROVIDER" \
    --audio "$AUDIO_FILE" \
    --expect "custom dictation" \
    ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}
else
  swiftc -parse-as-library "$ROOT/scripts/live-stt-smoke.swift" -o "$SMOKE_BIN"
  "$SMOKE_BIN" \
    --provider "$PROVIDER" \
    --audio "$AUDIO_FILE" \
    --expect "custom dictation" \
    ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}
fi
