# Usage

## Run The App

Build and open the signed app bundle:

```sh
bash scripts/ensure-local-codesign-identity.sh
./scripts/build-and-run.sh
```

Run the identity command once per development machine; it is idempotent and may request one Keychain or trust authorization while creating `Vhrase Local Development`.
Subsequent builds reuse that identity so macOS recognizes Vhrase as the same app instead of repeatedly asking for credential or privacy access.
The run script stops stale Vhrase processes, rebuilds and signs the bundle, and adds a waveform icon to the menu bar. Vhrase opens the main window once on first launch; later launches stay in the menu bar until you open the main window from its controls.
Use the bundle for normal operation so macOS associates privacy permissions with the app instead of Terminal.

## First Setup

1. Open **System** in the sidebar.
2. Add xAI and/or ElevenLabs credentials in System for normal Finder launches, or add them to the ignored `.env` file for prompt-free development builds.
3. Request Microphone access.
4. Grant Accessibility so Vhrase can return finalized text to the originating app; it also enables the global Fn/Globe shortcut.
5. Grant Input Monitoring only if Fn/Globe does not respond reliably, and Screen Recording only when screenshot context is enabled.

The System screen reports saved or environment-backed credentials separately and routes unavailable permissions to the matching macOS privacy pane.
Normal launches prefer saved Keychain values, while the development runner skips Keychain and resolves shell or `.env` values in memory without printing them.
Credential fields remain editable; editing one explicitly saves that value to Keychain.
Microphone, Input Monitoring, Screen Recording, and Accessibility can each produce one native prompt when their feature is first enabled. Accessibility covers insertion and normally covers Fn/Globe; Vhrase does not request optional permissions preemptively.

## Dictate

Choose the provider and Upload or Realtime mode from the compact menu-bar controller or **Capture**.
ElevenLabs uses `scribe_v2` for Upload and `scribe_v2_realtime` for Realtime; these transport-specific models are shown read-only so an unsupported combination cannot be saved.
Start from the menu, **Dictate**, or the configured global shortcut.
Toggle mode presses once to start and once to stop; Hold mode records while the shortcut is held and processes when it is released.

Vhrase remembers the external app that was active when recording began and returns the finalized transcript after restoring and confirming that target.
The Output setting controls whether the transcript remains on the clipboard after insertion. When it is off, Vhrase restores the previous clipboard contents after sending the paste command.
If Accessibility or the target app is unavailable, the transcript stays on the clipboard as a safety fallback and Vhrase reports why it did not insert.

## Surfaces

- **Floating recorder:** follows the active screen at the bottom edge, shows listening or processing state, and provides explicit cancel and finish controls without taking focus from the target app.
- **Menu bar:** start capture, review compact activity stats, open the main window, and switch provider or mode when no workflow is active.
- **Dictate:** current readiness, latest transcript, local activity, and the fastest route to capture or system controls.
- **Capture:** one stage editor for the global shortcut, listening language, provider tuning, transport mode, and provider keyterms.
- **Output:** one stage editor for exact replacements, optional LLM enhancement, delivery, and history saving.
- **System:** Keychain credentials, macOS permissions, and actionable diagnostics.
- **History:** saved-activity statistics plus searchable, copyable, and removable transcripts.

Workflow-shaping controls are locked while a recording or transcription is active, and each run keeps its own settings and credential snapshot.

## Cleanup And Chinese Output

Replacement rules and OpenCC `s2hk` normalization run before optional LLM cleanup.
Install `opencc` to normalize Chinese output to Hong Kong Traditional Chinese; when it is unavailable, Vhrase preserves the transcript and shows a warning.
LLM cleanup uses the configured OpenAI-compatible endpoint and can include the recorded target-app identity as context.
Screenshot context is off by default; enabling it captures only the main display, sends that image to the configured cleanup endpoint for the current transcript, and removes the disposable local capture immediately after it is read.
If the LLM call fails, Vhrase uses deterministic local cleanup when that fallback is enabled; otherwise it preserves the raw transcript.

Keyterms are validated against the selected provider and transport before recording can start.
ElevenLabs keyterm prompting carries a 20% usage premium, which **Capture** calls out alongside its batch or realtime limits.

Use **Check model access** in **Output** to send a minimal request through the configured model without running a transcription.
Import and Export move customization settings between machines without including API keys.
Imports accept only regular JSON files up to 1 MiB and validate local settings, provider keyterm limits, and the LLM endpoint before changing anything.
Before persisting an import, Vhrase shows the exact sensitive changes for review when the file changes the LLM endpoint or global shortcut, enables LLM cleanup or screenshot context, or retains finalized text on the clipboard.

## Local Demo And Audio Smoke

**Run demo** exercises finalization, history, and clipboard output without calling xAI or ElevenLabs or automatically pasting.
`bash scripts/verify.sh` also synthesizes `.cache/audio-smoke/vhrase-smoke.wav` and verifies that it contains mono 16 kHz Int16 PCM without submitting it to a provider.
Live generated-audio and microphone provider commands are documented in [Development](development.md) and consume provider usage only when run explicitly.
