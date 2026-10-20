// Defines transcription results, cleanup provenance, delivery outcomes, and persisted history records.

import Foundation
import NaturalLanguage

struct FrontmostApp: Sendable {
  let name: String
  let bundleIdentifier: String
}

struct TranscriptionResult: Sendable {
  let text: String
  let providerName: String
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

/// Captures the exact text and instruction pair used by a successful LLM cleanup for later prompt evaluation.
struct LLMRefinement: Codable, Equatable, Sendable {
  let input: String
  let output: String
  let model: String
  let systemInstruction: String
  let includedScreenshot: Bool
  /// `nil` when the endpoint reported no usage, and for transcripts saved before Vhrase read it.
  let usage: LLMUsage?
}

/// Prompt-cache hits are not broken out, because Vercel AI Gateway's chat endpoint omits them.
struct LLMUsage: Codable, Equatable, Sendable {
  let inputTokens: Int
  let outputTokens: Int
}

enum TranscriptDelivery: Equatable, Sendable {
  case none
  case copied
  case pasteCommandSent(clipboardRetained: Bool)
}

enum WorkflowCompletion: Equatable, Sendable {
  case transcript(TranscriptDelivery)
  case textPolished

  var isTranscript: Bool {
    if case .transcript = self {
      return true
    }
    return false
  }
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
  // Absent on older history and non-LLM results.
  var refinement: LLMRefinement? = nil
  // Absent on older history and demos; processing includes finalization and delivery after recording stops.
  var recordingSeconds: Double? = nil
  var transcriptionSeconds: Double? = nil
  var processingSeconds: Double? = nil

  var wordCount: Int { Self.countWords(in: text) }

  /// Counts language-aware words consistently for historical text and aggregate activity.
  static func countWords(in text: String) -> Int {
    let tokenizer = NLTokenizer(unit: .word)
    tokenizer.string = text
    var count = 0
    tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
      if text[range].unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) }) {
        count += 1
      }
      return true
    }
    return count
  }
}
