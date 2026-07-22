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

## Verify

Run the local verification entrypoint:

```sh
bash scripts/verify.sh
```

The verification script runs focused Swift checks, generates and validates a nonempty mono 16 kHz Int16 PCM fixture at `.cache/audio-smoke/vhrase-smoke.wav`, compiles the live STT helpers, builds and signs the app bundle, validates its metadata, and runs the readiness doctor in strict mode.
The generated fixture is offline proof of the audio format path; verification never submits it to a provider or consumes account usage.
Credential readiness checks inspect environment-variable and Keychain item presence without requesting or printing secret values, so verification does not produce one password prompt per credential.

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
It reports credential presence from a nonempty launch environment override or the macOS Keychain without printing secret values.

## Credentials

Vhrase saves generic-password items under the Keychain service `Vhrase`, using `XAI_API_KEY`, `ELEVENLABS_API_KEY`, and `AI_GATEWAY_API_KEY` as account names.
A nonempty environment value takes precedence over the corresponding saved item for that process.
`./scripts/build-and-run.sh` launches Vhrase with an explicit import argument, so nonempty supported environment values are also synchronized into Keychain before later Finder or menu-bar cold launches.
An absent environment variable never removes or replaces an existing Keychain item, and editable fields contain only saved Keychain values when no override is active.
Environment-backed fields are disabled for editing during that process so SwiftUI placeholder updates cannot erase the synchronized item.

## Customization Contract

Customization exports use the current version 2 JSON contract and intentionally exclude API keys.
Import accepts only regular files up to 1 MiB, rejects every version except the current one, and validates local settings, provider keyterms, and the LLM endpoint before mutating persisted state.
Endpoint or shortcut changes and newly enabled LLM cleanup, screenshot context, or automatic paste require an explicit warning confirmation that lists the sensitive changes.

## Bundle

Create a runnable `.app` bundle with microphone and screen-capture usage descriptions:

```sh
bash scripts/bundle-app.sh
```

The bundle is written to `dist/Vhrase.app` and signed with `VHRASE_CODESIGN_IDENTITY`, the local Vhrase development identity, or ad-hoc signing as a fallback.
For normal local development, use the persistent Vhrase identity rather than the ad-hoc fallback so Keychain and TCC permissions remain attached to one designated application identity.

## Live STT Smokes

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
It resolves a nonempty `XAI_API_KEY` or `ELEVENLABS_API_KEY` environment override before the matching `Vhrase` Keychain item, and it may consume provider STT usage.
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

The adjustment smoke test resolves a nonempty `AI_GATEWAY_API_KEY` environment override before the matching `Vhrase` Keychain item, reads nonsecret `adjustmentBaseURL` and `adjustmentModel` values from app defaults when present, captures `.cache/live-adjustment-smoke/screen.png` with macOS `screencapture`, sends the screenshot plus a sample transcript to `/chat/completions`, and checks that the adjusted text contains `OpenAI`.
Unlike the app's opt-in disposable screenshot path, this explicit development smoke keeps its named screenshot artifact for inspection; pass `--no-screenshot` to avoid capture.
The model-list check verifies that the current key can see configured language models before spending time debugging prompt or screenshot behavior.
