// Exercises the app's actual cloud upload adapters on the same explicit WAV without touching user settings or Keychain.

import Foundation

@main
struct UploadSTTSmoke {
  static func main() async throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let path = arguments.first else {
      print(
        "Usage: live-upload-stt-smoke /absolute/path/recording.wav [gemini] [xai] [elevenLabs] [openAI] [vercel]"
      )
      return
    }
    let audio = URL(fileURLWithPath: path)
    // Naming providers limits which accounts the run bills; by default every adapter with a key in the environment runs.
    let requested = arguments.dropFirst().compactMap(STTProvider.init(rawValue:))
    let providers = requested.isEmpty ? [STTProvider.gemini, .xai, .openAI, .vercel] : requested
    var settings = DictationSettings.defaults
    settings.transcriptionMode = .upload
    settings.afterTranscription = .off
    settings.keyterms = "Vercel\nrefactor\nbackpropagation\nschema\nMonte Carlo"
    for provider in providers {
      settings.provider = provider
      guard let keyName = SecretKey(provider)?.rawValue else {
        print("\(provider.title): skipped, not a cloud provider")
        continue
      }
      let key = ProcessInfo.processInfo.environment[keyName] ?? ""
      guard !key.isEmpty else {
        print("\(provider.title): skipped, \(keyName) is not in the environment")
        continue
      }
      let client: SpeechToTextClient
      switch provider {
      case .gemini: client = GeminiTranscriptionClient(apiKey: key)
      case .xai: client = XAITranscriptionClient(apiKey: key)
      case .elevenLabs: client = ElevenLabsTranscriptionClient(apiKey: key)
      case .openAI: client = OpenAITranscriptionClient(apiKey: key)
      case .vercel: client = VercelTranscriptionClient(apiKey: key)
      case .parakeet, .huggingFace: continue
      }
      let started = Date()
      let result = try await client.transcribe(fileURL: audio, settings: settings)
      guard !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw NSError(
          domain: "Vhrase.UploadSmoke", code: 1,
          userInfo: [NSLocalizedDescriptionKey: "Empty transcript from \(provider.title)"])
      }
      print(
        "\(result.providerName) (\(String(format: "%.2f", Date().timeIntervalSince(started)))s): \(result.text)"
      )
    }
  }
}
