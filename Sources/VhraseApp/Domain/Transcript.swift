// Defines transcription results, cleanup provenance, delivery outcomes, and persisted history records.

import Foundation

struct FrontmostApp: Sendable {
  let name: String
  let bundleIdentifier: String
}

struct TranscriptionResult: Sendable {
  let text: String
  let providerName: String
  let duration: Double?
}

enum TranscriptCleanup: String, Codable, Equatable, Sendable {
  case raw
  case llm
  case localFallback
  case demo

  var title: String {
    switch self {
    case .raw: "Raw"
    case .llm: "LLM cleanup"
    case .localFallback: "Local fallback"
    case .demo: "Demo cleanup"
    }
  }
}

enum TranscriptDelivery: Equatable, Sendable {
  case none
  case copied
  case pasteCommandSent(clipboardRetained: Bool)
}

struct TranscriptHistoryItem: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let createdAt: Date
  let text: String
  let provider: String
  let transcriptionMode: String
  let cleanup: TranscriptCleanup
  let targetAppName: String?
  let targetAppBundleIdentifier: String?
}
