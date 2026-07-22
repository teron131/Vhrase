# Vhrase

Vhrase is a small native macOS menu bar app for configurable cloud speech-to-text and optional context-aware cleanup.

It records microphone audio, transcribes with xAI or ElevenLabs, can stream in realtime, stores a local transcript history, and can use an OpenAI-compatible model to clean up the transcript before safe copy or target-app paste.

## Quick Start

```sh
bash scripts/ensure-local-codesign-identity.sh
./scripts/build-and-run.sh
```

The identity command is a one-time, idempotent setup that creates `Vhrase Local Development` in the login Keychain and trusts it only for local code signing.
macOS may request one Keychain or trust authorization during that setup; later builds reuse the same identity instead of triggering recurring credential and privacy prompts.
The local identity can be removed later with Keychain Access if Vhrase development is no longer needed.

The first recording can trigger macOS microphone permission.
Input Monitoring is only needed when Fn/Globe is the global shortcut.
Screenshot context is off by default, and Screen Recording permission is only needed when you explicitly enable it for LLM cleanup.
Accessibility permission can be needed when paste insertion targets another app.
These are feature-specific macOS privacy prompts and are separate from the one-time local signing setup.
API keys entered in Vhrase are stored as generic-password items in macOS Keychain under the `Vhrase` service.
A nonempty `XAI_API_KEY`, `ELEVENLABS_API_KEY`, or `AI_GATEWAY_API_KEY` launch-environment value overrides its saved Keychain item for that process.
The development run command securely synchronizes those nonempty overrides into Vhrase's Keychain so later Finder and menu-bar launches keep working without shell inheritance.

## Source Layout

`Sources/VhraseApp` is grouped by ownership:

- `App`: SwiftUI entrypoint and app-state orchestration.
- `Domain`: validated settings, shortcuts, workflow status, and transcript contracts.
- `UI`: main window, menu-bar pop-up, and settings surfaces.
- `Transcription/Audio`: microphone capture and PCM conversion.
- `Transcription/Upload`: multipart upload provider adapters.
- `Transcription/Realtime`: WebSocket sessions and ordered transcript accumulation.
- `Adjustment`: LLM adjustment, local cleanup fallback, and replacement rules.
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

The run script stops stale Vhrase processes, rebuilds and signs `dist/Vhrase.app`, and launches the menu-bar app bundle instead of the raw Swift executable. Vhrase presents its main window on first launch; later launches stay out of the Dock until you explicitly open Home, History, or Settings.
