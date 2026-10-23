// Verifies production customization export round trips while excluding API credentials.

import Foundation

@main
struct CustomizationSnapshotCheck {
  static func main() throws {
    var settings = DictationSettings.defaults
    settings.adjustmentModel = "test-model"
    settings.provider = .elevenLabs
    settings.transcriptionMode = .realtime
    settings.language = ""
    settings.keyterms = "OpenAI\nxAI"
    settings.adjustmentPrompt = "Keep identifiers intact."
    let customStyle = PolishStyle(
      title: "Unlisted style", instruction: "Group related ideas into short paragraphs.")
    settings.restyleChoice = .custom
    settings.customRestyleName = customStyle.title
    settings.customRestyleInstruction = customStyle.instruction
    settings.afterTranscription = .restyle
    settings.polishPreferences.moneyStyle = .symbols
    settings.polishPreferences.unitStyle = .spelledOut
    settings.polishPreferences.removesFillerWords = false
    settings.polishPreferences.resolvesSpokenCorrections = false
    settings.keepTranscriptOnClipboard = true
    settings.automaticVolumeLeveling = false
    settings.inputGainDB = -3
    settings.noiseReductionDB = 9
    settings.inputDeviceUID = "test-microphone-uid"

    let snapshot = CustomizationSnapshot(settings: settings)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(snapshot)
    let json = String(decoding: data, as: UTF8.self)
    precondition(!json.contains("\"version\""))
    precondition(!json.localizedCaseInsensitiveContains("apiKey"))
    precondition(!json.localizedCaseInsensitiveContains("XAI_API_KEY"))
    precondition(!json.localizedCaseInsensitiveContains("ELEVENLABS_API_KEY"))
    precondition(!json.localizedCaseInsensitiveContains("LLM_API_KEY"))
    precondition(json.contains("\"keepTranscriptOnClipboard\" : true"))
    precondition(!json.contains("pasteAfterTranscription"))
    precondition(!json.contains("replacementRules"))

    let decoded = try JSONDecoder().decode(CustomizationSnapshot.self, from: data)
    precondition(decoded == snapshot)
    try decoded.settings.validateLocalConfiguration()

    var priorExport = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    var priorSettings = priorExport["settings"] as! [String: Any]
    var priorPreferences = priorSettings["polishPreferences"] as! [String: Any]
    priorPreferences.removeValue(forKey: "removesFillerWords")
    priorPreferences.removeValue(forKey: "resolvesSpokenCorrections")
    priorSettings["polishPreferences"] = priorPreferences
    priorExport["settings"] = priorSettings
    let migratedPreferences = try JSONDecoder().decode(
      CustomizationSnapshot.self, from: JSONSerialization.data(withJSONObject: priorExport))
    precondition(migratedPreferences.settings.polishPreferences.removesFillerWords)
    precondition(migratedPreferences.settings.polishPreferences.resolvesSpokenCorrections)

    var oldExport = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    var oldSettings = oldExport["settings"] as! [String: Any]
    for key in [
      "automaticVolumeLeveling", "inputGainDB", "noiseReductionDB", "inputDeviceUID",
      "polishPreferences", "restyleChoice", "customRestyleName", "customRestyleInstruction",
      "afterTranscription",
    ] {
      oldSettings.removeValue(forKey: key)
    }
    oldExport["settings"] = oldSettings
    let migrated = try JSONDecoder().decode(
      CustomizationSnapshot.self, from: JSONSerialization.data(withJSONObject: oldExport))
    precondition(migrated.settings.automaticVolumeLeveling)
    precondition(migrated.settings.inputGainDB == 0 && migrated.settings.noiseReductionDB == 6)
    precondition(migrated.settings.keyterms == settings.keyterms)
    precondition(migrated.settings.inputDeviceUID.isEmpty)
    precondition(migrated.settings.polishPreferences == .defaults)
    precondition(
      migrated.settings.polishStyle == .rephrase && migrated.settings.afterTranscription == .refine)
    precondition(migrated.settings.restyleChoice == .rephrase)
    precondition(migrated.settings.customRestyleName == "Custom")
    precondition(migrated.settings.customRestyleInstruction.isEmpty)
    for choice in RestyleChoice.allCases {
      var styled = DictationSettings.defaults
      styled.restyleChoice = choice
      styled.customRestyleName = customStyle.title
      styled.customRestyleInstruction = customStyle.instruction
      styled.afterTranscription = .restyle
      precondition(PolishPreset.matching(styled.polishPreferences) == .minimal)
      let encoded = try JSONEncoder().encode(CustomizationSnapshot(settings: styled))
      let restored = try JSONDecoder().decode(CustomizationSnapshot.self, from: encoded)
      precondition(restored.settings == styled)
      let document = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
      let values = document["settings"] as! [String: Any]
      precondition(values["restyleChoice"] as? String == choice.rawValue)
      precondition(values["customRestyleName"] as? String == customStyle.title)
      precondition(values["customRestyleInstruction"] as? String == customStyle.instruction)
      precondition(values["polishStyle"] == nil)
    }

    var invalidSettings = decoded.settings
    invalidSettings.elevenLabsVADThreshold = 1.1
    precondition(rejectsLocalConfiguration(invalidSettings))
    invalidSettings = settings
    invalidSettings.inputGainDB = .nan
    precondition(rejectsLocalConfiguration(invalidSettings))
    invalidSettings = settings
    invalidSettings.noiseReductionDB = 13
    precondition(rejectsLocalConfiguration(invalidSettings))

    invalidSettings = settings
    invalidSettings.customRestyleName = " \n"
    precondition(invalidSettings.polishStyle.title == "Custom")
    try invalidSettings.validateLocalConfiguration()
    invalidSettings.customRestyleInstruction = " \n\t"
    for mode in DictationPolishing.allCases {
      invalidSettings.afterTranscription = mode
      for choice in RestyleChoice.allCases {
        invalidSettings.restyleChoice = choice
        precondition(
          rejectsLocalConfiguration(invalidSettings) == (choice == .custom && mode == .restyle))
      }
    }

    for enabled in [false, true] {
      oldSettings["adjustWithLLM"] = enabled
      oldExport["settings"] = oldSettings
      let legacy = try JSONDecoder().decode(
        CustomizationSnapshot.self, from: JSONSerialization.data(withJSONObject: oldExport))
      precondition(legacy.settings.afterTranscription == (enabled ? .refine : .off))
    }
    oldSettings["afterTranscription"] = "restyle"
    oldSettings["adjustWithLLM"] = false
    oldExport["settings"] = oldSettings
    let current = try JSONDecoder().decode(
      CustomizationSnapshot.self, from: JSONSerialization.data(withJSONObject: oldExport))
    precondition(current.settings.afterTranscription == .restyle)
    for mode in DictationPolishing.allCases {
      var selected = settings
      selected.afterTranscription = mode
      let encoded = try JSONEncoder().encode(CustomizationSnapshot(settings: selected))
      let restored = try JSONDecoder().decode(CustomizationSnapshot.self, from: encoded)
      precondition(restored.settings == selected)
      let json = String(decoding: encoded, as: UTF8.self)
      precondition(!json.contains("adjustWithLLM") && !json.contains("useStyleForDictation"))
    }

    let suiteName = "Vhrase.SettingsStoreCheck"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      preconditionFailure("Could not create isolated settings defaults.")
    }
    defaults.removePersistentDomain(forName: suiteName)
    let store = SettingsStore(defaults: defaults)
    precondition(
      store.load().polishStyle == .rephrase && store.load().afterTranscription == .off
        && store.load().adjustmentModel.isEmpty)
    precondition(
      store.load().customRestyleName == "Custom" && store.load().customRestyleInstruction.isEmpty)
    for enabled in [false, true] {
      defaults.removeObject(forKey: "afterTranscription")
      defaults.set(enabled, forKey: "adjustWithLLM")
      let migrated = store.load()
      precondition(migrated.afterTranscription == (enabled ? .refine : .off))
      store.save(migrated)
      precondition(defaults.object(forKey: "adjustWithLLM") == nil)
      precondition(
        defaults.string(forKey: "afterTranscription") == migrated.afterTranscription.rawValue)
    }
    defaults.set("restyle", forKey: "afterTranscription")
    defaults.set(false, forKey: "adjustWithLLM")
    precondition(store.load().afterTranscription == .restyle)
    for mode in DictationPolishing.allCases {
      var selected = settings
      selected.afterTranscription = mode
      store.save(selected)
      precondition(SettingsStore(defaults: defaults).load().afterTranscription == mode)
    }
    store.save(settings)
    precondition(
      store.load().polishStyle == customStyle && store.load().afterTranscription == .restyle)
    precondition(store.load().language.isEmpty)
    precondition(store.load().keepTranscriptOnClipboard)
    precondition(store.load().polishPreferences.moneyStyle == .symbols)
    precondition(store.load().polishPreferences.unitStyle == .spelledOut)
    precondition(!store.load().polishPreferences.removesFillerWords)
    precondition(!store.load().polishPreferences.resolvesSpokenCorrections)
    precondition(store.load().automaticVolumeLeveling == settings.automaticVolumeLeveling)
    precondition(store.load().inputGainDB == -3 && store.load().noiseReductionDB == 9)
    precondition(store.load().inputDeviceUID == "test-microphone-uid")
    for choice in RestyleChoice.allCases {
      var switched = store.load()
      switched.restyleChoice = choice
      store.save(switched)
      let reopened = SettingsStore(defaults: defaults).load()
      precondition(reopened.restyleChoice == choice)
      precondition(reopened.customRestyleName == customStyle.title)
      precondition(reopened.customRestyleInstruction == customStyle.instruction)
      precondition(defaults.string(forKey: "restyleChoice") == choice.rawValue)
      switch choice {
      case .rephrase: precondition(reopened.polishStyle == .rephrase)
      case .genZ: precondition(reopened.polishStyle == .genZ)
      case .custom: precondition(reopened.polishStyle == customStyle)
      }
    }
    for key in ["polishStyleTitle", "polishStyleInstruction", "polishStyleExample"] {
      precondition(defaults.object(forKey: key) == nil)
    }
    defaults.set(100, forKey: "inputGainDB")
    defaults.set(-5, forKey: "noiseReductionDB")
    precondition(store.load().inputGainDB == 6 && store.load().noiseReductionDB == 0)
    defaults.removePersistentDomain(forName: suiteName)
    print("customization snapshot ok")
  }

  private static func rejectsLocalConfiguration(_ settings: DictationSettings) -> Bool {
    do {
      try settings.validateLocalConfiguration()
      return false
    } catch {
      return true
    }
  }
}
