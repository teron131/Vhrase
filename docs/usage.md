# Usage

## Run The App

Build and open the signed app bundle:

```sh
bash scripts/ensure-local-codesign-identity.sh
./scripts/build-and-run.sh
```

Run the identity command once per development machine; it is idempotent and may request one Keychain or trust authorization while creating `Vhrase Local Development`.
Subsequent builds reuse that identity so macOS recognizes Vhrase as the same app instead of repeatedly asking for credential or privacy access.
The run script stops stale Vhrase processes, rebuilds and signs the bundle, and adds a microphone icon to the menu bar. Vhrase opens the main setup window once on first launch; later launches stay in the menu bar until you explicitly open Home, History, or Settings.
Use the bundle for normal operation so macOS associates privacy permissions with the app instead of Terminal.

## First Setup

1. Open **Setup** in the sidebar.
2. Add xAI and/or ElevenLabs credentials in Setup, or export them before running `./scripts/build-and-run.sh`; both paths store the nonempty values in macOS Keychain for later menu-bar and Finder launches.
3. Request Microphone access, which is the only permission required to record.
4. Grant Input Monitoring when Fn/Globe is the global shortcut.
5. Grant Screen Recording only when screenshot context is enabled, and Accessibility only when automatic paste is enabled.

The setup screen reports saved or environment-backed credentials separately and routes unavailable permissions to the matching macOS privacy pane.
Direct launch-environment values still take precedence for the current process, while the development runner synchronizes them into Keychain without printing them.
Credential fields are read-only while their environment override is active, preventing an empty placeholder from deleting the synchronized Keychain item.
Microphone, Input Monitoring, Screen Recording, and Accessibility can each produce one native prompt when their feature is first enabled; Vhrase does not request optional permissions preemptively.

## Dictate

Choose the provider and Upload or Realtime mode from the compact menu-bar controller or the **Writing** screen.
ElevenLabs uses `scribe_v2` for Upload and `scribe_v2_realtime` for Realtime; these transport-specific models are shown read-only so an unsupported combination cannot be saved.
Start from the menu, the **Home** screen, or the configured global shortcut.
Toggle mode presses once to start and once to stop; Hold mode records while the shortcut is held and processes when it is released.

Vhrase remembers the external app that was active when recording began.
After transcription, it always copies the result and pastes only after Accessibility is available and the recorded target app has been restored and confirmed.
If that target is unavailable, the transcript stays on the clipboard and Vhrase reports why it did not paste.

## Surfaces

- **Floating recorder:** follows the active screen at the bottom edge, shows listening or processing state, and provides explicit cancel and finish controls without taking focus from the target app.
- **Menu bar:** start capture, recover recent transcripts with one-click copy, open History, and switch provider or mode when no workflow is active.
- **Main window toolbar:** exposes the microphone action only; passive workflow status stays in the content surface and floating recorder instead of appearing as a control.
- **Home:** current readiness, latest transcript, and the fastest route to demo, writing, and setup.
- **Writing:** provider tuning, vocabulary, replacements, LLM cleanup, output behavior, and shortcut capture.
- **Setup:** Keychain credentials, macOS permissions, and actionable diagnostics.
- **History:** search, copy, delete, or explicitly confirm clearing saved transcripts.
- **Settings:** compact general defaults, credentials, and permission controls.

Workflow-shaping controls are locked while a recording or transcription is active, and each run keeps its own settings and credential snapshot.

## Cleanup And Chinese Output

Replacement rules and OpenCC `s2hk` normalization run before optional LLM cleanup.
Install `opencc` to normalize Chinese output to Hong Kong Traditional Chinese; when it is unavailable, Vhrase preserves the transcript and shows a warning.
LLM cleanup uses the configured OpenAI-compatible endpoint and can include the recorded target-app identity as context.
Screenshot context is off by default; enabling it captures only the main display, sends that image to the configured cleanup endpoint for the current transcript, and removes the disposable local capture immediately after it is read.
If the LLM call fails, Vhrase uses deterministic local cleanup when that fallback is enabled; otherwise it preserves the raw transcript.

Keyterms are validated against the selected provider and transport before recording can start.
ElevenLabs keyterm prompting carries a 20% usage premium, which the **Writing** screen calls out alongside its batch or realtime limits.

Use **Check model access** in **Writing** to validate the configured LLM model list without running a transcription.
Import and Export move customization settings between machines without including API keys.
Imports accept only regular current-version JSON files up to 1 MiB and validate local settings, provider keyterm limits, and the LLM endpoint before changing anything.
Before persisting an import, Vhrase shows the exact sensitive changes for review when the file changes the LLM endpoint or global shortcut, enables LLM cleanup or screenshot context, or enables automatic paste.

## Local Demo And Audio Smoke

**Run demo** exercises finalization, history, and clipboard output without calling xAI or ElevenLabs or automatically pasting.
`bash scripts/verify.sh` also synthesizes `.cache/audio-smoke/vhrase-smoke.wav` and verifies that it contains mono 16 kHz Int16 PCM without submitting it to a provider.
Live generated-audio and microphone provider commands are documented in [Development](development.md) and consume provider usage only when run explicitly.
