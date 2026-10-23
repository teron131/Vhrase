// Owns persistent dictation preferences: their defaults, the bounds recording validates, and the decoding that keeps older saved values loading.

import Foundation

enum DictationPolishing: String, CaseIterable, Codable, Identifiable, Sendable {
  case off
  case refine
  case restyle

  var id: String { rawValue }

  var title: String {
    switch self {
    case .off: "Off"
    case .refine: "Refine"
    case .restyle: "Restyle"
    }
  }

  var usesLLM: Bool { self != .off }
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

/// Chosen locally because gateways such as Vercel AI Gateway drop OpenAI's `image_url` detail hint. 1600 keeps 13 pt Retina text near its on-screen size; from about 1280 down, unusual names misread more often.
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
  var afterTranscription: DictationPolishing
  var useLocalAdjustmentFallback: Bool
  var adjustmentBaseURL: String
  var adjustmentModel: String
  var adjustmentPrompt: String
  var polishPreferences: PolishPreferences = .defaults
  var restyleChoice: RestyleChoice = .rephrase
  var customRestyleName: String = RestyleChoice.custom.title
  var customRestyleInstruction: String = ""
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
  var huggingFaceModel: String = defaultHuggingFaceModel
  var geminiModel: String = defaultGeminiModel
  var openAIModel: String = defaultOpenAIModel
  var elevenLabsModel: String = defaultElevenLabsModel
  var elevenLabsRealtimeModel: String = defaultElevenLabsRealtimeModel
  var convertChineseOutput: Bool = true

  /// Vercel AI Gateway's identifier for xAI's speech-to-text.
  static let defaultVercelModel = "spacexai/grok-stt"
  static let defaultGeminiModel = "gemini-3.5-transcribe"
  static let defaultOpenAIModel = "gpt-transcribe"
  static let defaultElevenLabsModel = "scribe_v2"
  static let defaultElevenLabsRealtimeModel = "scribe_v2_realtime"
  static let defaultHuggingFaceModel = "openai/whisper-large-v3-turbo"
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
    afterTranscription: .off,
    useLocalAdjustmentFallback: true,
    adjustmentBaseURL: "https://ai-gateway.vercel.sh/v1",
    adjustmentModel: "",
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

  var polishStyle: PolishStyle {
    switch restyleChoice {
    case .rephrase: return .rephrase
    case .genZ: return .genZ
    case .custom:
      let name = customRestyleName.trimmingCharacters(in: .whitespacesAndNewlines)
      return PolishStyle(
        title: name.isEmpty ? RestyleChoice.custom.title : name,
        instruction: customRestyleInstruction)
    }
  }

  func validateRestyle() throws {
    guard
      restyleChoice != .custom
        || !customRestyleInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      throw ConfigurationValidationError(
        "Enter a Custom Restyle instruction on Polishing before restyling text.")
    }
  }

  /// The Custom instruction problem that blocks recording, which Polishing rather than Transcription fixes.
  var restyleIssue: String? {
    guard afterTranscription == .restyle else { return nil }
    do {
      try validateRestyle()
      return nil
    } catch {
      return error.localizedDescription
    }
  }

  var dictationPolishOperation: PolishOperation? {
    switch afterTranscription {
    case .off: nil
    case .refine: .refine
    case .restyle: .restyle(polishStyle)
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

  /// Keeps each retired replacement rule's target as a vocabulary term and drops the rule: `Vhrase` with rules `v phrase => Vhrase` and `open ai -> OpenAI` becomes `Vhrase` and `OpenAI`, one per line. A rule splits at `=>`, else `->`, else `=`.
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
    case adjustWithLLM
  }

  var transcriptionModeTitle: String {
    transcriptionMode.title(for: provider)
  }

  /// The setting naming the model the selected provider and mode send, with its default; `nil` where requests name no model (xAI) or the model is set up on this Mac.
  var transcriptionModelSetting:
    (keyPath: WritableKeyPath<DictationSettings, String>, defaultValue: String)?
  {
    switch (provider, transcriptionMode) {
    case (.gemini, _): (\.geminiModel, Self.defaultGeminiModel)
    case (.openAI, _): (\.openAIModel, Self.defaultOpenAIModel)
    case (.elevenLabs, .upload): (\.elevenLabsModel, Self.defaultElevenLabsModel)
    case (.elevenLabs, .realtime): (\.elevenLabsRealtimeModel, Self.defaultElevenLabsRealtimeModel)
    case (.vercel, _): (\.vercelModel, Self.defaultVercelModel)
    case (.xai, _), (.parakeet, _), (.huggingFace, _): nil
    }
  }

  /// Rejects invalid recording controls and the model or style inputs used by the selected dictation path.
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
      throw ConfigurationValidationError("xAI speech sensitivity must be between 0 and 1.")
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
    guard
      !afterTranscription.usesLLM
        || !adjustmentModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      throw ConfigurationValidationError("Choose an LLM model before enabling transcript cleanup.")
    }
    if afterTranscription == .restyle {
      try validateRestyle()
    }
    guard hotkeyPreset != .custom || customHotkey != nil else {
      throw ConfigurationValidationError("Capture a custom shortcut before selecting Custom.")
    }
    guard shortcutGestures.tapToToggle || shortcutGestures.holdToTalk else {
      throw ConfigurationValidationError("Turn on tap or hold so the shortcut can start dictation.")
    }
    // A free-text model name blocks recording only for the provider and mode that would send it.
    if let model = transcriptionModelSetting,
      self[keyPath: model.keyPath].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      let service = provider == .vercel ? "Vercel AI Gateway" : provider.title
      throw ConfigurationValidationError(
        "Enter the \(service) transcription model to use, such as \(model.defaultValue).")
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
    case afterTranscription
    case useLocalAdjustmentFallback
    case adjustmentBaseURL
    case adjustmentModel
    case adjustmentPrompt
    case polishPreferences
    case restyleChoice
    case customRestyleName
    case customRestyleInstruction
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
    case geminiModel
    case openAIModel
    case elevenLabsModel
    case elevenLabsRealtimeModel
    case convertChineseOutput
  }

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
    if let choice = try values.decodeIfPresent(DictationPolishing.self, forKey: .afterTranscription)
    {
      afterTranscription = choice
    } else {
      afterTranscription =
        (try retired.decodeIfPresent(Bool.self, forKey: .adjustWithLLM) ?? true)
        ? .refine : .off
    }
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
    restyleChoice =
      try values.decodeIfPresent(RestyleChoice.self, forKey: .restyleChoice) ?? .rephrase
    customRestyleName =
      try values.decodeIfPresent(String.self, forKey: .customRestyleName)
      ?? RestyleChoice.custom.title
    customRestyleInstruction =
      try values.decodeIfPresent(String.self, forKey: .customRestyleInstruction) ?? ""
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
      ?? Self.defaultHuggingFaceModel
    geminiModel =
      try values.decodeIfPresent(String.self, forKey: .geminiModel) ?? Self.defaultGeminiModel
    openAIModel =
      try values.decodeIfPresent(String.self, forKey: .openAIModel) ?? Self.defaultOpenAIModel
    elevenLabsModel =
      try values.decodeIfPresent(String.self, forKey: .elevenLabsModel)
      ?? Self.defaultElevenLabsModel
    elevenLabsRealtimeModel =
      try values.decodeIfPresent(String.self, forKey: .elevenLabsRealtimeModel)
      ?? Self.defaultElevenLabsRealtimeModel
    convertChineseOutput =
      try values.decodeIfPresent(Bool.self, forKey: .convertChineseOutput) ?? true
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
