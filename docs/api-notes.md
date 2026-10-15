# API Notes

## Gemini native transcription

`GeminiTranscriptionContract` builds `POST https://generativelanguage.googleapis.com/v1beta/interactions` with `x-goog-api-key`, inline WAV audio, the fixed `gemini-3.5-transcribe` model, and `store: false`.
Shared vocabulary maps to `generation_config.transcription_config.custom_vocabulary`; Gemini language hints map to `language_codes`.
Smart mode maps to `mode: "smart"`, while verbatim uses `mode: {"type":"verbatim"}`.
The adapter accepts only completed responses and joins text blocks from `model_output` steps before the existing finalization pipeline runs.
Requests have a 90-second timeout and no client retry; vocabulary is limited to 1,000 unique terms.
Gemini's streaming endpoint, diarization, and word timestamps are deliberately not exposed in this version.

Grok retains native `POST /v1/stt` and WebSocket transcription.
Its shared vocabulary maps to repeated `keyterm` values; filler retention maps to `filler_words`.
`xaiFormatText` gates both `format=true` and the language field for upload, and the formatting-enabling language query for realtime.
`xaiVADThreshold` maps to realtime `vad_threshold` and defaults to the provider's 0.08.

References: [Gemini transcription](https://ai.google.dev/gemini-api/docs/transcribe), [Grok speech to text](https://docs.x.ai/developers/model-capabilities/audio/speech-to-text).

## OpenAI and Vercel AI Gateway transcription

`OpenAITranscriptionContract` builds `POST https://api.openai.com/v1/audio/transcriptions` as a multipart upload with bearer auth and the fixed `gpt-transcribe` model.
Shared vocabulary maps to repeated `keywords[]` fields and the Listen language code to one `languages[]` field; both are specific to `gpt-transcribe`, which rejects the singular `language` field alongside `languages`, so the model is not editable.
OpenAI documents no keyword count or length limit but rejects a request whose keyword contains `<` or `>`, which Vhrase checks before recording; uploads are limited to 25 MB, about 13 minutes of Vhrase's 16 kHz mono WAV.

`VercelTranscriptionContract` builds `POST https://ai-gateway.vercel.sh/v4/ai/transcription-model` with bearer auth, the protocol headers `ai-gateway-protocol-version: 0.0.1` and `ai-transcription-model-specification-version: 4`, and the model in `ai-model-id`.
The gateway accepts no file upload, so the body is JSON with base64 `audio` and `mediaType: "audio/wav"`, and the response carries the transcript in `text`.
`vercelModel` defaults to `spacexai/grok-stt` and accepts any transcription model in the gateway's catalog; Vhrase sends no provider options, so vocabulary and language hints do not reach the model.
Both adapters use a 60-second timeout and no client retry.

References: [OpenAI speech to text](https://developers.openai.com/api/docs/guides/speech-to-text), [Vercel AI Gateway speech to text](https://vercel.com/docs/ai-gateway/modalities/speech-to-text).

## Parakeet on-device transcription

`ParakeetRecognizer` runs FluidAudio 0.17.1's `AsrManager` with `AsrModelVersion.v3`, NVIDIA Parakeet TDT 0.6B v3 converted to Core ML by FluidInference.
`OnDeviceModelStore` owns the setup state both on-device providers share, and `ParakeetModel` calls `AsrModels.download(to:force:version:)` only when the user asks; FluidAudio lists `FluidInference/parakeet-tdt-0.6b-v3-coreml` on Hugging Face, downloads the preprocessor, int8 encoder, decoder, `JointDecisionv3`, and vocabulary (about 480 MB), and compiles them with Core ML.
FluidAudio reads that repository's `main` branch rather than a pinned commit; it ships fixes under new file names instead of replacing published files, and it sends a Hugging Face token only from `HF_TOKEN`-style environment variables.
Vhrase writes a completion marker after the download finishes, so an interrupted folder is replaced rather than loaded.
Recognition uses `AsrModels.loadLocal(from:)`, which reads only the downloaded folder and fails instead of downloading, and passes the recorded WAV to `AsrManager.transcribe(_:decoderState:)` without a language hint.
`OnDeviceModelStore.prepare()` performs the same local load in the background when Parakeet becomes the selected provider, because Core ML compiles the model once per app and again after macOS updates.
Task cancellation stops at FluidAudio's chunk boundaries and surfaces as `CancellationError`.

References: [FluidAudio](https://github.com/FluidInference/FluidAudio), [Parakeet TDT 0.6B v3 Core ML](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml), [NVIDIA Parakeet TDT 0.6B v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3).

## Hugging Face on-device transcription

`HuggingFaceRecognizer` runs models through `Transcription/OnDevice/HuggingFaceRuntime/asr.py`, a Python script that builds the `transformers` `automatic-speech-recognition` pipeline the way youtube-toolkit's local route does: the first available of an Nvidia GPU, the Apple GPU, and the CPU, at half precision on a GPU and full precision on the CPU.
`HuggingFaceRuntime` starts the script with `uv run --script`, so uv builds the environment from the script's inline dependencies (`torch`, `transformers`, `librosa`, `numpy`, `huggingface-hub`) pinned by `asr.py.lock`, and reuses it afterwards; the app links no Python and no Swift package for this.
The script and its lockfile ship in the SwiftPM resource bundle, and uv is looked up in `/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`, and `~/.cargo/bin`, because an app launched from Finder inherits no shell path.
Before each start Vhrase copies both files to `Models/huggingface/runtime` when they differ and runs them from there, because uv keys an environment to the script's path: run from inside the app bundle, every rebuilt or moved app built a new 1 GB environment, which took 45 to 60 seconds even from uv's own cache.

The helper's Hub cache is `HF_HUB_CACHE=~/Library/Application Support/Vhrase/Models/huggingface/hub`, separate from `~/.cache/huggingface/hub`, with `HF_HUB_DISABLE_SHARED_BLOBS=1` so each model's files stay inside its own `models--owner--name` folder and deleting that folder frees them.
`HuggingFaceModelReference` validates the `huggingFaceModel` setting against the Hub's naming rules before it becomes that folder name; `trust_remote_code` stays off, so a model that needs its own Python code fails to load instead of running it.
`asr.py download MODEL` builds the pipeline, which lets `transformers` fetch exactly the files it needs, reports progress as cached bytes over an estimate from the repository's file list, transcribes one second of silence, and ends with an `installed` or `error` JSON line; Vhrase then writes the completion marker, and a failed or cancelled download removes the model's folder.
`asr.py serve` runs with `HF_HUB_OFFLINE=1`, keeps the last requested model loaded, and answers one JSON request per line for `load` and `transcribe`; it exits when its standard input closes, which is how Vhrase stops it and how it notices the app is gone.
Recordings longer than 28 seconds are cut at the quietest point before each limit and transcribed piece by piece, as in youtube-toolkit, because the pipeline's own chunking repeats text for Parakeet and Whisper refuses longer audio without it.
The Listen language code is passed as `generate_kwargs.language` only to multilingual Whisper models; no vocabulary reaches any model.
Cancelling a request or exceeding the ten-minute request limit terminates uv, which forwards the signal to Python; the recognizer then starts a fresh server on the next request.
Whisper's temperature fallback is not enabled: in `transformers` 5.19 it raised an internal error on a degenerate clip and did not stop silence from returning “Thank you.”.

References: [transformers ASR pipeline](https://huggingface.co/docs/transformers/main_classes/pipelines#transformers.AutomaticSpeechRecognitionPipeline), [uv scripts](https://docs.astral.sh/uv/guides/scripts/), [OpenAI Whisper large-v3-turbo](https://huggingface.co/openai/whisper-large-v3-turbo).

## Credentials

Vhrase stores API keys as macOS Keychain generic-password items under service `Vhrase`, with the environment-variable name as the account name.
A saved Keychain credential takes precedence. A nonempty `XAI_API_KEY`, `ELEVENLABS_API_KEY`, `GEMINI_API_KEY`, `OPENAI_API_KEY`, `AI_GATEWAY_API_KEY`, or `LLM_API_KEY` launch-environment value is used next, and a direct literal export from `~/.zshrc` fills any remaining key.
Development launches additionally resolve ignored `.env` fallbacks in memory without reading or modifying Keychain.
Credential fields always edit the saved Keychain value; clearing one reveals the environment fallback when it exists.

## Speech-To-Text

- xAI upload STT uses `POST https://api.x.ai/v1/stt` with multipart audio upload.
- ElevenLabs upload STT uses `POST https://api.elevenlabs.io/v1/speech-to-text` with the fixed `scribe_v2` model.
- xAI realtime uses `wss://api.x.ai/v1/stt`, waits for `transcript.created`, sends raw 16 kHz PCM in exact 3,200-byte (100 ms) binary frames, pads the final frame with silence, and finishes with `audio.done`.
- xAI chunk-final `is_final` text remains replaceable until `speech_final` commits the complete utterance, preventing cumulative partials from being duplicated.
- ElevenLabs realtime uses `wss://api.elevenlabs.io/v1/speech-to-text/realtime` with the fixed `scribe_v2_realtime` model, base64 `input_audio_chunk` messages, and an empty-audio commit when manual recording finishes.

ElevenLabs model identifiers are intentionally not editable because its batch and realtime transports require different current models.
Provider-specific validation runs before a request: xAI allows up to 100 keyterms of at most 50 characters, ElevenLabs upload allows up to 1,000 keyterms of fewer than 50 characters and at most five words, and ElevenLabs realtime allows up to 50 keyterms of at most 20 characters.
ElevenLabs charges a 20% premium when keyterm prompting is used, so Vhrase surfaces that tradeoff beside the setting.

## LLM Adjustment

LLM adjustment uses `POST {adjustmentBaseURL}/chat/completions`.
The default base URL is `https://ai-gateway.vercel.sh/v1`, and the saved LLM API key uses the `LLM_API_KEY` Keychain account.
Every LLM completion request fixes `reasoning_effort` to `low`, including the model-access check.
Screenshot context is off by default and, when explicitly enabled, captures the display under the target app's frontmost on-screen window, or the main display when no such window is found, into a disposable cache directory, downsizes its longest side to the chosen Screenshot size (1024 to 2560 pixels, 1600 by default, or the original capture), sends it as base64 JPEG OpenAI-compatible `image_url` content to the configured adjustment endpoint, and removes the complete capture directory immediately afterward.
The request still asks for `high` detail, but Vercel AI Gateway does not forward that hint, and OpenAI then reads an image at its original size; the local downsizing is what bounds the cost, to about 2,000 prompt tokens for a 16:10 display instead of about 9,000 for a 3420×2214 Retina capture.
The shared vocabulary is included in the LLM prompt as reference spellings to use only when supported by the source context; Vhrase does not force vocabulary terms into the text or apply literal replacement rules.

Automatic transcript cleanup and double-tap editor polishing share `PolishPreferences.systemInstruction`.
Writing preferences, vocabulary, and additional instructions are sent in a system message; source text, application context, and any screenshot stay in the user message.
The Natural default uses adaptive formatting and natural rewriting, sentence breaks, and paragraph structure.
Reset restores only the writing preferences, preserving custom instructions, provider settings, model configuration, and credentials.
Older settings and customization exports receive default writing preferences, and the previous built-in prompt is removed from the custom-instructions field while user-authored instructions are retained.

Deterministic checks cover request shapes, ordered realtime accumulation, xAI chunk-final semantics, ElevenLabs multi-commit draining, documented errors, timeout, and cancellation.
Live provider accuracy and service-side behavior still require the explicit generated-audio or microphone smokes in [Development](development.md), which may consume provider usage.

## References

- [xAI Speech to Text](https://docs.x.ai/developers/model-capabilities/audio/speech-to-text)
- [ElevenLabs batch Speech to Text](https://elevenlabs.io/docs/api-reference/speech-to-text/convert)
- [ElevenLabs realtime Speech to Text](https://elevenlabs.io/docs/api-reference/speech-to-text/v-1-speech-to-text-realtime)
- [ElevenLabs realtime transcripts and commit strategies](https://elevenlabs.io/docs/eleven-api/guides/how-to/speech-to-text/realtime/transcripts-and-commit-strategies)
- [ElevenLabs keyterm prompting](https://elevenlabs.io/docs/eleven-api/guides/how-to/speech-to-text/batch/keyterm-prompting)
- [ElevenLabs models](https://elevenlabs.io/docs/overview/models)
