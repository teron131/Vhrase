// Verifies the native Gemini request, shared-vocabulary limits, and persistence of provider-specific controls.

import Foundation

@main
struct GeminiSTTOptionsCheck {
  static func main() throws {
    var settings = DictationSettings.defaults
    settings.provider = .gemini
    settings.transcriptionMode = .upload
    settings.geminiSmartTranscription = true
    settings.geminiLanguageHints = "en-US, yue-Hant-HK"
    settings.keyterms = " Vercel\nrefactor\nVercel\n\nMonte Carlo"
    let audio = Data([1, 2, 3])
    let json =
      try JSONSerialization.jsonObject(
        with: GeminiTranscriptionContract.requestBody(audio: audio, settings: settings))
      as! [String: Any]
    precondition(json["model"] as? String == "gemini-3.5-transcribe")
    precondition(json["store"] as? Bool == false)
    let input = (json["input"] as! [[String: Any]])[0]
    precondition(input["data"] as? String == audio.base64EncodedString())
    precondition(input["mime_type"] as? String == "audio/wav")
    let generation = json["generation_config"] as! [String: Any]
    let config = generation["transcription_config"] as! [String: Any]
    precondition(config["mode"] as? String == "smart")
    precondition(config["custom_vocabulary"] as? [String] == ["Vercel", "refactor", "Monte Carlo"])
    precondition(config["language_codes"] as? [String] == ["en-US", "yue-Hant-HK"])
    settings.geminiSmartTranscription = false
    settings.geminiLanguageHints = ""
    settings.keyterms = ""
    let verbatim =
      try JSONSerialization.jsonObject(
        with: GeminiTranscriptionContract.requestBody(audio: audio, settings: settings))
      as! [String: Any]
    let raw =
      (verbatim["generation_config"] as! [String: Any])["transcription_config"] as! [String: Any]
    precondition((raw["mode"] as? [String: String])?["type"] == "verbatim")
    precondition(raw["custom_vocabulary"] == nil && raw["language_codes"] == nil)
    settings.keyterms = (1...1_000).map { "term \($0)" }.joined(separator: "\n")
    try TranscriptionContract.validate(settings: settings)
    settings.keyterms += "\nextra term"
    do {
      try TranscriptionContract.validate(settings: settings)
      preconditionFailure("Accepted more than 1,000 Gemini terms")
    } catch {
      precondition(
        error.localizedDescription.contains("1,000") || error.localizedDescription.contains("1000"))
    }
    settings.keyterms = "Vercel"
    settings.xaiFormatText = false
    settings.xaiVADThreshold = 0.03
    let suite = "Vhrase.GeminiOptionsCheck"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = SettingsStore(defaults: defaults)
    store.save(settings)
    precondition(store.load() == settings)
    let snapshot = CustomizationSnapshot(settings: settings)
    let decoded = try JSONDecoder().decode(
      CustomizationSnapshot.self, from: JSONEncoder().encode(snapshot))
    precondition(decoded == snapshot)
    settings.transcriptionMode = .realtime
    do {
      try TranscriptionContract.validate(settings: settings)
      preconditionFailure("Accepted unsupported Gemini streaming")
    } catch { precondition(error.localizedDescription.contains("Upload")) }
    settings.provider = .xai
    let fields = try XAITranscriptionContract.uploadFields(settings: settings)
    precondition(!fields.contains { $0.0 == "format" || $0.0 == "language" })
    let query = try XAITranscriptionContract.realtimeQueryItems(settings: settings)
    precondition(query.first { $0.name == "vad_threshold" }?.value == "0.03")
    print("Gemini native request and shared vocabulary persistence ok")
  }
}
