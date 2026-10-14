# Vhrase

Vhrase is a small native macOS menu bar app for configurable cloud or on-device speech-to-text and optional context-aware cleanup.

It records microphone audio, transcribes natively with Gemini, Grok (xAI), ElevenLabs, OpenAI, any Vercel AI Gateway transcription model, or NVIDIA Parakeet or a Hugging Face model running on this Mac, stores a local transcript history, and returns the result to the originating app.
Parakeet and Hugging Face models need no API key and work offline after a one-time download; Parakeet covers 25 European languages, while Hugging Face runs Whisper Large v3 Turbo or any speech model the `transformers` pipeline accepts, in a Python runtime that `uv` builds.
Gemini offers vocabulary hints and Smart transcription; Grok offers vocabulary hints, filler removal, and number formatting.
Grok and ElevenLabs also support realtime streaming, and an optional OpenAI-compatible model can provide a separate cleanup pass.

## Quick Start

```sh
bash scripts/ensure-local-codesign-identity.sh
./scripts/build-and-run.sh
```

The identity command is a one-time, idempotent setup that creates `Vhrase Local Development` in the login Keychain and trusts it only for local code signing.
macOS may request one Keychain or trust authorization during that setup; later builds reuse the same identity instead of triggering recurring credential and privacy prompts.
The local identity can be removed later with Keychain Access if Vhrase development is no longer needed.

The first recording can trigger macOS microphone permission.
Accessibility returns finalized text to the originating app and also enables the global Fn/Globe shortcut.
Input Monitoring is only an optional fallback when Fn/Globe does not respond reliably.
Screenshot context is off by default, and Screen Recording permission is only needed when you explicitly enable it for LLM cleanup.
These are feature-specific macOS privacy prompts and are separate from the one-time local signing setup.
API keys entered in Vhrase are stored as generic-password items in macOS Keychain under the `Vhrase` service.
A saved Keychain credential takes precedence.
A nonempty `GEMINI_API_KEY`, `XAI_API_KEY`, `ELEVENLABS_API_KEY`, `OPENAI_API_KEY`, `AI_GATEWAY_API_KEY`, or `LLM_API_KEY` launch-environment value is used next, and a direct literal export in `~/.zshrc` fills any remaining key without executing shell code.
The development run command uses ignored `.env` values in memory without reading Keychain, preventing rebuilt development binaries from producing credential prompts.
A nonsecret LLM credential reference such as `AI_GATEWAY_API_KEY` is stored in preferences, survives rebuilds, and resolves against the launch environment, `~/.zshrc`, or `.env`.
Normal Finder and menu-bar launches prefer saved Keychain credentials before using the in-memory environment fallbacks.

## Source Layout

`Sources/VhraseApp` is grouped by ownership:

- `App`: scene composition, process launch/termination, dictation workflow orchestration, and the session's credentials.
- `Domain`: validated settings, shortcuts, workflow status, and transcript contracts.
- `UI`: main window, menu-bar pop-up, and recorder HUD surfaces; each main-window destination owns its controls and temporary editing lifecycle.
- `Transcription`: provider request contracts and the recording that carries one capture through to recognized text.
- `Transcription/Audio`: microphone capture, PCM conversion, and live level metering.
- `Transcription/Upload`: cloud upload provider adapters.
- `Transcription/Realtime`: WebSocket sessions and ordered transcript accumulation.
- `Transcription/OnDevice`: on-device model setup shared by Parakeet (FluidAudio) and Hugging Face models (a Python helper started through `uv`), and each one's recognition.
- `Adjustment`: LLM polishing with shared vocabulary, Chinese conversion, and local cleanup fallback.
- `System`: macOS permissions, hotkeys, frontmost app context, screenshots, and text insertion.
- `Storage`: Keychain, settings, and transcript-history persistence.

## Docs

- [Usage](docs/usage.md): launching, configuring, recording, shortcuts, and customization.
- [Development](docs/development.md): build, verify, bundle, doctor, and live smoke commands.
- [API Notes](docs/api-notes.md): provider endpoints and request behavior.

## Main Commands

```sh
./scripts/build-and-run.sh
bash scripts/doctor.sh
bash scripts/verify.sh
bash scripts/verify.sh --launch
```

The run script stops stale Vhrase processes, rebuilds and signs `dist/Vhrase.app`, and launches the menu-bar app bundle instead of the raw Swift executable. Vhrase presents its main window on first launch; later launches stay out of the Dock until you open it from the menu bar.
