# Usage

## Native transcription providers

Select Gemini, xAI (Grok), ElevenLabs, OpenAI, or Vercel in Transcription → Transcribe, or switch providers directly from Dictate or the menu bar.
Gemini uses `gemini-3.5-transcribe` directly with your `GEMINI_API_KEY`; it uploads the completed recording when you stop and requests `store: false`.
Gemini realtime is not enabled in Vhrase; choosing Gemini switches capture to Upload while retaining realtime support for Grok and ElevenLabs.
All providers read the same Shared vocabulary list, with duplicate lines ignored and provider limits checked before recording.
“Add developer vocabulary” adds a small editable set including Vercel, refactor, backpropagation, and Monte Carlo without removing existing entries.

Gemini Smart transcription removes fillers, applies spoken corrections, and formats text; turn it off when preservation matters more than formatting.
If both Smart and LLM enhancement are enabled, Transcription explains the second cleanup pass and offers “Use Smart only.”
Listen accepts Gemini-specific BCP-47 language hints such as `en-US, yue-Hant-HK`; leave them blank for automatic detection.
Grok's “Keep filler words” and “Format numbers and currency” are independent controls; formatting uses the language in Listen.
For Grok realtime, lowering the speech detection threshold may help quiet speech but can admit background noise; Smart Turn controls turn timing, not text cleanup.

OpenAI uses `gpt-transcribe` with your `OPENAI_API_KEY`; Shared vocabulary is sent as keyword hints, and the Listen language code, when set, is sent as its language hint.
Vercel sends the recording through Vercel AI Gateway with your `AI_GATEWAY_API_KEY` to the model named in Vercel options, `spacexai/grok-stt` by default; any transcription model in the gateway's catalog works, such as `openai/gpt-transcribe` or `google/gemini-3.5-transcribe`.
The gateway forwards neither Shared vocabulary nor a language hint, so those guide only LLM polishing with Vercel.
OpenAI and Vercel transcribe after you stop; Realtime stays with Grok and ElevenLabs.

Dictate shows the latest provider transcription alongside the final output and its transcription request time, so you can inspect what later cleanup changed.
This original-text comparison is held only in memory; saved history retains finalized text as before.
Long history entries can be expanded with “Read full transcript.”

## On-device Parakeet

Providers are grouped by where they run: **Cloud** (ElevenLabs, Gemini, OpenAI, Vercel, xAI) sends the recording to that provider, while **Local** (Hugging Face, Parakeet) recognizes speech on this Mac; every picker lists them alphabetically.
Select **Parakeet** under Local in Transcription → Transcribe, Dictate, or the menu bar to transcribe on this Mac with NVIDIA Parakeet TDT 0.6B v3 (CC-BY-4.0), run on the Neural Engine through FluidAudio.
It needs no API key; instead, **Download 480 MB** in Parakeet options or the System readiness card fetches the model once from FluidAudio's Hugging Face repository into `~/Library/Application Support/Vhrase/Models`, then Core ML prepares it for this Mac (about 15 seconds the first time).
The download shows progress and can be cancelled; a cancelled or failed download leaves no partial model, and **Retry Download** starts over.
Once downloaded, recognition reads only those files and never uses the network; **Remove** deletes them.

Parakeet transcribes after you stop, so its mode reads **After stop** and Realtime stays disabled.
Vhrase loads the model in the background when Parakeet is selected or a recording starts, and releases it after five idle minutes.
Core ML keeps a compiled copy per app and discards it after macOS updates, so the first load afterwards takes about 15 seconds; a transcription that has to wait shows “Preparing Parakeet for this Mac” in the recorder.
Press Escape or the recorder's cancel control during Parakeet transcription to discard the recording without delivering or saving text; cloud transcriptions keep their existing behavior because the provider has already received the audio.
Parakeet detects among its 25 European languages automatically and ignores the Listen language code; it does not support Chinese or Cantonese, and it does not take Shared vocabulary hints.

Audio never leaves the Mac with Parakeet, but LLM polishing still sends the transcript, and a screenshot when screen context is on, to the configured endpoint.
Parakeet options state which applies and offer **Keep text on this Mac**, which turns automatic polishing off; OpenCC conversion and local cleanup stay on the Mac.

## On-device Hugging Face models

Select **Hugging Face** under Local to transcribe on this Mac with Hugging Face's `transformers` speech recognition pipeline, the same one youtube-toolkit uses.
**Model** offers **Whisper Large v3 Turbo** (`openai/whisper-large-v3-turbo`, OpenAI's fastest large model, 1.6 GB) or **Custom**, which takes any Hugging Face model ID the pipeline accepts, such as `nvidia/parakeet-tdt-0.6b-v3`, `openai/whisper-large-v3`, or a fine-tune for one language.
The pipeline picks the device and precision itself: half precision on the Apple GPU, or full precision on the CPU when there is no GPU; it has no 8-bit mode on a Mac.

These models run in Python, so the Mac needs [uv](https://docs.astral.sh/uv/) (`brew install uv`), which the app looks for in Homebrew's and uv's own install locations.
The first download builds the Python environment, about 1 GB of PyTorch and `transformers` in uv's cache, then fetches the model into `~/Library/Application Support/Vhrase/Models/huggingface/hub` and transcribes a second of silence to prove it runs here.
Download, cancel, retry, and **Remove** work as they do for Parakeet; removing a model deletes its files, while the Python environment stays in uv's cache for other models.
If you are logged in to Hugging Face on this Mac (`hf auth login`), the download uses that login, which is what lets gated models download.

Vhrase starts the Python process in the background when Hugging Face is selected or a recording starts, which takes about seven seconds for Whisper Large v3 Turbo on an Apple M5, and keeps it warm for up to ten idle minutes after the last operation finishes.
If macOS reports elevated memory pressure, Vhrase releases an idle helper immediately; an active request finishes first, then releases its helper if pressure remains elevated.
Background warm-up pauses while memory pressure is elevated, but an explicit transcription can still load the model when needed; normal pressure restores the ten-minute warm period without automatically reloading a model.
The idle timeout, switching to another provider, cancelling inference, removing the model, or quitting Vhrase stops the helper and its children so their model allocations can be released; quitting begins cleanup immediately without waiting for the idle timeout, and a stubborn process is force-stopped after one second.
Downloaded model files and the Python environment remain on disk for reuse, separately from the memory held by a running model.
A seven-second sentence then takes about 0.8 seconds and a 45-second dictation about 3 seconds; Parakeet takes about 0.1 and 0.3 seconds, so Hugging Face is the choice for languages and models Parakeet does not cover.
After the download, recognition reads only local files, and the Hub client runs in offline mode; cancelling a transcription stops the Python process, and the next dictation starts it again.

Whisper models read the Listen language code, such as `en`, `yue`, or `zh`, and detect the language when it is blank; other models detect it themselves and ignore the code.
With `yue`, Whisper Large v3 Turbo wrote a Cantonese sample in Cantonese wording; with detection it wrote the same sample as standard written Chinese.
Hugging Face models do not take Shared vocabulary hints.
Whisper models also cannot tell that a recording holds no speech and return a short phrase such as “Thank you.” for silence; Vhrase's recording-level check stops silent recordings before recognition, but a recording of only clicks or background noise can still produce such a phrase.
On audio it cannot make sense of, Whisper can also repeat one word until its output limit, which took about ten seconds on a garbled test clip; press Escape to cancel.

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
2. Add the credential for each cloud provider you use in System, export it directly in `~/.zshrc`, or add it to the ignored `.env` file for prompt-free development builds; Parakeet and Hugging Face instead need their one-time model download.
3. Request Microphone access.
4. Grant Accessibility so Vhrase can return finalized text to the originating app; it also enables the global Fn/Globe shortcut.
5. Grant Input Monitoring only if Fn/Globe does not respond reliably, and Screen Recording only when screenshot context is enabled.
6. In **Transcription → Transcribe → Transcription test**, choose **Record test** and speak a short phrase; recording stops after five seconds, or choose **Stop and transcribe** sooner.

The test uses your selected provider, mode, language, and vocabulary, and shows the raw recognized text with a **Copy** action.
It does not polish, paste, add History entries, or change activity totals; cloud providers receive the test audio and bill it as ordinary transcription, while local tests stay on the Mac.
**Cancel**, leaving the stage, or deactivating its window stops the test and discards its temporary audio.

The System screen shows whether each credential is saved, loaded from the environment, or missing beside its field, and each permission row offers the next step: a native request while macOS still allows one, otherwise the matching privacy pane.
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

- **Floating recorder:** a small black pill at the bottom of the active screen, with white audio bars that stream from right to left while listening and a progress indicator while processing. The bars scale to your recent speaking level, and sound far below it stays a dot, so a quiet microphone still shows tall bars while room noise does not; the live microphone preview in Transcription → Listen shows absolute levels. Hover or click the waveform to reveal cancel and finish controls without taking focus from the target app. Completion briefly confirms delivery; right-click it to copy again. Errors expand to show the explanation and retry action. Transcript previews remain in Dictate and the menu bar rather than expanding the pill.
- **Menu bar:** start capture, review compact activity stats, open the main window, and switch provider or mode when no workflow is active.
- **Dictate:** a mic bar holds the record button, a signal that rests as quiet dots and shows the live microphone level while recording, and a provider and mode menu; its fill turns orange when ready, red while listening, and violet while Vhrase works. The latest transcript and its pre-cleanup original appear in a speech bubble from the parrot, and activity totals below double as tiles that choose which total the chart plots.
- **Transcription:** one stage editor for the global shortcut, listening language, provider tuning, transport mode, and provider keyterms.
- **Refinement:** one page for the LLM model, shared vocabulary, writing preferences, and clipboard delivery.
- **System:** Keychain credentials in two groups, **Transcription** for each speech provider's key and **LLM** for the OpenAI-compatible key and endpoint that cleanup uses, plus macOS permissions, actionable diagnostics, and the **Theme** choice of System, Light, or Dark; System follows macOS, and the recorder pill stays dark in all three.
- **History:** saved-activity statistics plus searchable, copyable, and removable transcripts, each shown with its time, provider, and destination app.

Workflow-shaping controls are locked while a recording or transcription is active, and each run keeps its own settings and credential snapshot.

## Cleanup And Chinese Output

Shared vocabulary supplies recognition hints and context-sensitive spelling references to LLM polishing; it does not perform automatic text substitutions.
OpenCC `s2hk` normalization runs after optional LLM cleanup.
Install `opencc` to normalize Chinese output to Hong Kong Traditional Chinese; when it is unavailable, Vhrase preserves the transcript and shows a warning.
LLM cleanup uses the configured OpenAI-compatible endpoint and can include the recorded target-app identity as context.
Screenshot context is off by default; enabling it captures the display showing the app you are dictating into (the main display when that app has no visible window), sends that image to the configured cleanup endpoint for the current transcript, and removes the disposable local capture immediately after it is read.
Screenshot size in Refinement trades speed for legibility: smaller images reach the model sooner, while small text and unusual names blur, noticeably from about 1280 pixels down; the preview beside the slider simulates the effect on standard macOS text.
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
