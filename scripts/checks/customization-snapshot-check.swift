// Verifies production customization export round trips while excluding API credentials.

import Foundation

@main
struct CustomizationSnapshotCheck {
  static func main() throws {
    var settings = DictationSettings.defaults
    settings.provider = .elevenLabs
    settings.transcriptionMode = .realtime
    settings.language = ""
    settings.keyterms = "OpenAI\nxAI"
    settings.replacementRules = "open AI => OpenAI"
    settings.adjustmentPrompt = "Keep identifiers intact."
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

    let decoded = try JSONDecoder().decode(CustomizationSnapshot.self, from: data)
    precondition(decoded == snapshot)
    try decoded.settings.validateLocalConfiguration()

    var oldExport = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    var oldSettings = oldExport["settings"] as! [String: Any]
    for key in ["automaticVolumeLeveling", "inputGainDB", "noiseReductionDB", "inputDeviceUID"] {
      oldSettings.removeValue(forKey: key)
    }
    oldExport["settings"] = oldSettings
    let migrated = try JSONDecoder().decode(
      CustomizationSnapshot.self, from: JSONSerialization.data(withJSONObject: oldExport))
    precondition(migrated.settings.automaticVolumeLeveling)
    precondition(migrated.settings.inputGainDB == 0 && migrated.settings.noiseReductionDB == 6)
    precondition(migrated.settings.keyterms == settings.keyterms)
    precondition(migrated.settings.inputDeviceUID.isEmpty)

    var invalidSettings = decoded.settings
    invalidSettings.elevenLabsVADThreshold = 1.1
    precondition(rejectsLocalConfiguration(invalidSettings))
    invalidSettings = settings
    invalidSettings.inputGainDB = .nan
    precondition(rejectsLocalConfiguration(invalidSettings))
    invalidSettings = settings
    invalidSettings.noiseReductionDB = 13
    precondition(rejectsLocalConfiguration(invalidSettings))

    let suiteName = "Vhrase.SettingsStoreCheck"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      preconditionFailure("Could not create isolated settings defaults.")
    }
    defaults.removePersistentDomain(forName: suiteName)
    let store = SettingsStore(defaults: defaults)
    store.save(settings)
    precondition(store.load().language.isEmpty)
    precondition(store.load().keepTranscriptOnClipboard)
    precondition(store.load().automaticVolumeLeveling == settings.automaticVolumeLeveling)
    precondition(store.load().inputGainDB == -3 && store.load().noiseReductionDB == 9)
    precondition(store.load().inputDeviceUID == "test-microphone-uid")
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
