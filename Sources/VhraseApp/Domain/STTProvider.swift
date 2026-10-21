// Names the speech-to-text providers and what each supports, recording modes, vocabulary hints, and whether it runs in the cloud or on this Mac, for the settings, request contracts, and pickers that share them.

import Foundation

enum STTProvider: String, CaseIterable, Codable, Identifiable, Sendable {
  case xai
  case elevenLabs
  case gemini
  case openAI
  case vercel
  case parakeet
  case huggingFace

  var id: String { rawValue }

  var title: String {
    switch self {
    case .xai:
      "xAI"
    case .elevenLabs:
      "ElevenLabs"
    case .gemini:
      "Gemini"
    case .openAI:
      "OpenAI"
    case .vercel:
      "Vercel"
    case .parakeet:
      "Parakeet"
    case .huggingFace:
      "Hugging Face"
    }
  }

  var availableModes: [TranscriptionMode] {
    switch self {
    case .xai, .elevenLabs: TranscriptionMode.allCases
    case .gemini, .openAI, .vercel, .parakeet, .huggingFace: [.upload]
    }
  }

  /// False for providers whose recognition ignores the shared vocabulary, leaving it to LLM polishing alone.
  var takesVocabularyHints: Bool {
    switch self {
    case .xai, .elevenLabs, .gemini, .openAI: true
    case .vercel, .parakeet, .huggingFace: false
    }
  }

  var location: ProviderLocation {
    switch self {
    case .xai, .elevenLabs, .gemini, .openAI, .vercel: .cloud
    case .parakeet, .huggingFace: .local
    }
  }

  var detail: String {
    switch self {
    case .xai: "xAI speech recognition with optional filler removal and number formatting."
    case .elevenLabs: "ElevenLabs speech recognition with verbatim controls and realtime streaming."
    case .gemini: "Gemini speech recognition with optional Smart transcription."
    case .openAI: "OpenAI speech recognition with an optional language hint."
    case .vercel:
      "Any transcription model on Vercel AI Gateway, reached with one gateway key."
    case .parakeet:
      "NVIDIA Parakeet running on this Mac. No API key, and no network once downloaded."
    case .huggingFace:
      "Any Hugging Face speech model the transformers pipeline accepts, running on this Mac. No API key, and no network once downloaded."
    }
  }
}

enum ProviderLocation: String, CaseIterable, Identifiable, Sendable {
  case cloud
  case local

  var id: String { rawValue }

  var title: String {
    switch self {
    case .cloud: "Cloud"
    case .local: "Local"
    }
  }

  /// Lists this location's providers alphabetically, the order every picker and the credential rows present them in.
  var providers: [STTProvider] {
    STTProvider.allCases
      .filter { $0.location == self }
      .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
  }
}

enum TranscriptionMode: String, CaseIterable, Codable, Identifiable, Sendable {
  case upload
  case realtime

  var id: String { rawValue }

  /// Names after-stop transcription by where it runs, so on-device recognition never reads as an upload.
  func title(for provider: STTProvider) -> String {
    switch self {
    case .upload:
      provider.location == .local ? "After stop" : "Upload"
    case .realtime:
      "Realtime"
    }
  }
}
