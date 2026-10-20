// Owns persistent dictation preferences and the provider capabilities that constrain capture and cleanup.

import Foundation

enum STTProvider: String, CaseIterable, Codable, Identifiable, Sendable {
  case xai
  case elevenLabs
  case gemini
  case openAI
  case vercel
  case parakeet
  case huggingFace

  var id: String { rawValue }

  var title: String {
    switch self {
    case .xai:
      "xAI"
    case .elevenLabs:
      "ElevenLabs"
    case .gemini:
      "Gemini"
    case .openAI:
      "OpenAI"
    case .vercel:
      "Vercel"
    case .parakeet:
      "Parakeet"
    case .huggingFace:
      "Hugging Face"
    }
  }

  var availableModes: [TranscriptionMode] {
    switch self {
    case .xai, .elevenLabs: TranscriptionMode.allCases
    case .gemini, .openAI, .vercel, .parakeet, .huggingFace: [.upload]
    }
  }

  /// False for providers whose recognition ignores the shared vocabulary, leaving it to LLM polishing alone.
  var takesVocabularyHints: Bool {
    switch self {
    case .xai, .elevenLabs, .gemini, .openAI: true
    case .vercel, .parakeet, .huggingFace: false
    }
  }

  var location: ProviderLocation {
    switch self {
    case .xai, .elevenLabs, .gemini, .openAI, .vercel: .cloud
    case .parakeet, .huggingFace: .local
    }
  }

  var detail: String {
    switch self {
    case .xai: "Grok speech recognition with optional filler removal and number formatting."
    case .elevenLabs: "Scribe speech recognition with verbatim controls and realtime streaming."
    case .gemini: "Gemini 3.5 Transcribe with optional Smart transcription."
    case .openAI: "GPT Transcribe with an optional language hint."
    case .vercel:
      "Any transcription model on Vercel AI Gateway, reached with one gateway key."
    case .parakeet:
      "NVIDIA Parakeet TDT 0.6B v3 running on this Mac. No API key, and no network once downloaded."
    case .huggingFace:
      "Any Hugging Face speech model the transformers pipeline accepts, running on this Mac. No API key, and no network once downloaded."
    }
  }
}

/// Where a provider recognizes speech: cloud providers need an API key, local ones a downloaded model.
enum ProviderLocation: String, CaseIterable, Identifiable, Sendable {
  case cloud
  case local

  var id: String { rawValue }

  var title: String {
    switch self {
    case .cloud: "Cloud"
    case .local: "Local"
    }
  }

  /// Lists this location's providers alphabetically, the order every picker and the credential rows present them in.
  var providers: [STTProvider] {
    STTProvider.allCases
      .filter { $0.location == self }
      .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
  }
}

enum TranscriptionMode: String, CaseIterable, Codable, Identifiable, Sendable {
  case upload
  case realtime

  var id: String { rawValue }

  /// Names after-stop transcription by where it runs, so on-device recognition never reads as an upload.
  func title(for provider: STTProvider) -> String {
    switch self {
    case .upload:
      provider.location == .local ? "After stop" : "Upload"
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

/// Longest side of the screenshot sent with LLM polishing, chosen locally because gateways such as Vercel AI Gateway drop OpenAI's `image_url` detail hint.
/// Smaller images reach the model sooner but blur small text; 1600 keeps 13 pt Retina text near its on-screen size, and from about 1280 down unusual names misread more often.
enum ScreenshotResolution: String, CaseIterable, Codable, Identifiable, Sendable {
  case pixels1024 = "1024"
  case pixels1280 = "1280"
  case pixels1440 = "1440"
  case pixels1600 = "1600"
  case pixels1920 = "1920"
  case pixels2560 = "2560"
  case original

  var id: String { rawValue }

  /// The capture's longest side after downsizing, or `nil` to keep the capture's own size.
  var maxPixelSize: Int? { Int(rawValue) }

  var title: String { maxPixelSize.map(String.init) ?? "Original" }
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
  var polishPreferences: PolishPreferences = .defaults
  var includeScreenshot: Bool
  var screenshotResolution: ScreenshotResolution = .pixels1600
  var hotkeyPreset: HotkeyPreset
  var customHotkey: CustomHotkey?
  var shortcutGestures = ShortcutGestures()
  var geminiSmartTranscription: Bool = true
  var geminiLanguageHints: String = ""
  var xaiFormatText: Bool = true
  var xaiVADThreshold: Double = 0.08
  var automaticVolumeLeveling: Bool = true
  var inputGainDB: Double = 0
  var noiseReductionDB: Double = 6
  var inputDeviceUID: String = ""
  var vercelModel: String = defaultVercelModel
  var huggingFaceModel: String = HuggingFaceModelReference.whisperTurbo

  /// Vercel AI Gateway's identifier for xAI's speech-to-text, the same default youtube-toolkit uses.
  static let defaultVercelModel = "spacexai/grok-stt"
  static let legacyDefaultAdjustmentPrompt = """
    Rewrite the transcript into polished text that is ready to insert into the active app. Fix obvious speech-to-text mistakes, punctuation, casing, and awkward phrasing while preserving intent. Use the screenshot only as context. Return only the final text.
    """
  static let defaultAdjustmentPrompt = ""

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
    customHotkey: nil
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

  /// Converts retired substitution targets into reference vocabulary without retaining executable replacement rules.
  static func migratingVocabulary(_ vocabulary: String, replacementRules: String) -> String {
    let targets = replacementRules.split(whereSeparator: \.isNewline).compactMap {
      line -> String? in
      let rule = String(line)
      let separators = ["=>", "->", "="]
      guard let range = separators.lazy.compactMap({ rule.range(of: $0) }).first else { return nil }
      let source = rule[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
      let target = rule[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
      return source.isEmpty || target.isEmpty ? nil : target
    }
    guard !targets.isEmpty else { return vocabulary }
    var seen = Set<String>()
    return (vocabulary.components(separatedBy: .newlines) + targets)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty && seen.insert($0).inserted }
      .joined(separator: "\n")
  }

  private enum RetiredKeys: String, CodingKey {
    case replacementRules
  }

  /// Reports the language hint the selected provider actually receives; Parakeet and the gateway always detect the language.
  var recognitionLanguage: String {
    switch provider {
    case .gemini: geminiLanguageCodes.joined(separator: ", ")
    case .parakeet, .vercel: ""
    case .xai, .elevenLabs, .openAI, .huggingFace:
      language.trimmingCharacters(in: .whitespacesAndNewlines)
    }
  }

  var transcriptionModeTitle: String {
    transcriptionMode.title(for: provider)
  }

  /// Rejects persisted or imported values that cannot be produced by Vhrase's bounded controls.
  func validateLocalConfiguration() throws {
    guard (-6...6).contains(inputGainDB), (0...12).contains(noiseReductionDB) else {
      throw ConfigurationValidationError(
        "Input volume must be between −6 and +6 dB, and extra noise reduction between 0 and 12 dB.")
    }
    guard provider.availableModes.contains(transcriptionMode) else {
      throw ConfigurationValidationError(
        "\(provider.title) currently transcribes after you stop recording. Choose \(TranscriptionMode.upload.title(for: provider)) mode."
      )
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
    guard shortcutGestures.tapToToggle || shortcutGestures.holdToTalk else {
      throw ConfigurationValidationError("Turn on tap or hold so the shortcut can start dictation.")
    }
    // A free-text model name blocks recording only for the provider that would use it.
    guard
      provider != .vercel || !vercelModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      throw ConfigurationValidationError(
        "Enter a Vercel AI Gateway transcription model, such as \(Self.defaultVercelModel).")
    }
    if provider == .huggingFace {
      _ = try HuggingFaceModelReference(huggingFaceModel)
    }
  }
}

extension DictationSettings {
  private enum CodingKeys: String, CodingKey {
    case provider
    case transcriptionMode
    case elevenLabsCommitStrategy
    case elevenLabsNoVerbatim
    case elevenLabsVADSilenceThreshold
    case elevenLabsVADThreshold
    case elevenLabsMinSpeechDuration
    case elevenLabsMinSilenceDuration
    case language
    case keyterms
    case includeFillerWords
    case xaiRealtimeEndpointing
    case xaiSmartTurnEnabled
    case xaiSmartTurnThreshold
    case xaiSmartTurnTimeout
    case keepTranscriptOnClipboard
    case adjustWithLLM
    case useLocalAdjustmentFallback
    case adjustmentBaseURL
    case adjustmentModel
    case adjustmentPrompt
    case polishPreferences
    case includeScreenshot
    case screenshotResolution
    case hotkeyPreset
    case customHotkey
    case shortcutGestures
    case geminiSmartTranscription
    case geminiLanguageHints
    case xaiFormatText
    case xaiVADThreshold
    case automaticVolumeLeveling
    case inputGainDB
    case noiseReductionDB
    case inputDeviceUID
    case vercelModel
    case huggingFaceModel
  }

  /// Supplies audio and model defaults for existing exports while retaining validation of the original settings contract.
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    provider = try values.decode(STTProvider.self, forKey: .provider)
    transcriptionMode = try values.decode(TranscriptionMode.self, forKey: .transcriptionMode)
    elevenLabsCommitStrategy = try values.decode(
      ElevenLabsCommitStrategy.self, forKey: .elevenLabsCommitStrategy)
    elevenLabsNoVerbatim = try values.decode(Bool.self, forKey: .elevenLabsNoVerbatim)
    elevenLabsVADSilenceThreshold = try values.decode(
      Double.self, forKey: .elevenLabsVADSilenceThreshold)
    elevenLabsVADThreshold = try values.decode(Double.self, forKey: .elevenLabsVADThreshold)
    elevenLabsMinSpeechDuration = try values.decode(Int.self, forKey: .elevenLabsMinSpeechDuration)
    elevenLabsMinSilenceDuration = try values.decode(
      Int.self, forKey: .elevenLabsMinSilenceDuration)
    language = try values.decode(String.self, forKey: .language)
    keyterms = try values.decode(String.self, forKey: .keyterms)
    let retired = try decoder.container(keyedBy: RetiredKeys.self)
    if let rules = try retired.decodeIfPresent(String.self, forKey: .replacementRules) {
      keyterms = Self.migratingVocabulary(keyterms, replacementRules: rules)
    }
    includeFillerWords = try values.decode(Bool.self, forKey: .includeFillerWords)
    xaiRealtimeEndpointing = try values.decode(Int.self, forKey: .xaiRealtimeEndpointing)
    xaiSmartTurnEnabled = try values.decode(Bool.self, forKey: .xaiSmartTurnEnabled)
    xaiSmartTurnThreshold = try values.decode(Double.self, forKey: .xaiSmartTurnThreshold)
    xaiSmartTurnTimeout = try values.decode(Int.self, forKey: .xaiSmartTurnTimeout)
    keepTranscriptOnClipboard = try values.decode(Bool.self, forKey: .keepTranscriptOnClipboard)
    adjustWithLLM = try values.decode(Bool.self, forKey: .adjustWithLLM)
    useLocalAdjustmentFallback = try values.decode(Bool.self, forKey: .useLocalAdjustmentFallback)
    adjustmentBaseURL = try values.decode(String.self, forKey: .adjustmentBaseURL)
    adjustmentModel = try values.decode(String.self, forKey: .adjustmentModel)
    adjustmentPrompt = try values.decode(String.self, forKey: .adjustmentPrompt)
    if adjustmentPrompt == Self.legacyDefaultAdjustmentPrompt {
      adjustmentPrompt = ""
    }
    polishPreferences =
      try values.decodeIfPresent(
        PolishPreferences.self, forKey: .polishPreferences) ?? .defaults
    includeScreenshot = try values.decode(Bool.self, forKey: .includeScreenshot)
    screenshotResolution =
      try values.decodeIfPresent(ScreenshotResolution.self, forKey: .screenshotResolution)
      ?? .pixels1600
    hotkeyPreset = try values.decode(HotkeyPreset.self, forKey: .hotkeyPreset)
    customHotkey = try values.decodeIfPresent(CustomHotkey.self, forKey: .customHotkey)
    shortcutGestures =
      try values.decodeIfPresent(ShortcutGestures.self, forKey: .shortcutGestures)
      ?? ShortcutGestures()
    geminiSmartTranscription = try values.decode(Bool.self, forKey: .geminiSmartTranscription)
    geminiLanguageHints = try values.decode(String.self, forKey: .geminiLanguageHints)
    xaiFormatText = try values.decode(Bool.self, forKey: .xaiFormatText)
    xaiVADThreshold = try values.decode(Double.self, forKey: .xaiVADThreshold)
    automaticVolumeLeveling =
      try values.decodeIfPresent(Bool.self, forKey: .automaticVolumeLeveling) ?? true
    inputGainDB = try values.decodeIfPresent(Double.self, forKey: .inputGainDB) ?? 0
    noiseReductionDB = try values.decodeIfPresent(Double.self, forKey: .noiseReductionDB) ?? 6
    inputDeviceUID = try values.decodeIfPresent(String.self, forKey: .inputDeviceUID) ?? ""
    vercelModel =
      try values.decodeIfPresent(String.self, forKey: .vercelModel) ?? Self.defaultVercelModel
    huggingFaceModel =
      try values.decodeIfPresent(String.self, forKey: .huggingFaceModel)
      ?? HuggingFaceModelReference.whisperTurbo
  }
}

struct CustomizationSnapshot: Codable, Equatable, Sendable {
  let settings: DictationSettings
}

/// Carries the sentence shown when a setting cannot be used, both beside the control and when recording is refused.
struct ConfigurationValidationError: LocalizedError {
  let message: String

  init(_ message: String) {
    self.message = message
  }

  var errorDescription: String? {
    message
  }
}
