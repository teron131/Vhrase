// Builds and validates provider-specific upload and realtime transcription parameters.

import Foundation

/// Enforces provider limits before recording starts and again at each request boundary.
enum TranscriptionContract {
  static func validate(settings: DictationSettings) throws {
    try settings.validateLocalConfiguration()
    _ = try validatedKeyterms(
      settings.keytermList,
      provider: settings.provider,
      mode: settings.transcriptionMode
    )
  }

  /// Describes the first limit that would block recording, or returns `nil` for usable settings.
  static func configurationIssue(in settings: DictationSettings) -> String? {
    do {
      try validate(settings: settings)
      return nil
    } catch {
      return error.localizedDescription
    }
  }

  fileprivate static func validatedKeyterms(
    _ keyterms: [String],
    provider: STTProvider,
    mode: TranscriptionMode
  ) throws -> [String] {
    let policy = keytermPolicy(provider: provider, mode: mode)
    guard keyterms.count <= policy.maximumCount else {
      throw TranscriptionContractError.tooManyKeyterms(
        provider: provider,
        mode: mode,
        maximum: policy.maximumCount,
        actual: keyterms.count
      )
    }

    for (offset, keyterm) in keyterms.enumerated() {
      let position = offset + 1
      let characterCount = keyterm.count
      let isTooLong =
        policy.characterLimitIsExclusive
        ? characterCount >= policy.characterLimit
        : characterCount > policy.characterLimit
      if isTooLong {
        throw TranscriptionContractError.keytermTooLong(
          provider: provider,
          mode: mode,
          position: position,
          limit: policy.characterLimit,
          isExclusive: policy.characterLimitIsExclusive,
          actual: characterCount
        )
      }

      if let maximumWords = policy.maximumWords {
        let wordCount = keyterm.split(whereSeparator: \.isWhitespace).count
        if wordCount > maximumWords {
          throw TranscriptionContractError.tooManyWords(
            provider: provider,
            mode: mode,
            position: position,
            maximum: maximumWords,
            actual: wordCount
          )
        }
      }

      if let unsupportedCharacter = keyterm.first(where: {
        policy.unsupportedCharacters.contains($0)
      }) {
        throw TranscriptionContractError.unsupportedCharacter(
          provider: provider,
          mode: mode,
          position: position,
          character: unsupportedCharacter
        )
      }
    }

    return keyterms
  }

  private static func keytermPolicy(
    provider: STTProvider,
    mode: TranscriptionMode
  ) -> KeytermPolicy {
    switch (provider, mode) {
    case (.xai, _):
      KeytermPolicy(maximumCount: 100, characterLimit: 50)
    case (.gemini, _):
      KeytermPolicy(maximumCount: 1_000, characterLimit: Int.max)
    case (.elevenLabs, .upload):
      KeytermPolicy(
        maximumCount: 1_000,
        characterLimit: 50,
        characterLimitIsExclusive: true,
        maximumWords: 5,
        unsupportedCharacters: ["<", ">", "{", "}", "[", "]", "\\"]
      )
    case (.elevenLabs, .realtime):
      KeytermPolicy(maximumCount: 50, characterLimit: 20)
    }
  }
}

/// Owns Gemini's native Interactions schema; vocabulary and Smart mode never pass through a gateway.
enum GeminiTranscriptionContract {
  static let modelID = "gemini-3.5-transcribe"

  static func requestBody(audio: Data, settings: DictationSettings) throws -> Data {
    try TranscriptionContract.validate(settings: settings)
    let terms = try TranscriptionContract.validatedKeyterms(
      settings.keytermList, provider: .gemini, mode: .upload)
    let languageCodes = settings.geminiLanguageCodes
    var config: [String: Any] = [
      "mode": settings.geminiSmartTranscription
        ? "smart" as Any : ["type": "verbatim"] as Any
    ]
    if !terms.isEmpty { config["custom_vocabulary"] = terms }
    if !languageCodes.isEmpty {
      config["language_codes"] = languageCodes
    }
    return try JSONSerialization.data(withJSONObject: [
      "model": modelID,
      "input": [["type": "audio", "data": audio.base64EncodedString(), "mime_type": "audio/wav"]],
      "generation_config": ["transcription_config": config],
      "store": false,
    ])
  }
}

enum TranscriptionContractError: LocalizedError, Equatable {
  case tooManyKeyterms(
    provider: STTProvider,
    mode: TranscriptionMode,
    maximum: Int,
    actual: Int
  )
  case keytermTooLong(
    provider: STTProvider,
    mode: TranscriptionMode,
    position: Int,
    limit: Int,
    isExclusive: Bool,
    actual: Int
  )
  case tooManyWords(
    provider: STTProvider,
    mode: TranscriptionMode,
    position: Int,
    maximum: Int,
    actual: Int
  )
  case unsupportedCharacter(
    provider: STTProvider,
    mode: TranscriptionMode,
    position: Int,
    character: Character
  )

  var errorDescription: String? {
    switch self {
    case .tooManyKeyterms(let provider, let mode, let maximum, let actual):
      return
        "\(label(provider: provider, mode: mode)) supports at most \(maximum) keyterms; found \(actual)."
    case .keytermTooLong(
      let provider, let mode, let position, let limit, let isExclusive, let actual):
      let requirement = isExclusive ? "fewer than \(limit)" : "at most \(limit)"
      return
        "\(label(provider: provider, mode: mode)) keyterm \(position) must contain \(requirement) characters; found \(actual)."
    case .tooManyWords(let provider, let mode, let position, let maximum, let actual):
      return
        "\(label(provider: provider, mode: mode)) keyterm \(position) supports at most \(maximum) words; found \(actual)."
    case .unsupportedCharacter(let provider, let mode, let position, let character):
      return
        "\(label(provider: provider, mode: mode)) keyterm \(position) contains unsupported character '\(character)'."
    }
  }

  private func label(
    provider: STTProvider,
    mode: TranscriptionMode
  ) -> String {
    "\(provider.title) \(mode.title.lowercased())"
  }
}

private struct KeytermPolicy {
  let maximumCount: Int
  let characterLimit: Int
  var characterLimitIsExclusive = false
  var maximumWords: Int?
  var unsupportedCharacters: Set<Character> = []
}

/// Builds xAI request fields and query items from normalized Vhrase settings.
enum XAITranscriptionContract {
  static func uploadFields(settings: DictationSettings) throws -> [(String, String)] {
    try settings.validateLocalConfiguration()
    let keyterms = try TranscriptionContract.validatedKeyterms(
      settings.keytermList,
      provider: .xai,
      mode: .upload
    )
    var fields: [(String, String)] = [
      ("filler_words", settings.includeFillerWords ? "true" : "false")
    ]
    let language = settings.language.trimmingCharacters(in: .whitespacesAndNewlines)
    if settings.xaiFormatText, !language.isEmpty {
      fields.insert(
        contentsOf: [
          ("format", "true"),
          ("language", language),
        ], at: 0)
    }
    fields += keyterms.map { ("keyterm", $0) }
    return fields
  }

  static func realtimeQueryItems(settings: DictationSettings) throws -> [URLQueryItem] {
    try settings.validateLocalConfiguration()
    let keyterms = try TranscriptionContract.validatedKeyterms(
      settings.keytermList,
      provider: .xai,
      mode: .realtime
    )
    let language = settings.language.trimmingCharacters(in: .whitespacesAndNewlines)
    var queryItems = [
      URLQueryItem(name: "sample_rate", value: "16000"),
      URLQueryItem(name: "encoding", value: "pcm"),
      URLQueryItem(name: "interim_results", value: "true"),
      URLQueryItem(name: "filler_words", value: settings.includeFillerWords ? "true" : "false"),
      URLQueryItem(name: "endpointing", value: String(settings.xaiRealtimeEndpointing)),
      URLQueryItem(name: "vad_threshold", value: String(settings.xaiVADThreshold)),
    ]
    if settings.xaiSmartTurnEnabled {
      queryItems.append(
        URLQueryItem(name: "smart_turn", value: String(settings.xaiSmartTurnThreshold)))
      queryItems.append(
        URLQueryItem(name: "smart_turn_timeout", value: String(settings.xaiSmartTurnTimeout)))
    }
    if settings.xaiFormatText, !language.isEmpty {
      queryItems.append(URLQueryItem(name: "language", value: language))
    }
    queryItems += keyterms.map { URLQueryItem(name: "keyterm", value: $0) }
    return queryItems
  }
}

/// Builds ElevenLabs requests with the fixed models supported by each transport.
enum ElevenLabsTranscriptionContract {
  static let uploadModelID = "scribe_v2"
  static let realtimeModelID = "scribe_v2_realtime"

  static func uploadFields(settings: DictationSettings) throws -> [(String, String)] {
    try settings.validateLocalConfiguration()
    let keyterms = try TranscriptionContract.validatedKeyterms(
      settings.keytermList,
      provider: .elevenLabs,
      mode: .upload
    )
    let language = settings.language.trimmingCharacters(in: .whitespacesAndNewlines)
    var fields: [(String, String)] = [
      ("model_id", uploadModelID),
      ("no_verbatim", settings.elevenLabsNoVerbatim ? "true" : "false"),
    ]
    if !language.isEmpty {
      fields.append(("language_code", language))
    }
    fields += keyterms.map { ("keyterms", $0) }
    return fields
  }

  static func realtimeQueryItems(settings: DictationSettings) throws -> [URLQueryItem] {
    try settings.validateLocalConfiguration()
    let keyterms = try TranscriptionContract.validatedKeyterms(
      settings.keytermList,
      provider: .elevenLabs,
      mode: .realtime
    )
    let language = settings.language.trimmingCharacters(in: .whitespacesAndNewlines)
    var queryItems = [
      URLQueryItem(name: "model_id", value: realtimeModelID),
      URLQueryItem(name: "audio_format", value: "pcm_16000"),
      URLQueryItem(name: "commit_strategy", value: settings.elevenLabsCommitStrategy.rawValue),
      URLQueryItem(name: "no_verbatim", value: settings.elevenLabsNoVerbatim ? "true" : "false"),
      URLQueryItem(
        name: "vad_silence_threshold_secs", value: String(settings.elevenLabsVADSilenceThreshold)),
      URLQueryItem(name: "vad_threshold", value: String(settings.elevenLabsVADThreshold)),
      URLQueryItem(
        name: "min_speech_duration_ms", value: String(settings.elevenLabsMinSpeechDuration)),
      URLQueryItem(
        name: "min_silence_duration_ms", value: String(settings.elevenLabsMinSilenceDuration)),
    ]
    if !language.isEmpty {
      queryItems.append(URLQueryItem(name: "language_code", value: language))
    }
    queryItems += keyterms.map { URLQueryItem(name: "keyterms", value: $0) }
    return queryItems
  }
}
