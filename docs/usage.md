# Usage

## Native transcription providers

Select Gemini, xAI (Grok), or ElevenLabs in Transcription → Transcribe, or switch providers directly from Dictate or the menu bar.
Gemini uses `gemini-3.5-transcribe` directly with your `GEMINI_API_KEY`; it uploads the completed recording when you stop and requests `store: false`.
Gemini realtime is not enabled in Vhrase; choosing Gemini switches capture to Upload while retaining realtime support for Grok and ElevenLabs.
All providers read the same Shared vocabulary list, with duplicate lines ignored and provider limits checked before recording.
“Add developer vocabulary” adds a small editable set including Vercel, refactor, backpropagation, and Monte Carlo without removing existing entries.

Gemini Smart transcription removes fillers, applies spoken corrections, and formats text; turn it off when preservation matters more than formatting.
If both Smart and LLM enhancement are enabled, Transcription explains the second cleanup pass and offers “Use Smart only.”
Listen accepts Gemini-specific BCP-47 language hints such as `en-US, yue-Hant-HK`; leave them blank for automatic detection.
Grok's “Keep filler words” and “Format numbers and currency” are independent controls; formatting uses the language in Listen.
For Grok realtime, lowering the speech detection threshold may help quiet speech but can admit background noise; Smart Turn controls turn timing, not text cleanup.

Dictate shows the latest provider transcription alongside the final output and its transcription request time, so you can inspect what later cleanup changed.
This original-text comparison is held only in memory; saved history retains finalized text as before.
Long history entries can be expanded with “Read full transcript.”

## Microphone processing

Transcription → Listen contains the shared audio controls for every provider and mode.
Input device lists physical microphones and excludes virtual audio drivers and temporary aggregate devices; System default follows the Mac's current input, while an explicit choice applies only to Vhrase's preview and dictation.
The choice is saved by stable device identity and included in settings exports; a disconnected selection stays visible and must be replaced before capture can start.
The live microphone preview shows separate microphone-input and after-processing levels while this panel is in the active window, without saving audio, creating a history entry, or contacting a provider.
The taller waveforms smooth level changes for readability without changing the audio itself.
Dragging an audio slider updates the running processor on the next audio chunk without restarting the microphone or resetting its learned noise profile while processing remains enabled.
Choose “Record 5-second test” and then “Play test” to hear the processed microphone audio at your existing playback volume.
The test is held only in memory, discarded when leaving the panel or changing audio settings, and never added to transcript history or sent to an API.
Microphone capture pauses during test playback to prevent feedback and resumes afterward; “Stop playback” ends the test early.
Control changes refresh the preview automatically; leaving the panel, deactivating its window, or starting dictation releases the preview microphone.
Returning to Vhrase resumes the visible preview; clicking Listen again, or Transcription while Listen is already selected, explicitly reacquires the microphone after another app has used it.
Processing applies only to captured microphone samples; Vhrase does not enable Apple's duplex voice-processing mode or control speaker/headphone playback.
Automatic volume leveling is on by default and uses SpeexDSP with a maximum 6 dB automatic boost and gradual gain changes.
Volume adjustment defaults to 0 dB and allows a −6 to +6 dB trim after noise reduction, with PCM saturation protection.
Noise reduction uses the bundled model-free SpeexDSP preprocessor, defaults to a mild −6 dB attenuation limit, and runs from −12 dB on the left to 0 dB (off) on the right.
It targets steady background noise rather than removing other speakers, and never discards audio based on speech detection.
Both uploads and realtime streams receive the same processed 16 kHz mono PCM16 audio; the level meter reflects that processed signal.
Stopping flushes the processor before finalizing, including up to one extra 100 ms chunk for delayed speech.
Settings are saved locally and included in customization exports; older exports receive the new defaults.

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
2. Add xAI and/or ElevenLabs credentials in System, export them directly in `~/.zshrc`, or add them to the ignored `.env` file for prompt-free development builds.
3. Request Microphone access.
4. Grant Accessibility so Vhrase can return finalized text to the originating app; it also enables the global Fn/Globe shortcut.
5. Grant Input Monitoring only if Fn/Globe does not respond reliably, and Screen Recording only when screenshot context is enabled.

The System screen reports saved or environment-backed credentials separately and routes unavailable permissions to the matching macOS privacy pane.
Normal launches prefer saved Keychain values, then use launch-environment values or direct literal exports from `~/.zshrc`, while the development runner skips Keychain and can additionally resolve `.env` values in memory without printing them.
Credential fields remain editable; editing one saves that value to Keychain without opening a password dialog.
If macOS blocks access, Vhrase leaves the saved item protected, uses your edit only for the current session, and shows an unsaved-changes notice with a retry action.
Microphone, Input Monitoring, Screen Recording, and Accessibility can each produce one native prompt when their feature is first enabled. Accessibility covers insertion and normally covers Fn/Globe; Vhrase does not request optional permissions preemptively.

## Dictate

Choose the provider and Upload or Realtime mode from the compact menu-bar controller or **Transcription**.
ElevenLabs uses `scribe_v2` for Upload and `scribe_v2_realtime` for Realtime; these transport-specific models are shown read-only so an unsupported combination cannot be saved.
Start from the menu, **Dictate**, or the configured global shortcut.
Tap the shortcut once to start and once to stop, or hold it to record only until release.
Double-tap the shortcut to polish selected text, or the entire focused editable field when nothing is selected.
Vhrase replaces the source only if the same field, selection, and text remain unchanged while the LLM request is running.

Vhrase remembers the external app that was active when recording began and returns the finalized transcript after restoring and confirming that target.
The Refinement setting controls whether the transcript remains on the clipboard after insertion. When it is off, Vhrase restores the previous clipboard contents after sending the paste command.
If Accessibility or the target app is unavailable, the transcript stays on the clipboard as a safety fallback and Vhrase reports why it did not insert.

## Surfaces

- **Floating recorder:** a small black pill at the bottom of the active screen, with six white audio bars while listening and a progress indicator while processing. Hover or click the waveform to reveal cancel and finish controls without taking focus from the target app. Completion briefly confirms delivery; right-click it to copy again. Errors expand to show the explanation and retry action. Transcript previews remain in Dictate and the menu bar rather than expanding the pill.
- **Menu bar:** start capture, review compact activity stats, open the main window, and switch provider or mode when no workflow is active.
- **Dictate:** current readiness, latest transcript, local activity, and the fastest route to capture or system controls.
- **Transcription:** one stage editor for the global shortcut, listening language, provider tuning, transport mode, and provider keyterms.
- **Refinement:** one page for the LLM model, shared vocabulary, writing preferences, and clipboard delivery.
- **System:** Keychain credentials, macOS permissions, and actionable diagnostics.
- **History:** saved-activity statistics plus searchable, copyable, and removable transcripts.

Workflow-shaping controls are locked while a recording or transcription is active, and each run keeps its own settings and credential snapshot.

## Cleanup And Chinese Output

Shared vocabulary supplies recognition hints and context-sensitive spelling references to LLM polishing; it does not perform automatic text substitutions.
OpenCC `s2hk` normalization runs after optional LLM cleanup.
Install `opencc` to normalize Chinese output to Hong Kong Traditional Chinese; when it is unavailable, Vhrase preserves the transcript and shows a warning.
LLM cleanup uses the configured OpenAI-compatible endpoint and can include the recorded target-app identity as context.
Screenshot context is off by default; enabling it captures only the main display, sends that image to the configured cleanup endpoint for the current transcript, and removes the disposable local capture immediately after it is read.
If the LLM call fails, Vhrase uses deterministic local cleanup when that fallback is enabled; otherwise it preserves the raw transcript.

Keyterms are validated against the selected provider and transport before recording can start.
ElevenLabs keyterm prompting carries a 20% usage premium, which **Transcription** calls out alongside its batch or realtime limits.

Vocabulary can be edited alongside provider options in **Transcription → Transcribe** or writing options in **Refinement**; both edit the same saved list.
Existing replacement-rule targets are migrated into vocabulary on upgrade or customization import.
Refinement defaults to minimal rewriting, removes non-semantic filler words, resolves explicit spoken self-corrections, and preserves sentence flow and paragraph structure.
Every refinement style avoids em dashes; the model uses commas, parentheses, colons, semicolons, or separate sentences instead.
The stepped writing-style slider applies five coordinated levels from Minimal through Polished, with labels beneath each step. Individual options are always visible, and combinations that differ from the presets are shown as Custom.

Use **Check model access** in **Refinement** to send a minimal request through the configured model without running a transcription.
Import and Export move customization settings between machines without including API keys.
Imports accept only regular JSON files up to 1 MiB and validate local settings, provider keyterm limits, and the LLM endpoint before changing anything.
Before persisting an import, Vhrase shows the exact sensitive changes for review when the file changes the LLM endpoint or global shortcut, enables LLM cleanup or screenshot context, or retains finalized text on the clipboard.

## Local Demo And Audio Smoke

**Run demo** exercises finalization, history, and clipboard output without calling xAI or ElevenLabs or automatically pasting.
`bash scripts/verify.sh` also synthesizes `.cache/audio-smoke/vhrase-smoke.wav` and verifies that it contains mono 16 kHz Int16 PCM without submitting it to a provider.
Live generated-audio and microphone provider commands are documented in [Development](development.md) and consume provider usage only when run explicitly.
