#!/usr/bin/env bash
# Records a short microphone sample with ffmpeg and runs it through live-stt-smoke.sh against the chosen provider.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE_DIR="$ROOT/.cache/live-mic-stt-smoke"
PROVIDER=""
MODE="upload"
DURATION="4"
AUDIO_DEVICE=":0"
OUTPUT_FILE="$CACHE_DIR/mic.wav"
EXTRA_ARGS=()

usage() {
  cat <<'USAGE'
Usage: bash scripts/live-mic-stt-smoke.sh --provider xai|elevenlabs [options]

Options:
  --mode upload|realtime       Defaults to upload.
  --duration seconds           Defaults to 4.
  --audio-device avfoundation  Defaults to :0, meaning audio device 0 and no video.
  --output path.wav            Defaults to .cache/live-mic-stt-smoke/mic.wav.
  --keyterm "OpenAI"           Repeatable provider keyterm.
  --expect "text"              Defaults to custom dictation in the downstream smoke script.

This uses ffmpeg's AVFoundation input. It may trigger macOS microphone permission for the terminal app running the command.
Use this to list AVFoundation devices:
  ffmpeg -f avfoundation -list_devices true -i ""
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
      EXTRA_ARGS+=("$1" "$2")
      shift 2
      ;;
    --duration)
      DURATION="${2:-}"
      shift 2
      ;;
    --audio-device)
      AUDIO_DEVICE="${2:-}"
      shift 2
      ;;
    --output)
      OUTPUT_FILE="${2:-}"
      shift 2
      ;;
    --keyterm|--expect|--language|--elevenlabs-commit-strategy|--elevenlabs-vad-silence-threshold|--elevenlabs-vad-threshold|--elevenlabs-min-speech-duration|--elevenlabs-min-silence-duration)
      EXTRA_ARGS+=("$1" "${2:-}")
      shift 2
      ;;
    --elevenlabs-no-verbatim|--verbose)
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

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg is required for microphone smoke tests." >&2
  exit 1
fi

mkdir -p "$CACHE_DIR" "$(dirname "$OUTPUT_FILE")"

echo "Recording microphone for ${DURATION}s to $OUTPUT_FILE"
echo "Speak a phrase that includes: custom dictation"
ffmpeg \
  -hide_banner \
  -loglevel error \
  -y \
  -f avfoundation \
  -i "$AUDIO_DEVICE" \
  -t "$DURATION" \
  -ac 1 \
  -ar 16000 \
  -sample_fmt s16 \
  "$OUTPUT_FILE"

bash "$ROOT/scripts/live-stt-smoke.sh" \
  --provider "$PROVIDER" \
  --mode "$MODE" \
  --audio "$OUTPUT_FILE" \
  ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}
