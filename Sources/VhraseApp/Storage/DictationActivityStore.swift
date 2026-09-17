// Retains content-free daily totals independently of transcript history and derives usage estimates.

import Foundation

struct DictationActivityDay: Codable {
  private static let typingWordsPerMinute = 55.0

  let date: Date
  var dictations = 0
  var words = 0
  var recordingSeconds = 0.0
  var processingSeconds = 0.0
  var estimatedCostUSD = 0.0

  var dictatedWordsPerMinute: Double {
    guard words > 0, recordingSeconds > 0 else {
      return 0
    }
    return Double(words) / recordingSeconds * 60
  }

  /// Compares aggregate elapsed time with a fixed typing baseline, retaining slower attempts in the total.
  var savedSeconds: Double {
    max(0, Double(words) / Self.typingWordsPerMinute * 60 - recordingSeconds - processingSeconds)
  }

  mutating func add(_ other: DictationActivityDay) {
    dictations += other.dictations
    words += other.words
    recordingSeconds += other.recordingSeconds
    processingSeconds += other.processingSeconds
    estimatedCostUSD += other.estimatedCostUSD
  }
}

final class DictationActivityStore {
  private let defaults: UserDefaults
  private let storageKey = "dictationActivityDays"

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func load() -> [DictationActivityDay] {
    guard let data = defaults.data(forKey: storageKey) else { return [] }
    do {
      return try JSONDecoder().decode([DictationActivityDay].self, from: data)
    } catch {
      NSLog("Vhrase activity decode failed: \(error.localizedDescription)")
      return []
    }
  }

  /// Counts finalized text only in memory; persistence contains no text, audio, or destination details.
  func record(
    text: String, recordingSeconds: Double, processingSeconds: Double,
    settings: DictationSettings, days: [DictationActivityDay], now: Date = Date()
  ) -> [DictationActivityDay] {
    let words = TranscriptHistoryItem.countWords(in: text)

    let date = Calendar.current.startOfDay(for: now)
    let entry = DictationActivityDay(
      date: date, dictations: 1, words: words,
      recordingSeconds: recordingSeconds, processingSeconds: processingSeconds,
      estimatedCostUSD: recordingSeconds / 3_600 * hourlyRate(settings))
    var updated = days
    if let index = updated.firstIndex(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }
    ) {
      updated[index].add(entry)
    } else {
      updated.append(entry)
    }
    do {
      defaults.set(try JSONEncoder().encode(updated), forKey: storageKey)
    } catch {
      NSLog("Vhrase activity encode failed: \(error.localizedDescription)")
    }
    return updated
  }

  // Public list rates checked 2026-09-16; Gemini uses Google's approximate blended audio/text rate.
  // Sources: https://docs.x.ai/developers/models/speech-to-text, https://elevenlabs.io/pricing/api, https://ai.google.dev/gemini-api/docs/pricing.
  private func hourlyRate(_ settings: DictationSettings) -> Double {
    switch settings.provider {
    case .xai:
      settings.transcriptionMode == .realtime ? 0.20 : 0.10
    case .elevenLabs:
      (settings.transcriptionMode == .realtime ? 0.39 : 0.22)
        + (settings.keytermList.isEmpty ? 0 : 0.05)
    case .gemini:
      0.30
    }
  }
}
