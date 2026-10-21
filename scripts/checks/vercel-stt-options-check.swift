// Verifies Vercel AI Gateway's JSON transcription request, its editable model, and persistence of that model.

import Foundation

@main
struct VercelSTTOptionsCheck {
  static func main() throws {
    var settings = DictationSettings.defaults
    settings.provider = .vercel
    settings.transcriptionMode = .upload
    precondition(STTProvider.vercel.location == .cloud)
    precondition(STTProvider.vercel.availableModes == [.upload])
    precondition(settings.vercelModel == "spacexai/grok-stt")
    // The gateway forwards no vocabulary, so a list sized for LLM polishing never blocks recording.
    precondition(!STTProvider.vercel.takesVocabularyHints)
    settings.keyterms = (1...1_200).map { "term \($0)" }.joined(separator: "\n")
    try TranscriptionContract.validate(settings: settings)

    settings.vercelModel = " openai/gpt-transcribe "
    let headers = try VercelTranscriptionContract.headers(settings: settings)
    precondition(headers["ai-model-id"] == "openai/gpt-transcribe")
    precondition(headers["ai-gateway-protocol-version"] == "0.0.1")
    precondition(headers["ai-transcription-model-specification-version"] == "4")
    precondition(headers["Content-Type"] == "application/json")
    precondition(
      VercelTranscriptionContract.endpoint.absoluteString
        == "https://ai-gateway.vercel.sh/v4/ai/transcription-model")

    let audio = Data([1, 2, 3])
    let body =
      try JSONSerialization.jsonObject(
        with: VercelTranscriptionContract.requestBody(audio: audio)) as! [String: String]
    precondition(body == ["audio": audio.base64EncodedString(), "mediaType": "audio/wav"])

    settings.vercelModel = "  "
    precondition(TranscriptionContract.configurationIssue(in: settings)?.contains("Vercel") == true)
    // A blank gateway model blocks only the gateway.
    settings.provider = .xai
    settings.keyterms = ""
    try TranscriptionContract.validate(settings: settings)

    settings.provider = .vercel
    settings.vercelModel = "google/gemini-3.5-transcribe"
    let suite = "Vhrase.VercelOptionsCheck"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = SettingsStore(defaults: defaults)
    store.save(settings)
    precondition(store.load() == settings)
    let decoded = try JSONDecoder().decode(
      CustomizationSnapshot.self,
      from: JSONEncoder().encode(CustomizationSnapshot(settings: settings)))
    precondition(decoded.settings == settings)
    print("Vercel gateway request and model persistence ok")
  }
}
