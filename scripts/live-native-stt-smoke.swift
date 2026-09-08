// Exercises the app's actual Gemini and Grok upload adapters on the same explicit WAV without touching user settings or Keychain.

import Foundation

@main
struct NativeSTTSmoke {
  static func main() async throws {
    guard CommandLine.arguments.count == 2 else {
      print("Usage: live-native-stt-smoke /absolute/path/recording.wav")
      return
    }
    let audio = URL(fileURLWithPath: CommandLine.arguments[1])
    var settings = DictationSettings.defaults
    settings.transcriptionMode = .upload
    settings.adjustWithLLM = false
    settings.keyterms = "Vercel\nrefactor\nbackpropagation\nschema\nMonte Carlo"
    for provider in [STTProvider.gemini, .xai] {
      settings.provider = provider
      let keyName = provider == .gemini ? "GEMINI_API_KEY" : "XAI_API_KEY"
      let key = ProcessInfo.processInfo.environment[keyName] ?? ""
      let client: SpeechToTextClient =
        provider == .gemini
        ? GeminiTranscriptionClient(apiKey: key) : XAITranscriptionClient(apiKey: key)
      let started = Date()
      let result = try await client.transcribe(fileURL: audio, settings: settings)
      guard !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw NSError(
          domain: "Vhrase.NativeSmoke", code: 1,
          userInfo: [NSLocalizedDescriptionKey: "Empty transcript from \(provider.title)"])
      }
      print(
        "\(result.providerName) (\(String(format: "%.2f", Date().timeIntervalSince(started)))s): \(result.text)"
      )
    }
  }
}
