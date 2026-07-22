# API Notes

## Credentials

Vhrase stores API keys as macOS Keychain generic-password items under service `Vhrase`, with the environment-variable name as the account name.
A saved Keychain credential takes precedence. A nonempty `XAI_API_KEY`, `ELEVENLABS_API_KEY`, or `LLM_API_KEY` environment value is used only when the matching saved item is empty.
Development launches import nonempty fallbacks only into empty matching Keychain accounts so a later GUI cold launch does not depend on shell-environment inheritance.
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
Screenshot context is off by default and, when explicitly enabled, captures only the main display into a disposable cache directory, sends it as base64 PNG OpenAI-compatible `image_url` content to the configured adjustment endpoint, and removes the complete capture directory immediately afterward.
Configured keyterms are included as preferred vocabulary spellings in the prompt, and replacement rules are applied before the LLM call.

Deterministic checks cover request shapes, ordered realtime accumulation, xAI chunk-final semantics, ElevenLabs multi-commit draining, documented errors, timeout, and cancellation.
Live provider accuracy and service-side behavior still require the explicit generated-audio or microphone smokes in [Development](development.md), which may consume provider usage.

## References

- [xAI Speech to Text](https://docs.x.ai/developers/model-capabilities/audio/speech-to-text)
- [ElevenLabs batch Speech to Text](https://elevenlabs.io/docs/api-reference/speech-to-text/convert)
- [ElevenLabs realtime Speech to Text](https://elevenlabs.io/docs/api-reference/speech-to-text/v-1-speech-to-text-realtime)
- [ElevenLabs realtime transcripts and commit strategies](https://elevenlabs.io/docs/eleven-api/guides/how-to/speech-to-text/realtime/transcripts-and-commit-strategies)
- [ElevenLabs keyterm prompting](https://elevenlabs.io/docs/eleven-api/guides/how-to/speech-to-text/batch/keyterm-prompting)
- [ElevenLabs models](https://elevenlabs.io/docs/overview/models)
