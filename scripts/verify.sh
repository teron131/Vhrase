#!/usr/bin/env bash
# Verifies production-facing Vhrase behavior, builds and signs the app bundle, and optionally smoke-launches it.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/dist/Vhrase.app"
PLIST="$APP_DIR/Contents/Info.plist"

export CLANG_MODULE_CACHE_PATH="$ROOT/.build/ModuleCache"
export PYTHONPYCACHEPREFIX="$ROOT/.cache/python"

RUN_LAUNCH_CHECK=0
BUILD_CONFIG="debug"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --launch)
      RUN_LAUNCH_CHECK=1
      shift
      ;;
    --release)
      BUILD_CONFIG="release"
      shift
      ;;
    --help|-h)
      echo "Usage: bash scripts/verify.sh [--launch] [--release]"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

cd "$ROOT"

echo "==> Building audio processing dependency"
swift build --jobs 4
SWIFT_BIN_DIR="$(swift build --show-bin-path)"
SPEEX_CHECK_FLAGS=(-I "$ROOT/.build/checkouts/CSpeex/Sources/speex/include")
SPEEX_OBJECTS=("$SWIFT_BIN_DIR"/speex.build/*/*.o)

if /usr/bin/grep -Eq 'find-generic-password.*[[:space:]]-w' "$ROOT/scripts/build-and-run.sh"; then
  echo "The app launcher must not read Keychain secret values during verification." >&2
  exit 1
fi

echo "==> Running focused Swift checks"
APP_DOMAIN_SOURCES=(
  Sources/VhraseApp/Domain/DictationSettings.swift
  Sources/VhraseApp/Domain/HuggingFaceModelReference.swift
  Sources/VhraseApp/Domain/PolishPreferences.swift
  Sources/VhraseApp/Domain/Shortcut.swift
  Sources/VhraseApp/Domain/Transcript.swift
  Sources/VhraseApp/Domain/WorkflowStatus.swift
)
APP_PRESENTATION_CHECK_SOURCES=(
  "${APP_DOMAIN_SOURCES[@]}"
  Sources/VhraseApp/App/SetupDiagnostics.swift
  Sources/VhraseApp/System/PermissionManager.swift
  Sources/VhraseApp/Transcription/ProviderContracts.swift
  Sources/VhraseApp/UI/Design/VhraseTheme.swift
  Sources/VhraseApp/UI/Design/WaveformLevelResponse.swift
  Sources/VhraseApp/UI/DictationPresentation.swift
)
APP_PRESENTATION_CHECKS=(
  scripts/checks/permission-request-plan-check.swift
  scripts/checks/record-button-state-check.swift
  scripts/checks/readiness-summary-check.swift
  scripts/checks/setup-diagnostics-check.swift
  scripts/checks/history-metadata-check.swift
  scripts/checks/waveform-response-check.swift
)
APP_CORE_CHECK_SOURCES=(
  "${APP_DOMAIN_SOURCES[@]}"
  Sources/VhraseApp/Adjustment/Local/LocalAdjustment.swift
  Sources/VhraseApp/Storage/DictationActivityStore.swift
  Sources/VhraseApp/Storage/SettingsStore.swift
  Sources/VhraseApp/Storage/TranscriptHistoryStore.swift
  Sources/VhraseApp/UI/MainWindow/HistorySearch.swift
  Sources/VhraseApp/UI/Components/ActivityRange.swift
)
APP_CORE_CHECKS=(
  scripts/checks/status-flow-check.swift
  scripts/checks/shortcut-behavior-check.swift
  scripts/checks/dictation-activity-check.swift
  scripts/checks/vocabulary-migration-check.swift
  scripts/checks/polish-preferences-check.swift
  scripts/checks/customization-snapshot-check.swift
  scripts/checks/history-check.swift
  scripts/checks/history-search-check.swift
  scripts/checks/demo-adjustment-check.swift
)
APP_PROVIDER_CHECK_SOURCES=(
  "${APP_DOMAIN_SOURCES[@]}"
  Sources/VhraseApp/Transcription/Audio/AudioRecorder.swift
  Sources/VhraseApp/Transcription/Audio/PCM16AudioConverter.swift
  Sources/VhraseApp/Transcription/Audio/AudioInputDevice.swift
  Sources/VhraseApp/Transcription/Audio/DeviceAudioCapture.swift
  Sources/VhraseApp/Transcription/Audio/AudioPreprocessor.swift
  Sources/VhraseApp/Transcription/Audio/AudioInputPreview.swift
  Sources/VhraseApp/Transcription/Audio/AudioTestClip.swift
  Sources/VhraseApp/Transcription/Upload/MultipartForm.swift
  Sources/VhraseApp/Transcription/ProviderContracts.swift
  Sources/VhraseApp/Transcription/Realtime/RealtimeTranscription.swift
  Sources/VhraseApp/Transcription/Realtime/RealtimeTranscriptAccumulator.swift
  Sources/VhraseApp/Transcription/Upload/UploadTranscriptionClients.swift
  Sources/VhraseApp/Storage/SettingsStore.swift
)
APP_PROVIDER_CHECKS=(
  scripts/checks/audio-capture-health-check.swift
  scripts/checks/audio-tap-isolation-check.swift
  scripts/checks/audio-processing-check.swift
  scripts/checks/audio-preview-check.swift
  scripts/checks/input-device-check.swift
  scripts/checks/xai-stt-options-check.swift
  scripts/checks/elevenlabs-options-check.swift
  scripts/checks/gemini-stt-options-check.swift
  scripts/checks/openai-stt-options-check.swift
  scripts/checks/vercel-stt-options-check.swift
  scripts/checks/parakeet-options-check.swift
  scripts/checks/hugging-face-options-check.swift
)
APP_FINALIZATION_CHECK_SOURCES=(
  "${APP_DOMAIN_SOURCES[@]}"
  Sources/VhraseApp/System/ScreenContext.swift
  Sources/VhraseApp/Adjustment/Local/OpenCCInstaller.swift
  Sources/VhraseApp/Adjustment/Local/ChineseTextConverter.swift
  Sources/VhraseApp/Adjustment/Local/LocalAdjustment.swift
  Sources/VhraseApp/Adjustment/LLMEndpoint.swift
  Sources/VhraseApp/Adjustment/LLMAdjustmentClient.swift
  Sources/VhraseApp/Adjustment/TranscriptFinalization.swift
)
APP_FINALIZATION_CHECKS=(
  scripts/checks/adjustment-fallback-check.swift
  scripts/checks/llm-adjustment-request-check.swift
  scripts/checks/opencc-installer-check.swift
)
APP_CREDENTIAL_CHECK_SOURCES=(
  "${APP_DOMAIN_SOURCES[@]}"
  Sources/VhraseApp/Storage/APIKeyStore.swift
)
APP_CREDENTIAL_CHECKS=(
  scripts/checks/api-key-resolution-check.swift
  scripts/checks/keychain-interaction-check.swift
)
APP_INSERTION_CHECK_SOURCES=(
  Sources/VhraseApp/System/TextInsertion.swift
)
APP_INSERTION_CHECKS=(
  scripts/checks/text-insertion-check.swift
)

mkdir -p "$ROOT/.cache/checks"
run_compiled_check() {
  local check_script="$1"
  shift
  local check_name
  check_name="$(basename "$check_script" .swift)"
  swiftc -parse-as-library "$@" "$check_script" -o "$ROOT/.cache/checks/$check_name"
  "$ROOT/.cache/checks/$check_name"
}

for check_script in "${APP_PRESENTATION_CHECKS[@]}"; do
  run_compiled_check "$check_script" "${APP_PRESENTATION_CHECK_SOURCES[@]}"
done
for check_script in "${APP_CORE_CHECKS[@]}"; do
  run_compiled_check "$check_script" "${APP_CORE_CHECK_SOURCES[@]}"
done
for check_script in "${APP_PROVIDER_CHECKS[@]}"; do
  run_compiled_check "$check_script" "${APP_PROVIDER_CHECK_SOURCES[@]}" "${SPEEX_CHECK_FLAGS[@]}" "${SPEEX_OBJECTS[@]}"
done
for check_script in "${APP_FINALIZATION_CHECKS[@]}"; do
  run_compiled_check "$check_script" "${APP_FINALIZATION_CHECK_SOURCES[@]}"
done
for check_script in "${APP_CREDENTIAL_CHECKS[@]}"; do
  run_compiled_check "$check_script" "${APP_CREDENTIAL_CHECK_SOURCES[@]}"
done
for check_script in "${APP_INSERTION_CHECKS[@]}"; do
  run_compiled_check "$check_script" "${APP_INSERTION_CHECK_SOURCES[@]}"
done
run_compiled_check scripts/checks/on-device-model-store-check.swift \
  "${APP_DOMAIN_SOURCES[@]}" \
  Sources/VhraseApp/Transcription/ProviderContracts.swift \
  Sources/VhraseApp/Transcription/OnDevice/OnDeviceModel.swift \
  Sources/VhraseApp/Transcription/OnDevice/OnDeviceModelStore.swift
run_compiled_check scripts/checks/hugging-face-process-check.swift \
  "${APP_DOMAIN_SOURCES[@]}" \
  Sources/VhraseApp/Transcription/ProviderContracts.swift \
  Sources/VhraseApp/Transcription/OnDevice/HuggingFaceRecognizer.swift \
  Sources/VhraseApp/Transcription/OnDevice/HuggingFaceProcess.swift
run_compiled_check scripts/checks/transcription-test-check.swift \
  Sources/VhraseApp/App/TranscriptionTest.swift \
  Sources/VhraseApp/Transcription/Audio/SpeechPresenceGate.swift

echo "==> Checking the Hugging Face helper without model dependencies"
UV_CACHE_DIR="$ROOT/.cache/uv" uv run --offline --no-project --python 3.13 \
  python scripts/checks/hugging-face-runtime-check.py

echo "==> Compiling live STT smoke client"
mkdir -p "$ROOT/.cache/live-stt-smoke"
swiftc -parse-as-library "$ROOT/scripts/live-stt-smoke.swift" -o "$ROOT/.cache/live-stt-smoke/live-stt-smoke"
"$ROOT/.cache/live-stt-smoke/live-stt-smoke" --help >/dev/null
/usr/bin/python3 -m py_compile "$ROOT/scripts/live-realtime-stt-smoke.py"
/usr/bin/python3 -m py_compile "$ROOT/scripts/live-adjustment-smoke.py"
bash "$ROOT/scripts/live-mic-stt-smoke.sh" --help >/dev/null
bash "$ROOT/scripts/doctor.sh" --help >/dev/null

echo "==> Generating offline audio fixture"
AUDIO_SMOKE_DIR="$ROOT/.cache/audio-smoke"
AUDIO_SMOKE_AIFF="$AUDIO_SMOKE_DIR/vhrase-smoke.aiff"
AUDIO_SMOKE_WAV="$AUDIO_SMOKE_DIR/vhrase-smoke.wav"
mkdir -p "$AUDIO_SMOKE_DIR"
say -o "$AUDIO_SMOKE_AIFF" "Vhrase audio smoke test. Custom dictation is ready."
afconvert -f WAVE -d LEI16@16000 -c 1 "$AUDIO_SMOKE_AIFF" "$AUDIO_SMOKE_WAV"

audio_fixture_is_valid() {
  local info
  local byte_count
  info="$(afinfo "$1" 2>/dev/null)" || return 1
  byte_count="$(awk '/audio bytes:/ {print $3}' <<<"$info")"
  [[ "$info" == *"1 ch"* && "$info" == *"16000 Hz, Int16"* && "$byte_count" =~ ^[0-9]+$ && "$byte_count" -gt 0 ]]
}

if ! audio_fixture_is_valid "$AUDIO_SMOKE_WAV"; then
  echo "System speech synthesis unavailable; generating deterministic tone fixture"
  /usr/bin/python3 - "$AUDIO_SMOKE_WAV" <<'PY'
import math
import struct
import sys
import wave

sample_rate = 16_000
duration_seconds = 2
samples = []
for index in range(sample_rate * duration_seconds):
    segment = min(index // (sample_rate // 2), 3)
    frequency = (440, 554, 659, 880)[segment]
    envelope = min(index / 800, (sample_rate * duration_seconds - index) / 800, 1)
    samples.append(int(10_000 * envelope * math.sin(2 * math.pi * frequency * index / sample_rate)))

with wave.open(sys.argv[1], "wb") as fixture:
    fixture.setnchannels(1)
    fixture.setsampwidth(2)
    fixture.setframerate(sample_rate)
    fixture.writeframes(b"".join(struct.pack("<h", sample) for sample in samples))
PY
fi

if ! audio_fixture_is_valid "$AUDIO_SMOKE_WAV"; then
  echo "Generated audio fixture is not nonempty mono 16 kHz Int16 PCM." >&2
  exit 1
fi

# The bundle entrypoint owns the build, signing, signature verification, and entitlement checks.
echo "==> Building, bundling, and signing app"
bash scripts/bundle-app.sh "$BUILD_CONFIG"

echo "==> Validating bundle metadata"
plutil -lint "$PLIST"

echo "==> Running local readiness doctor"
bash scripts/doctor.sh --strict

if [[ "$RUN_LAUNCH_CHECK" == "1" ]]; then
  echo "==> Running menu-bar launch check"
  bash scripts/check-menu-bar.sh "$APP_DIR"
fi

echo "==> Verification complete"
