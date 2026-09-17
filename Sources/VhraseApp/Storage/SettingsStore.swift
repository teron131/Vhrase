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
        fallback.polishPreferences.allowsLeadingConjunctions)
    )
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
    if !settings.provider.availableModes.contains(settings.transcriptionMode) {
      settings.transcriptionMode = .upload
    }
    return settings
  }

  func save(_ settings: DictationSettings) {
    defaults.set(settings.provider.rawValue, forKey: "provider")
    defaults.set(settings.transcriptionMode.rawValue, forKey: "transcriptionMode")
    defaults.set(settings.elevenLabsCommitStrategy.rawValue, forKey: "elevenLabsCommitStrategy")
    defaults.set(settings.elevenLabsNoVerbatim, forKey: "elevenLabsNoVerbatim")
    defaults.set(settings.elevenLabsVADSilenceThreshold, forKey: "elevenLabsVADSilenceThreshold")
    defaults.set(settings.elevenLabsVADThreshold, forKey: "elevenLabsVADThreshold")
    defaults.set(settings.elevenLabsMinSpeechDuration, forKey: "elevenLabsMinSpeechDuration")
    defaults.set(settings.elevenLabsMinSilenceDuration, forKey: "elevenLabsMinSilenceDuration")
    defaults.set(settings.language, forKey: "language")
    defaults.set(settings.keyterms, forKey: "keyterms")
    defaults.removeObject(forKey: "replacementRules")
    defaults.set(settings.includeFillerWords, forKey: "includeFillerWords")
    defaults.set(settings.xaiRealtimeEndpointing, forKey: "xaiRealtimeEndpointing")
    defaults.set(settings.xaiSmartTurnEnabled, forKey: "xaiSmartTurnEnabled")
    defaults.set(settings.xaiSmartTurnThreshold, forKey: "xaiSmartTurnThreshold")
    defaults.set(settings.xaiSmartTurnTimeout, forKey: "xaiSmartTurnTimeout")
    defaults.set(settings.keepTranscriptOnClipboard, forKey: "keepTranscriptOnClipboard")
    defaults.set(settings.adjustWithLLM, forKey: "adjustWithLLM")
    defaults.set(settings.useLocalAdjustmentFallback, forKey: "useLocalAdjustmentFallback")
    defaults.set(settings.adjustmentBaseURL, forKey: "adjustmentBaseURL")
    defaults.set(settings.adjustmentModel, forKey: "adjustmentModel")
    defaults.set(settings.adjustmentPrompt, forKey: "adjustmentPrompt")
    defaults.set(settings.polishPreferences.rewriteLevel.rawValue, forKey: "polishRewriteLevel")
    defaults.set(settings.polishPreferences.numberStyle.rawValue, forKey: "polishNumberStyle")
    defaults.set(settings.polishPreferences.ordinalStyle.rawValue, forKey: "polishOrdinalStyle")
    defaults.set(settings.polishPreferences.moneyStyle.rawValue, forKey: "polishMoneyStyle")
    defaults.set(settings.polishPreferences.unitStyle.rawValue, forKey: "polishUnitStyle")
    defaults.set(
      settings.polishPreferences.contractionStyle.rawValue,
      forKey: "polishContractionStyle")
    defaults.set(settings.polishPreferences.sentenceStyle.rawValue, forKey: "polishSentenceStyle")
    defaults.set(
      settings.polishPreferences.structureStyle.rawValue,
      forKey: "polishStructureStyle")
    defaults.set(
      settings.polishPreferences.allowsLeadingConjunctions,
      forKey: "polishAllowsLeadingConjunctions")
    defaults.set(settings.includeScreenshot, forKey: "includeScreenshot")
    defaults.set(settings.hotkeyPreset.rawValue, forKey: "hotkeyPreset")
    saveCustomHotkey(settings.customHotkey)
    defaults.set(settings.geminiSmartTranscription, forKey: "geminiSmartTranscription")
    defaults.set(settings.geminiLanguageHints, forKey: "geminiLanguageHints")
    defaults.set(settings.xaiFormatText, forKey: "xaiFormatText")
    defaults.set(settings.xaiVADThreshold, forKey: "xaiVADThreshold")
    defaults.set(settings.automaticVolumeLeveling, forKey: "automaticVolumeLeveling")
    defaults.set(settings.inputGainDB, forKey: "inputGainDB")
    defaults.set(settings.noiseReductionDB, forKey: "noiseReductionDB")
    defaults.set(settings.inputDeviceUID, forKey: "inputDeviceUID")
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
      defaults.removeObject(forKey: "customHotkeyKeyCode")
      defaults.removeObject(forKey: "customHotkeyModifiers")
      defaults.removeObject(forKey: "customHotkeyDisplay")
      return
    }

    defaults.set(Int(hotkey.keyCode), forKey: "customHotkeyKeyCode")
    defaults.set(Int(hotkey.modifiers), forKey: "customHotkeyModifiers")
    defaults.set(hotkey.display, forKey: "customHotkeyDisplay")
  }
}
