// Verifies the local Parakeet provider's after-stop-only contract, its labels, vocabulary policy, and persistence.

import Foundation

@main
struct ParakeetOptionsCheck {
  static func main() throws {
    var settings = DictationSettings.defaults
    settings.provider = .parakeet
    settings.transcriptionMode = .upload
    precondition(STTProvider.parakeet.availableModes == [.upload])
    // Each location lists its providers alphabetically by title, ignoring case, so xAI sorts last.
    precondition(ProviderLocation.local.providers == [.huggingFace, .parakeet])
    precondition(
      ProviderLocation.cloud.providers == [.elevenLabs, .gemini, .openAI, .vercel, .xai])
    precondition(settings.transcriptionModeTitle == "After stop")
    precondition(TranscriptionMode.upload.title(for: .xai) == "Upload")

    // Parakeet receives no vocabulary, so a list sized for LLM polishing never blocks recording.
    settings.keyterms = (1...1_200).map { "term \($0) " + String(repeating: "x", count: 60) }
      .joined(separator: "\n")
    try TranscriptionContract.validate(settings: settings)

    settings.transcriptionMode = .realtime
    do {
      try TranscriptionContract.validate(settings: settings)
      preconditionFailure("Accepted realtime Parakeet transcription")
    } catch {
      precondition(error.localizedDescription.contains("After stop"))
    }
    do {
      _ = try RealtimeTranscriptionSession.start(settings: settings, apiKey: "") { _ in }
      preconditionFailure("Opened a realtime session for Parakeet")
    } catch {
      precondition(error.localizedDescription.contains("Parakeet"))
    }

    settings.transcriptionMode = .upload
    settings.keyterms = "Vercel"
    let suite = "Vhrase.ParakeetOptionsCheck"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = SettingsStore(defaults: defaults)
    store.save(settings)
    precondition(store.load() == settings)
    defaults.set(TranscriptionMode.realtime.rawValue, forKey: "transcriptionMode")
    precondition(store.load().transcriptionMode == .upload)

    let snapshot = CustomizationSnapshot(settings: settings)
    let decoded = try JSONDecoder().decode(
      CustomizationSnapshot.self, from: JSONEncoder().encode(snapshot))
    precondition(decoded.settings.provider == .parakeet)
    print("parakeet options ok")
  }
}
