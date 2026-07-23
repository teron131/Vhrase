# Vhrase

Vhrase is a small native macOS menu bar app for configurable cloud speech-to-text and optional context-aware cleanup.

It records microphone audio, transcribes with xAI or ElevenLabs, can stream in realtime, stores a local transcript history, and can use an OpenAI-compatible model to clean up the transcript before returning it to the originating app.

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
A saved Keychain credential takes precedence. A nonempty `XAI_API_KEY`, `ELEVENLABS_API_KEY`, or `LLM_API_KEY` launch-environment value is used only when the matching saved item is empty.
The development run command uses shell and ignored `.env` values in memory without reading or modifying Keychain, which prevents rebuilt development binaries from producing repeated credential prompts.
Normal Finder and menu-bar launches continue to use saved Keychain credentials.

## Source Layout

`Sources/VhraseApp` is grouped by ownership:

- `App`: SwiftUI entrypoint and app-state orchestration.
- `Domain`: validated settings, shortcuts, workflow status, and transcript contracts.
- `UI`: main window, menu-bar pop-up, and recorder HUD surfaces.
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

The run script stops stale Vhrase processes, rebuilds and signs `dist/Vhrase.app`, and launches the menu-bar app bundle instead of the raw Swift executable. Vhrase presents its main window on first launch; later launches stay out of the Dock until you open it from the menu bar.
