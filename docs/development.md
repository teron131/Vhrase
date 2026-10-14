# Development

## Run

Use the single development entrypoint so Vhrase launches once as a signed menu-bar app bundle:

```sh
./scripts/build-and-run.sh
```

The script stops stale Vhrase processes before rebuilding, signing, and opening `dist/Vhrase.app`.

## Build

```sh
swift build
```

## Microphone and Fn diagnostics

Vhrase writes lifecycle events to macOS unified logging under the `local.codex.Vhrase` subsystem at notice or error level, so diagnostics do not require a special logging launch.
To watch an already running app without restarting it:

```sh
/usr/bin/log stream --style compact --predicate 'subsystem == "local.codex.Vhrase"'
```

To inspect a recent stuck popup after the fact:

```sh
/usr/bin/log show --last 30m --style compact --predicate 'subsystem == "local.codex.Vhrase"'
```

The `FnHotkey` category records key edges, unavailable event taps, and recovery after macOS disables a tap; `Dictation` records attempt numbers, workflow phases, and provider error domains/codes.
`AudioRecorder` records capture mode, format, PCM counts, failures, and cleanup; `DeviceCapture` records hardware start/stop completion and runtime errors.
`AudioDevice` records the numeric device, alive/running state, and exclusive owner PID; `-1` means no exclusive owner and `unknown` means the driver did not expose that property.
An input already running elsewhere is diagnostic evidence, not itself a conflict, so Vhrase does not reject it or change system defaults or exclusive ownership.
Logs exclude audio, transcripts, credentials, request URLs, device names, and device UIDs.

Selected-device startup and normal shutdown wait at most eight seconds; cancellation queues hardware cleanup without waiting for the driver, while normal completion drains queued audio before finalizing the recording.
A driver stuck inside a system call may release the physical microphone later, even though the popup has already reported failure.
During capture, errors and input-format changes become visible failures, and five seconds without processed PCM triggers a stall error; silent PCM remains healthy.
These bounds cover the selected-device AVFoundation queue and audio delivery, while the system-default AVAudioEngine prepare/start/stop calls still run synchronously.
For live verification, test Fn while another app uses the same input, then change or disconnect that input and verify failure feedback and a subsequent fresh recording.

## Verify

Run the local verification entrypoint:

```sh
bash scripts/verify.sh
```

The verification script runs focused Swift checks, generates and validates a nonempty mono 16 kHz Int16 PCM fixture at `.cache/audio-smoke/vhrase-smoke.wav`, compiles the live STT helpers, builds and signs the app bundle, validates its metadata, and runs the readiness doctor in strict mode.
The generated fixture is offline proof of the audio format path; verification never submits it to a provider or consumes account usage.
Credential checks validate environment resolution without requesting or printing secret values.
The on-device lifecycle checks use controlled model operations, the process check proves that a stubborn helper and its children exit, and the setup-test check verifies automatic recording completion, cancellation, and temporary-audio cleanup without a microphone.
The Hugging Face helper check uses `uv` with an already installed Python 3.13 to exercise model replacement and failure recovery without importing model libraries or downloading weights.

For stable macOS privacy permissions during local development, create the local codesigning identity once:

```sh
bash scripts/ensure-local-codesign-identity.sh
```

The command creates a ten-year self-signed `Vhrase Local Development` certificate and private key in the login Keychain, trusts that certificate locally for code signing, and removes its temporary certificate-package files when finished.
It may request one Keychain or trust authorization during initial setup, is safe to rerun, and can be reversed later in Keychain Access.
If the local identity is not present, the bundle falls back to ad-hoc signing and macOS may treat rebuilt apps as new permission clients.

To include a runtime smoke check that starts and quits the bundled menu bar app:

```sh
bash scripts/verify.sh --launch
```

To check local readiness without recording audio, calling providers, opening settings, or prompting for permissions:

```sh
bash scripts/doctor.sh
```

The doctor reports whether `opencc` is available for unconditional final transcript `s2hk` conversion.
It reports credential presence from macOS Keychain or an environment fallback without printing secret values.

## Credentials

Vhrase saves generic-password items under the Keychain service `Vhrase`, using `GEMINI_API_KEY`, `XAI_API_KEY`, `ELEVENLABS_API_KEY`, `OPENAI_API_KEY`, `AI_GATEWAY_API_KEY`, and `LLM_API_KEY` as account names.
Normal Finder launches read saved Keychain values first, then use launch-environment values and direct literal exports from `~/.zshrc` as fallbacks.
All credential operations run inside a serialized, process-local no-interaction scope and restore the previous interaction flag afterward.
The file-based login Keychain ignores LAContext-only dialog suppression, so this boundary deliberately uses the deprecated SecKeychain interaction APIs while retaining existing items and their access controls.
The focused `keychain-interaction-check.swift` creates and removes an isolated test Keychain under `.cache/checks`, proving locked reads and writes return without prompting; it never locks the user's login Keychain.
`./scripts/build-and-run.sh` skips Keychain reads and resolves credentials from the launch environment, `~/.zshrc`, and the ignored repository `.env` file in that order.
An LLM field value such as `AI_GATEWAY_API_KEY` is a nonsecret credential reference stored in preferences, so it survives development rebuilds and resolves against those environment sources.
Use this non-executable `.env` format:

```dotenv
XAI_API_KEY=
GEMINI_API_KEY=
ELEVENLABS_API_KEY=
OPENAI_API_KEY=
AI_GATEWAY_API_KEY=
LLM_API_KEY=
```

File-based values remain in memory and are never imported into Keychain.
Vhrase reads only direct literal `export KEY=value` assignments from `~/.zshrc`; it does not execute commands, expand variables, or source other files.

## Customization Contract

Customization exports use a JSON settings snapshot and intentionally exclude API keys.
Import accepts only regular files up to 1 MiB and validates local settings, provider keyterms, and the LLM endpoint before mutating persisted state.
Endpoint or shortcut changes and newly enabled LLM cleanup, screenshot context, or clipboard retention require an explicit warning confirmation that lists the sensitive changes.

## Bundle

Create a runnable `.app` bundle with microphone and screen-capture usage descriptions:

```sh
bash scripts/bundle-app.sh
```

The bundle is written to `dist/Vhrase.app` and signed with `VHRASE_CODESIGN_IDENTITY`, the local Vhrase development identity, or ad-hoc signing as a fallback.
Provider pickers use the compact [Google](https://artificialanalysis.ai/img/logos/google_small.svg), [ElevenLabs](https://artificialanalysis.ai/img/logos/elevenlabs_small.svg), [SpaceXAI](https://artificialanalysis.ai/img/logos/spacexai.svg), [NVIDIA](https://artificialanalysis.ai/img/logos/nvidia.svg), [OpenAI](https://artificialanalysis.ai/img/logos/openai.svg), [Vercel](https://artificialanalysis.ai/img/logos/vercel.svg), and [Hugging Face](https://artificialanalysis.ai/img/logos/huggingface.svg) SVGs from Artificial Analysis, stored unchanged in `Sources/VhraseApp/UI/Resources/ProviderIcons`.
SwiftPM packages these assets in `Vhrase_VhraseApp.bundle`; the bundle script copies that resource bundle into the app's `Contents/Resources` directory so installed apps do not depend on the build checkout.
FluidAudio compiles into the executable from source, so the bundle embeds no third-party frameworks and hardened-runtime library validation is unaffected; its trait list is empty to leave out the prebuilt NeMo text-normalization library that recognition does not use.
The bundle script copies FluidAudio's Apache-2.0 license and third-party notices beside the Speex license; Parakeet and Hugging Face model files are downloaded at runtime and never bundled.
The same resource bundle carries `asr.py` and `asr.py.lock`, each packaged by name so nothing else in their source folder comes along; the Python environment they describe is built by uv on the user's Mac, outside the app bundle and outside its code signature.
After changing the script's dependency block, run `uv lock --script Sources/VhraseApp/Transcription/OnDevice/HuggingFaceRuntime/asr.py` so the lockfile matches, because uv cannot rewrite it inside a signed bundle.
For normal local development, use the persistent Vhrase identity rather than the ad-hoc fallback so Keychain and TCC permissions remain attached to one designated application identity.

## On-device Smoke

The on-device paths can be exercised end to end on WAV files without a microphone, provider usage, or the app's settings:

```sh
B=.build/arm64-apple-macosx/debug
C=.build/checkouts/FluidAudio/Sources
swiftc -parse-as-library -I $B/Modules -I $C/FastClusterWrapper/include -I $C/MachTaskSelfWrapper/include Sources/VhraseApp/Domain/*.swift Sources/VhraseApp/Transcription/ProviderContracts.swift Sources/VhraseApp/Transcription/Upload/*.swift Sources/VhraseApp/Transcription/OnDevice/*.swift Sources/VhraseApp/System/ScreenContext.swift Sources/VhraseApp/Adjustment/Local/*.swift Sources/VhraseApp/Adjustment/LLMEndpoint.swift Sources/VhraseApp/Adjustment/LLMAdjustmentClient.swift Sources/VhraseApp/Adjustment/TranscriptFinalization.swift Sources/VhraseApp/Storage/TranscriptHistoryStore.swift Sources/VhraseApp/System/ResourceBundle.swift $B/VhraseApp.build/DerivedSources/resource_bundle_accessor.swift scripts/on-device-stt-smoke.swift $B/FluidAudio.build/*.o $B/FastClusterWrapper.build/*.o $B/MachTaskSelfWrapper.build/*.o -lc++ -o .cache/checks/on-device-stt-smoke
.cache/checks/on-device-stt-smoke --download recording.wav "expected phrase"
.cache/checks/on-device-stt-smoke --hugging-face --language auto --download recording.wav "expected phrase"
```

Run `swift build` first so FluidAudio's objects and the resource bundle with the Hugging Face helper exist.
Without options the smoke runs Parakeet; `--hugging-face` runs the built-in Whisper model, `--hugging-face owner/name` any other Hugging Face model ID, and `--language` sets a Whisper model's language code or `auto`.
Each recording should match Vhrase's capture format, 16 kHz mono Int16 WAV, for example from `afconvert -f WAVE -d LEI16@16000 -c 1 input output.wav`.
The smoke uses the same `OnDeviceModelStore`, model, recognizer, `TranscriptFinalizer`, and history store calls as the app, with history in a temporary defaults suite.
It then checks that three seconds of silence produce nothing to deliver, that cancelling a four-minute transcription returns no text, and that the next transcription still succeeds.
For Hugging Face the silence step only reports what came back, because Whisper models word silence and the app's recording-level gate, not the recognizer, refuses such recordings.
`--download` fetches the model into the app's own Models folder when it is missing, so a later app launch reuses it.

## Live STT Smokes

The app's actual cloud upload adapters can be tested with a short WAV and environment credentials, without reading Keychain or changing app settings:

```sh
swiftc -parse-as-library Sources/VhraseApp/Domain/*.swift Sources/VhraseApp/Transcription/ProviderContracts.swift Sources/VhraseApp/Transcription/Upload/*.swift Sources/VhraseApp/Storage/APIKeyStore.swift scripts/live-native-stt-smoke.swift -o .cache/checks/live-native-stt-smoke
.cache/checks/live-native-stt-smoke /absolute/path/recording.wav
.cache/checks/live-native-stt-smoke /absolute/path/recording.wav vercel openAI
```

This makes one native request to Gemini, Grok, OpenAI, and Vercel AI Gateway, or only to the providers named after the recording, with the same developer vocabulary and Gemini Smart enabled; a provider whose key is not in the environment is skipped.
It may consume provider usage and prints the sample transcripts, never credentials.
To explicitly show the rebuilt control center, launch `dist/Vhrase.app` with `--show-window`; normal launches retain menu-bar-only behavior.

Run a live provider upload smoke test with a generated local voice sample:

```sh
bash scripts/live-stt-smoke.sh --provider xai
bash scripts/live-stt-smoke.sh --provider elevenlabs
```

Run the same generated sample through realtime WebSocket transcription:

```sh
bash scripts/live-stt-smoke.sh --provider xai --mode realtime
bash scripts/live-stt-smoke.sh --provider elevenlabs --mode realtime
```

The live smoke test creates a provider-and-mode-named WAV under `.cache/live-stt-smoke/` with macOS `say`, submits it to the selected provider, and checks that the transcript contains `custom dictation`.
It resolves the matching `Vhrase` Keychain item first, then uses a nonempty `XAI_API_KEY` or `ELEVENLABS_API_KEY` environment value only as a fallback, and it may consume provider STT usage.
Upload smokes compile `scripts/live-stt-smoke.swift`, while realtime smokes use `uv` with the system Python, `websockets`, and `scripts/live-realtime-stt-smoke.py`.
ElevenLabs model IDs are fixed to `scribe_v2` for upload and `scribe_v2_realtime` for realtime, matching the app rather than exposing drift-prone model flags.
xAI realtime smoke audio is paced in exact 3,200-byte (100 ms) PCM frames and its fallback transcript commits complete utterances only on `speech_final`.

To record from the real microphone and send that audio through the same smoke path:

```sh
bash scripts/live-mic-stt-smoke.sh --provider xai
bash scripts/live-mic-stt-smoke.sh --provider elevenlabs --mode realtime
```

The mic smoke test records `.cache/live-mic-stt-smoke/mic.wav` using FFmpeg's AVFoundation input, then passes that file to `scripts/live-stt-smoke.sh`.
It may trigger macOS microphone permission for the terminal app running the command.
Speak a phrase that includes `custom dictation`, or pass a different `--expect` value.

## Live Adjustment Smoke

Run a live OpenAI-compatible LLM adjustment smoke test with screenshot context:

```sh
python3 scripts/live-adjustment-smoke.py --list-models
python3 scripts/live-adjustment-smoke.py --require-screenshot
```

The adjustment smoke test resolves the matching `Vhrase` Keychain item before using a nonempty `LLM_API_KEY` environment fallback, reads nonsecret `adjustmentBaseURL` and `adjustmentModel` values from app defaults when present, captures `.cache/live-adjustment-smoke/screen.png` with macOS `screencapture`, sends the screenshot plus a sample transcript to `/chat/completions`, and checks that the adjusted text contains `OpenAI`.
Unlike the app's opt-in disposable screenshot path, this explicit development smoke keeps its named screenshot artifact for inspection; pass `--no-screenshot` to avoid capture.
The model-list check verifies that the current key can see configured language models before spending time debugging prompt or screenshot behavior.

## UI and application lifecycle

`AppLifecycle` owns the single-instance guard, app state, recorder panel, deferred credential loading, and normal termination cleanup.
`VhraseApp` composes the main scene, menu-bar extra, and commands; `MainWindowCoordinator` owns first-launch visibility and the shared route used by menu actions and Command-comma.
Closing or hiding the main window keeps the menu-bar app running, while normal application termination flushes credential edits and releases capture resources.

`MainWindowView` retains sidebar selection, Transcription stage selection, activity range, and History browsing state across destination changes.
`DictationView`, `CaptureView`, `OutputView`, `HistoryView`, and `SystemView` own their destination controls and display policy.
The Transcription destination releases shortcut editing and microphone preview when leaving the destination or deactivating its window; System ends credential editing and flushes pending saves at those boundaries.
`MainWindowEvents` scopes Escape and activation callbacks to the actual host window, and `MainWindowControls` contains only shared visual building blocks, including the settings groups and rows every destination uses.
`VhraseTheme` and `VhraseFont` carry the visual rules: the orange accent identifies Vhrase's controls, status colors mark recording, processing, readiness, and failure, and the New York serif sets only the user's own words.
The recorder's panel lifecycle belongs to `RecorderHUDPanelController`, separately from the SwiftUI pill content.
`AudioRecorder` owns capture startup, health monitoring, and WAV delivery; `PCM16AudioConverter` owns resampling, enhancement, transport framing, and final audio draining.
`TranscriptionRecording` owns one recording from microphone start to recognized text for both dictation and the setup test: capture, the speech-presence gate, the realtime session when the mode streams, and temporary-audio cleanup; a failed or cancelled step releases all of them.
`RecordingMeter` publishes the active recording's level, waveform history, and elapsed time apart from `AppState`, so ten level updates a second redraw only the meters and timers that show them instead of re-evaluating every window, including a hidden one.
`Credentials` owns the session's credential state: environment fallbacks, the System page's editable fields, their debounced Keychain saves, and the value each request uses.
`HistorySearch.Index` owns one archive snapshot, its provider and destination summaries, and the most recent ranking; history edits replace the index, which carries each unchanged transcript's search document over so only the edited one is tokenized, while date filters and counts refresh when the calendar day or time zone changes.
On-device model preparation and removal completions belong to the selection that started them; idle countdowns start only after all warm-up and transcription operations finish, lasting ten minutes for Hugging Face and five minutes for Parakeet.
Hugging Face listens for macOS memory-pressure events: warning or critical pressure releases an idle helper and suppresses background warm-up; active recognition finishes before release, and explicit transcription remains available under pressure.
Returning to normal pressure permits the warm period again without reloading an idle model.
`HuggingFaceProcess` owns uv and its Python children as one process group, requests termination once, escalates to a kill after one second, and lets recognition await exit before replacing the helper.
Normal app termination stops all registered Hugging Face helpers and rejects launches from queued tasks; changing away from Hugging Face also cancels its pending warm-up and unloads the recognizer.
`TranscriptionTest` owns the five-second setup recording and raw result, running the same `TranscriptionRecording` as dictation without entering the adjustment, insertion, history, or activity pipeline.
