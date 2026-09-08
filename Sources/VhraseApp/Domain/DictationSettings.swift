// Owns persistent dictation preferences and the provider capabilities that constrain capture and cleanup.

import Foundation

enum STTProvider: String, CaseIterable, Codable, Identifiable, Sendable {
  case xai
  case elevenLabs
  case gemini

  var id: String { rawValue }

  var title: String {
    switch self {
    case .xai:
      "xAI"
    case .elevenLabs:
      "ElevenLabs"
    case .gemini:
      "Gemini"
    }
  }

  var availableModes: [TranscriptionMode] {
    self == .gemini ? [.upload] : TranscriptionMode.allCases
  }

  var detail: String {
    switch self {
    case .xai: "Grok speech recognition with vocabulary hints and optional filler removal."
    case .elevenLabs: "Scribe speech recognition with vocabulary hints and verbatim controls."
    case .gemini: "Gemini 3.5 Transcribe with vocabulary hints and optional Smart transcription."
    }
  }
}

enum TranscriptionMode: String, CaseIterable, Codable, Identifiable, Sendable {
  case upload
  case realtime

  var id: String { rawValue }

  var title: String {
    switch self {
    case .upload:
      "Upload"
    case .realtime:
      "Realtime"
    }
  }
}

enum ElevenLabsCommitStrategy: String, CaseIterable, Codable, Identifiable, Sendable {
  case manual
  case vad

  var id: String { rawValue }

  var title: String {
    switch self {
    case .manual:
      "Manual"
    case .vad:
      "VAD"
    }
  }
}

struct DictationSettings: Codable, Equatable, Sendable {
  var provider: STTProvider
  var transcriptionMode: TranscriptionMode
  var elevenLabsCommitStrategy: ElevenLabsCommitStrategy
  var elevenLabsNoVerbatim: Bool
  var elevenLabsVADSilenceThreshold: Double
  var elevenLabsVADThreshold: Double
  var elevenLabsMinSpeechDuration: Int
  var elevenLabsMinSilenceDuration: Int
  var language: String
  var keyterms: String
  var replacementRules: String
  var includeFillerWords: Bool
  var xaiRealtimeEndpointing: Int
  var xaiSmartTurnEnabled: Bool
  var xaiSmartTurnThreshold: Double
  var xaiSmartTurnTimeout: Int
  var keepTranscriptOnClipboard: Bool
  var adjustWithLLM: Bool
  var useLocalAdjustmentFallback: Bool
  var adjustmentBaseURL: String
  var adjustmentModel: String
  var adjustmentPrompt: String
  var includeScreenshot: Bool
  var hotkeyPreset: HotkeyPreset
  var customHotkey: CustomHotkey?
  var shortcutBehavior: ShortcutBehavior
  var geminiSmartTranscription: Bool = true
  var geminiLanguageHints: String = ""
  var xaiFormatText: Bool = true
  var xaiVADThreshold: Double = 0.08

  static let defaultAdjustmentPrompt = """
    Rewrite the transcript into polished text that is ready to insert into the active app. Fix obvious speech-to-text mistakes, punctuation, casing, and awkward phrasing while preserving intent. Use the screenshot only as context. Return only the final text.
    """

  static let defaults = DictationSettings(
    provider: .xai,
    transcriptionMode: .upload,
    elevenLabsCommitStrategy: .manual,
    elevenLabsNoVerbatim: false,
    elevenLabsVADSilenceThreshold: 1.5,
    elevenLabsVADThreshold: 0.4,
    elevenLabsMinSpeechDuration: 100,
    elevenLabsMinSilenceDuration: 100,
    language: "en",
    keyterms: "",
    replacementRules: "",
    includeFillerWords: false,
    xaiRealtimeEndpointing: 500,
    xaiSmartTurnEnabled: false,
    xaiSmartTurnThreshold: 0.5,
    xaiSmartTurnTimeout: 1500,
    keepTranscriptOnClipboard: false,
    adjustWithLLM: true,
    useLocalAdjustmentFallback: true,
    adjustmentBaseURL: "https://ai-gateway.vercel.sh/v1",
    adjustmentModel: "xai/grok-4.3",
    adjustmentPrompt: defaultAdjustmentPrompt,
    includeScreenshot: false,
    hotkeyPreset: .controlOptionSpace,
    customHotkey: nil,
    shortcutBehavior: .toggle
  )

  var hotkeyDisplay: String {
    guard hotkeyPreset == .custom else {
      return hotkeyPreset.display
    }
    return customHotkey?.display ?? "Custom"
  }

  /// Omits the Custom choice until Vhrase has a captured shortcut it can actually register.
  var availableHotkeyPresets: [HotkeyPreset] {
    HotkeyPreset.allCases.filter { preset in
      preset != .custom || customHotkey != nil
    }
  }

  var keytermList: [String] {
    var seen = Set<String>()
    return
      keyterms
      .split(whereSeparator: \.isNewline)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty && seen.insert($0).inserted }
  }

  var geminiLanguageCodes: [String] {
    geminiLanguageHints.split { $0 == "," || $0.isNewline }
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  var transcriptionStyle: String {
    switch provider {
    case .gemini: geminiSmartTranscription ? "Smart transcription" : "Verbatim"
    case .xai: includeFillerWords ? "Keep fillers" : "Remove fillers"
    case .elevenLabs: elevenLabsNoVerbatim ? "Clean speech" : "Verbatim"
    }
  }

  var replacements: [TextReplacement] {
    replacementRules
      .split(whereSeparator: \.isNewline)
      .compactMap { TextReplacement(rule: String($0)) }
  }

  var customizationSummary: String {
    let language = recognitionLanguage
    let keytermCount = keytermList.count
    let replacementCount = replacements.count
    let languageLabel =
      language.isEmpty ? "Auto language" : language
    let keytermLabel = keytermCount == 1 ? "1 keyterm" : "\(keytermCount) keyterms"
    let replacementLabel =
      replacementCount == 1 ? "1 replacement" : "\(replacementCount) replacements"
    let cleanupLabel =
      adjustWithLLM
      ? "LLM cleanup"
      : provider == .gemini && geminiSmartTranscription ? "Smart transcription" : "Raw transcript"
    return "\(languageLabel) · \(keytermLabel) · \(replacementLabel) · \(cleanupLabel)"
  }

  var recognitionLanguage: String {
    provider == .gemini
      ? geminiLanguageCodes.joined(separator: ", ")
      : language.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Rejects persisted or imported values that cannot be produced by Vhrase's bounded controls.
  func validateLocalConfiguration() throws {
    guard provider.availableModes.contains(transcriptionMode) else {
      throw ConfigurationValidationError(
        "Gemini currently transcribes after you stop recording. Choose Upload mode.")
    }
    guard (0...1).contains(xaiVADThreshold) else {
      throw ConfigurationValidationError("Grok speech sensitivity must be between 0 and 1.")
    }
    guard (0...5_000).contains(xaiRealtimeEndpointing) else {
      throw ConfigurationValidationError("xAI endpointing must be between 0 and 5,000 ms.")
    }
    guard (0...1).contains(xaiSmartTurnThreshold) else {
      throw ConfigurationValidationError("xAI Smart Turn threshold must be between 0 and 1.")
    }
    guard (1...5_000).contains(xaiSmartTurnTimeout) else {
      throw ConfigurationValidationError("xAI Smart Turn timeout must be between 1 and 5,000 ms.")
    }
    guard (0.3...3).contains(elevenLabsVADSilenceThreshold) else {
      throw ConfigurationValidationError(
        "ElevenLabs VAD silence must be between 0.3 and 3 seconds.")
    }
    guard (0.1...0.9).contains(elevenLabsVADThreshold) else {
      throw ConfigurationValidationError("ElevenLabs VAD threshold must be between 0.1 and 0.9.")
    }
    guard (50...2_000).contains(elevenLabsMinSpeechDuration) else {
      throw ConfigurationValidationError(
        "ElevenLabs minimum speech must be between 50 and 2,000 ms.")
    }
    guard (50...2_000).contains(elevenLabsMinSilenceDuration) else {
      throw ConfigurationValidationError(
        "ElevenLabs minimum silence must be between 50 and 2,000 ms.")
    }
    guard !adjustWithLLM || !adjustmentModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      throw ConfigurationValidationError("Choose an LLM model before enabling transcript cleanup.")
    }
    guard hotkeyPreset != .custom || customHotkey != nil else {
      throw ConfigurationValidationError("Capture a custom shortcut before selecting Custom.")
    }
  }
}

struct CustomizationSnapshot: Codable, Equatable, Sendable {
  let settings: DictationSettings
}

private struct ConfigurationValidationError: LocalizedError {
  let message: String

  init(_ message: String) {
    self.message = message
  }

  var errorDescription: String? {
    message
  }
}

struct TextReplacement: Sendable {
  let source: String
  let target: String

  /// Splits at the first occurrence of the highest-priority delimiter, preserving delimiters in the replacement text.
  init?(rule: String) {
    let separators = ["=>", "->", "="]
    guard let range = separators.lazy.compactMap({ rule.range(of: $0) }).first else {
      return nil
    }

    let source = rule[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
    let target = rule[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
    guard !source.isEmpty, !target.isEmpty else {
      return nil
    }

    self.source = source
    self.target = target
  }
}
