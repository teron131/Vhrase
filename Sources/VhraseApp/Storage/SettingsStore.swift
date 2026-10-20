// Persists Vhrase's non-secret user preferences with explicit empty-value semantics.

import Foundation

final class SettingsStore {
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func load() -> DictationSettings {
    let fallback = DictationSettings.defaults
    // Persist the vocabulary first so another launch cannot lose retired preferred spellings.
    if let rules = defaults.string(forKey: "replacementRules") {
      let vocabulary = DictationSettings.migratingVocabulary(
        storedString("keyterms", fallback.keyterms), replacementRules: rules)
      defaults.set(vocabulary, forKey: "keyterms")
      defaults.removeObject(forKey: "replacementRules")
    }
    var settings = DictationSettings(
      provider: STTProvider(rawValue: defaults.string(forKey: "provider") ?? "")
        ?? fallback.provider,
      transcriptionMode: TranscriptionMode(
        rawValue: defaults.string(forKey: "transcriptionMode") ?? "") ?? fallback.transcriptionMode,
      elevenLabsCommitStrategy: ElevenLabsCommitStrategy(
        rawValue: defaults.string(forKey: "elevenLabsCommitStrategy") ?? "")
        ?? fallback.elevenLabsCommitStrategy,
      elevenLabsNoVerbatim: bool("elevenLabsNoVerbatim", fallback.elevenLabsNoVerbatim),
      elevenLabsVADSilenceThreshold: boundedDouble(
        "elevenLabsVADSilenceThreshold", fallback.elevenLabsVADSilenceThreshold, range: 0.3...3),
      elevenLabsVADThreshold: boundedDouble(
        "elevenLabsVADThreshold", fallback.elevenLabsVADThreshold, range: 0.1...0.9),
      elevenLabsMinSpeechDuration: boundedInt(
        "elevenLabsMinSpeechDuration", fallback.elevenLabsMinSpeechDuration, range: 50...2_000),
      elevenLabsMinSilenceDuration: boundedInt(
        "elevenLabsMinSilenceDuration", fallback.elevenLabsMinSilenceDuration, range: 50...2_000),
      language: storedString("language", fallback.language),
      keyterms: storedString("keyterms", fallback.keyterms),
      includeFillerWords: bool("includeFillerWords", fallback.includeFillerWords),
      xaiRealtimeEndpointing: boundedInt(
        "xaiRealtimeEndpointing", fallback.xaiRealtimeEndpointing, range: 0...5_000),
      xaiSmartTurnEnabled: bool("xaiSmartTurnEnabled", fallback.xaiSmartTurnEnabled),
      xaiSmartTurnThreshold: boundedDouble(
        "xaiSmartTurnThreshold", fallback.xaiSmartTurnThreshold, range: 0...1),
      xaiSmartTurnTimeout: boundedInt(
        "xaiSmartTurnTimeout", fallback.xaiSmartTurnTimeout, range: 1...5_000),
      keepTranscriptOnClipboard: bool(
        "keepTranscriptOnClipboard",
        fallback.keepTranscriptOnClipboard
      ),
      adjustWithLLM: bool("adjustWithLLM", fallback.adjustWithLLM),
      useLocalAdjustmentFallback: bool(
        "useLocalAdjustmentFallback", fallback.useLocalAdjustmentFallback),
      adjustmentBaseURL: nonEmptyString("adjustmentBaseURL", fallback.adjustmentBaseURL),
      adjustmentModel: nonEmptyString("adjustmentModel", fallback.adjustmentModel),
      adjustmentPrompt: storedString("adjustmentPrompt", fallback.adjustmentPrompt),
      includeScreenshot: bool("includeScreenshot", fallback.includeScreenshot),
      hotkeyPreset: HotkeyPreset(rawValue: defaults.string(forKey: "hotkeyPreset") ?? "")
        ?? fallback.hotkeyPreset,
      customHotkey: customHotkey()
    )
    if settings.hotkeyPreset == .custom, settings.customHotkey == nil {
      settings.hotkeyPreset = fallback.hotkeyPreset
    }
    if settings.adjustmentPrompt == DictationSettings.legacyDefaultAdjustmentPrompt {
      settings.adjustmentPrompt = ""
    }
    settings.polishPreferences = PolishPreferences(
      rewriteLevel: enumValue(
        "polishRewriteLevel", fallback.polishPreferences.rewriteLevel),
      numberStyle: enumValue(
        "polishNumberStyle", fallback.polishPreferences.numberStyle),
      ordinalStyle: enumValue(
        "polishOrdinalStyle", fallback.polishPreferences.ordinalStyle),
      moneyStyle: enumValue(
        "polishMoneyStyle", fallback.polishPreferences.moneyStyle),
      unitStyle: enumValue(
        "polishUnitStyle", fallback.polishPreferences.unitStyle),
      contractionStyle: enumValue(
        "polishContractionStyle", fallback.polishPreferences.contractionStyle),
      sentenceStyle: enumValue(
        "polishSentenceStyle", fallback.polishPreferences.sentenceStyle),
      structureStyle: enumValue(
        "polishStructureStyle", fallback.polishPreferences.structureStyle),
      allowsLeadingConjunctions: bool(
        "polishAllowsLeadingConjunctions",
        fallback.polishPreferences.allowsLeadingConjunctions),
      removesFillerWords: bool(
        "polishRemovesFillerWords",
        fallback.polishPreferences.removesFillerWords),
      resolvesSpokenCorrections: bool(
        "polishResolvesSpokenCorrections",
        fallback.polishPreferences.resolvesSpokenCorrections)
    )
    settings.screenshotResolution = enumValue(
      "screenshotResolution", fallback.screenshotResolution)
    settings.geminiSmartTranscription = bool(
      "geminiSmartTranscription", fallback.geminiSmartTranscription)
    settings.geminiLanguageHints = storedString("geminiLanguageHints", fallback.geminiLanguageHints)
    settings.xaiFormatText = bool("xaiFormatText", fallback.xaiFormatText)
    settings.inputDeviceUID = storedString("inputDeviceUID", fallback.inputDeviceUID)
    settings.xaiVADThreshold = boundedDouble(
      "xaiVADThreshold", fallback.xaiVADThreshold, range: 0...1)
    settings.automaticVolumeLeveling = bool(
      "automaticVolumeLeveling", fallback.automaticVolumeLeveling)
    settings.inputGainDB = boundedDouble("inputGainDB", fallback.inputGainDB, range: -6...6)
    settings.noiseReductionDB = boundedDouble(
      "noiseReductionDB", fallback.noiseReductionDB, range: 0...12)
    settings.vercelModel = storedString("vercelModel", fallback.vercelModel)
    settings.huggingFaceModel = storedString("huggingFaceModel", fallback.huggingFaceModel)
    settings.shortcutGestures = ShortcutGestures(
      tapToToggle: bool("shortcutTapToToggle", fallback.shortcutGestures.tapToToggle),
      holdToTalk: bool("shortcutHoldToTalk", fallback.shortcutGestures.holdToTalk),
      doubleTapToPolish: bool(
        "shortcutDoubleTapToPolish", fallback.shortcutGestures.doubleTapToPolish)
    )
    if !settings.shortcutGestures.tapToToggle, !settings.shortcutGestures.holdToTalk {
      settings.shortcutGestures = fallback.shortcutGestures
    }
    if !settings.provider.availableModes.contains(settings.transcriptionMode) {
      settings.transcriptionMode = .upload
    }
    return settings
  }

  /// Persists every preference, writing only the keys whose value changed so one edit does not resend them all.
  func save(_ settings: DictationSettings) {
    set(settings.provider.rawValue, forKey: "provider")
    set(settings.transcriptionMode.rawValue, forKey: "transcriptionMode")
    set(settings.elevenLabsCommitStrategy.rawValue, forKey: "elevenLabsCommitStrategy")
    set(settings.elevenLabsNoVerbatim, forKey: "elevenLabsNoVerbatim")
    set(settings.elevenLabsVADSilenceThreshold, forKey: "elevenLabsVADSilenceThreshold")
    set(settings.elevenLabsVADThreshold, forKey: "elevenLabsVADThreshold")
    set(settings.elevenLabsMinSpeechDuration, forKey: "elevenLabsMinSpeechDuration")
    set(settings.elevenLabsMinSilenceDuration, forKey: "elevenLabsMinSilenceDuration")
    set(settings.language, forKey: "language")
    set(settings.keyterms, forKey: "keyterms")
    remove("replacementRules")
    set(settings.includeFillerWords, forKey: "includeFillerWords")
    set(settings.xaiRealtimeEndpointing, forKey: "xaiRealtimeEndpointing")
    set(settings.xaiSmartTurnEnabled, forKey: "xaiSmartTurnEnabled")
    set(settings.xaiSmartTurnThreshold, forKey: "xaiSmartTurnThreshold")
    set(settings.xaiSmartTurnTimeout, forKey: "xaiSmartTurnTimeout")
    set(settings.keepTranscriptOnClipboard, forKey: "keepTranscriptOnClipboard")
    set(settings.adjustWithLLM, forKey: "adjustWithLLM")
    set(settings.useLocalAdjustmentFallback, forKey: "useLocalAdjustmentFallback")
    set(settings.adjustmentBaseURL, forKey: "adjustmentBaseURL")
    set(settings.adjustmentModel, forKey: "adjustmentModel")
    set(settings.adjustmentPrompt, forKey: "adjustmentPrompt")
    set(settings.polishPreferences.rewriteLevel.rawValue, forKey: "polishRewriteLevel")
    set(settings.polishPreferences.numberStyle.rawValue, forKey: "polishNumberStyle")
    set(settings.polishPreferences.ordinalStyle.rawValue, forKey: "polishOrdinalStyle")
    set(settings.polishPreferences.moneyStyle.rawValue, forKey: "polishMoneyStyle")
    set(settings.polishPreferences.unitStyle.rawValue, forKey: "polishUnitStyle")
    set(
      settings.polishPreferences.contractionStyle.rawValue,
      forKey: "polishContractionStyle")
    set(settings.polishPreferences.sentenceStyle.rawValue, forKey: "polishSentenceStyle")
    set(
      settings.polishPreferences.structureStyle.rawValue,
      forKey: "polishStructureStyle")
    set(
      settings.polishPreferences.allowsLeadingConjunctions,
      forKey: "polishAllowsLeadingConjunctions")
    set(
      settings.polishPreferences.removesFillerWords,
      forKey: "polishRemovesFillerWords")
    set(
      settings.polishPreferences.resolvesSpokenCorrections,
      forKey: "polishResolvesSpokenCorrections")
    set(settings.includeScreenshot, forKey: "includeScreenshot")
    set(settings.screenshotResolution.rawValue, forKey: "screenshotResolution")
    set(settings.hotkeyPreset.rawValue, forKey: "hotkeyPreset")
    saveCustomHotkey(settings.customHotkey)
    set(settings.shortcutGestures.tapToToggle, forKey: "shortcutTapToToggle")
    set(settings.shortcutGestures.holdToTalk, forKey: "shortcutHoldToTalk")
    set(settings.shortcutGestures.doubleTapToPolish, forKey: "shortcutDoubleTapToPolish")
    set(settings.geminiSmartTranscription, forKey: "geminiSmartTranscription")
    set(settings.geminiLanguageHints, forKey: "geminiLanguageHints")
    set(settings.xaiFormatText, forKey: "xaiFormatText")
    set(settings.xaiVADThreshold, forKey: "xaiVADThreshold")
    set(settings.automaticVolumeLeveling, forKey: "automaticVolumeLeveling")
    set(settings.inputGainDB, forKey: "inputGainDB")
    set(settings.noiseReductionDB, forKey: "noiseReductionDB")
    set(settings.inputDeviceUID, forKey: "inputDeviceUID")
    set(settings.vercelModel, forKey: "vercelModel")
    set(settings.huggingFaceModel, forKey: "huggingFaceModel")
  }

  private func nonEmptyString(_ key: String, _ fallback: String) -> String {
    let value = defaults.string(forKey: key) ?? fallback
    return value.isEmpty ? fallback : value
  }

  private func storedString(_ key: String, _ fallback: String) -> String {
    guard defaults.object(forKey: key) != nil else {
      return fallback
    }
    return defaults.string(forKey: key) ?? fallback
  }

  private func enumValue<Value: RawRepresentable>(_ key: String, _ fallback: Value) -> Value
  where Value.RawValue == String {
    guard let rawValue = defaults.string(forKey: key), let value = Value(rawValue: rawValue) else {
      return fallback
    }
    return value
  }

  private func bool(_ key: String, _ fallback: Bool) -> Bool {
    defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
  }

  private func int(_ key: String, _ fallback: Int) -> Int {
    defaults.object(forKey: key) == nil ? fallback : defaults.integer(forKey: key)
  }

  private func double(_ key: String, _ fallback: Double) -> Double {
    defaults.object(forKey: key) == nil ? fallback : defaults.double(forKey: key)
  }

  private func boundedInt(
    _ key: String,
    _ fallback: Int,
    range: ClosedRange<Int>
  ) -> Int {
    min(max(int(key, fallback), range.lowerBound), range.upperBound)
  }

  private func boundedDouble(
    _ key: String,
    _ fallback: Double,
    range: ClosedRange<Double>
  ) -> Double {
    min(max(double(key, fallback), range.lowerBound), range.upperBound)
  }

  private func customHotkey() -> CustomHotkey? {
    guard let display = defaults.string(forKey: "customHotkeyDisplay"),
      defaults.object(forKey: "customHotkeyKeyCode") != nil,
      defaults.object(forKey: "customHotkeyModifiers") != nil
    else {
      return nil
    }

    return CustomHotkey(
      keyCode: UInt32(defaults.integer(forKey: "customHotkeyKeyCode")),
      modifiers: UInt32(defaults.integer(forKey: "customHotkeyModifiers")),
      display: display
    )
  }

  private func saveCustomHotkey(_ hotkey: CustomHotkey?) {
    guard let hotkey else {
      remove("customHotkeyKeyCode")
      remove("customHotkeyModifiers")
      remove("customHotkeyDisplay")
      return
    }

    set(Int(hotkey.keyCode), forKey: "customHotkeyKeyCode")
    set(Int(hotkey.modifiers), forKey: "customHotkeyModifiers")
    set(hotkey.display, forKey: "customHotkeyDisplay")
  }

  /// Each write is a message to the preferences daemon, so an unchanged value is left alone.
  private func set<Value: Equatable>(_ value: Value, forKey key: String) {
    guard defaults.object(forKey: key) as? Value != value else {
      return
    }
    defaults.set(value, forKey: key)
  }

  private func remove(_ key: String) {
    guard defaults.object(forKey: key) != nil else {
      return
    }
    defaults.removeObject(forKey: key)
  }
}
