// Verifies the on-device Hugging Face provider's model IDs, after-stop-only contract, language hint, and persistence.

import Foundation

@main
struct HuggingFaceOptionsCheck {
  static func main() throws {
    var settings = DictationSettings.defaults
    settings.provider = .huggingFace
    settings.transcriptionMode = .upload
    precondition(STTProvider.huggingFace.location == .local)
    precondition(STTProvider.huggingFace.availableModes == [.upload])
    precondition(!STTProvider.huggingFace.takesVocabularyHints)
    precondition(settings.transcriptionModeTitle == "After stop")
    precondition(settings.huggingFaceModel == "openai/whisper-large-v3-turbo")
    try TranscriptionContract.validate(settings: settings)
    settings.language = " yue "
    precondition(settings.recognitionLanguage == "yue")

    let builtIn = try HuggingFaceModelReference(settings.huggingFaceModel)
    precondition(builtIn.id == "openai/whisper-large-v3-turbo")
    precondition(builtIn.cacheFolderName == "models--openai--whisper-large-v3-turbo")
    let other = try HuggingFaceModelReference(" nvidia/parakeet-tdt-0.6b-v3 ")
    precondition(other.id == "nvidia/parakeet-tdt-0.6b-v3")
    let ownerless = try HuggingFaceModelReference("gpt2")
    precondition(ownerless.cacheFolderName == "models--gpt2")

    // An ID becomes a folder in the Hub cache, so it may neither leave the Models folder nor imitate the cache's own separator.
    for id in [
      "", "  ", "a/b/c", "../../etc", "a/..", "owner/na me", "owner/-name", "owner/name.",
      "owner--name/model", "/model", "owner/", "模型/名", String(repeating: "a", count: 97),
    ] {
      do {
        _ = try HuggingFaceModelReference(id)
        preconditionFailure("Accepted the Hugging Face model ID “\(id)”")
      } catch {
        precondition(error.localizedDescription.contains("Hugging Face model ID"))
      }
    }

    settings.huggingFaceModel = "owner/na me"
    precondition(
      TranscriptionContract.configurationIssue(in: settings)?.contains("Hugging Face") == true)
    // An unusable model ID blocks only the provider that would use it.
    settings.provider = .parakeet
    try TranscriptionContract.validate(settings: settings)

    settings.provider = .huggingFace
    settings.huggingFaceModel = "nvidia/parakeet-tdt-0.6b-v3"
    settings.transcriptionMode = .realtime
    do {
      try TranscriptionContract.validate(settings: settings)
      preconditionFailure("Accepted realtime Hugging Face transcription")
    } catch {
      precondition(error.localizedDescription.contains("After stop"))
    }

    settings.transcriptionMode = .upload
    let suite = "Vhrase.HuggingFaceOptionsCheck"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = SettingsStore(defaults: defaults)
    store.save(settings)
    precondition(store.load() == settings)
    let decoded = try JSONDecoder().decode(
      CustomizationSnapshot.self,
      from: JSONEncoder().encode(CustomizationSnapshot(settings: settings)))
    precondition(decoded.settings == settings)

    // Exports written before these providers existed carry neither model and take the defaults.
    var legacy =
      try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(CustomizationSnapshot(settings: settings))) as! [String: Any]
    var legacySettings = legacy["settings"] as! [String: Any]
    legacySettings["huggingFaceModel"] = nil
    legacySettings["vercelModel"] = nil
    legacy["settings"] = legacySettings
    let migrated = try JSONDecoder().decode(
      CustomizationSnapshot.self, from: JSONSerialization.data(withJSONObject: legacy))
    precondition(migrated.settings.huggingFaceModel == HuggingFaceModelReference.whisperTurbo)
    precondition(migrated.settings.vercelModel == DictationSettings.defaultVercelModel)
    print("hugging face options ok")
  }
}
