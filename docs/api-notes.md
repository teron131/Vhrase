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

## Credentials

Vhrase stores API keys as macOS Keychain generic-password items under service `Vhrase`, with the environment-variable name as the account name.
A saved Keychain credential takes precedence. A nonempty `XAI_API_KEY`, `ELEVENLABS_API_KEY`, or `LLM_API_KEY` launch-environment value is used next, and a direct literal export from `~/.zshrc` fills any remaining key.
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
Screenshot context is off by default and, when explicitly enabled, captures only the main display into a disposable cache directory, sends it as base64 PNG OpenAI-compatible `image_url` content to the configured adjustment endpoint, and removes the complete capture directory immediately afterward.
Configured keyterms are included as preferred vocabulary spellings in the prompt, and replacement rules are applied before the LLM call.

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
