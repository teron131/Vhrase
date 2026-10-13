// Applies the same conservative silence check to dictation and setup tests before either submits audio for recognition.

import Foundation

/// Accepts very quiet speech while rejecting recordings that never rise above the existing live-waveform noise floor.
final class SpeechPresenceGate: @unchecked Sendable {
  private static let minimumLevel = 0.012
  private static let requiredChunks = 2

  private let lock = NSLock()
  private var audibleChunkCount = 0

  func observe(level: Double) {
    guard level > Self.minimumLevel else { return }
    lock.withLock {
      audibleChunkCount += 1
    }
  }

  var hasLikelySpeech: Bool {
    lock.withLock {
      audibleChunkCount >= Self.requiredChunks
    }
  }
}

enum RecordingContentError: LocalizedError {
  case noSpeechDetected

  var errorDescription: String? {
    "No speech was detected."
  }
}
