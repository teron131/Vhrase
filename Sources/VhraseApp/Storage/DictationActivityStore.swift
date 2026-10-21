// Retains content-free daily totals independently of transcript history and derives usage estimates.

import Foundation
import OSLog

struct DictationActivityDay: Codable {
  private static let typingWordsPerMinute = 55.0

  let date: Date
  var dictations = 0
  var words = 0
  var recordingSeconds = 0.0
  var processingSeconds = 0.0
  /// Transcription and LLM polishing together.
  var estimatedCostUSD = 0.0
  /// The part of `estimatedCostUSD` spent on LLM polishing, automatic or double-tap.
  var polishingCostUSD = 0.0

  var transcriptionCostUSD: Double {
    estimatedCostUSD - polishingCostUSD
  }

  var dictatedWordsPerMinute: Double {
    guard words > 0, recordingSeconds > 0 else {
      return 0
    }
    return Double(words) / recordingSeconds * 60
  }

  /// Clamps the period's total rather than each dictation, so a dictation slower than typing still counts against the others.
  var savedSeconds: Double {
    max(0, Double(words) / Self.typingWordsPerMinute * 60 - recordingSeconds - processingSeconds)
  }

  mutating func add(_ other: DictationActivityDay) {
    dictations += other.dictations
    words += other.words
    recordingSeconds += other.recordingSeconds
    processingSeconds += other.processingSeconds
    estimatedCostUSD += other.estimatedCostUSD
    polishingCostUSD += other.polishingCostUSD
  }
}

extension DictationActivityDay {
  /// Days saved before polishing was priced have no `polishingCostUSD`; their whole cost was transcription.
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    date = try values.decode(Date.self, forKey: .date)
    dictations = try values.decode(Int.self, forKey: .dictations)
    words = try values.decode(Int.self, forKey: .words)
    recordingSeconds = try values.decode(Double.self, forKey: .recordingSeconds)
    processingSeconds = try values.decode(Double.self, forKey: .processingSeconds)
    estimatedCostUSD = try values.decode(Double.self, forKey: .estimatedCostUSD)
    polishingCostUSD = try values.decodeIfPresent(Double.self, forKey: .polishingCostUSD) ?? 0
  }
}

final class DictationActivityStore {
  private let defaults: UserDefaults
  private let storageKey = "dictationActivityDays"
  private let logger = Logger(subsystem: "local.codex.Vhrase", category: "Activity")

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func load() -> [DictationActivityDay] {
    guard let data = defaults.data(forKey: storageKey) else { return [] }
    do {
      return try JSONDecoder().decode([DictationActivityDay].self, from: data)
    } catch {
      let failure = error as NSError
      logger.error(
        "Activity decode failed domain=\(failure.domain, privacy: .public) code=\(failure.code)")
      return []
    }
  }

  /// Counts finalized text only in memory; persistence contains no text, audio, or destination details.
  func record(
    text: String, recordingSeconds: Double, processingSeconds: Double,
    settings: DictationSettings, days: [DictationActivityDay], now: Date = Date()
  ) -> [DictationActivityDay] {
    let words = TranscriptHistoryItem.countWords(in: text)

    return merge(
      DictationActivityDay(
        date: Calendar.current.startOfDay(for: now), dictations: 1, words: words,
        recordingSeconds: recordingSeconds, processingSeconds: processingSeconds,
        estimatedCostUSD: recordingSeconds / 3_600 * hourlyRate(settings)),
      into: days)
  }

  /// Adds one polish's estimated LLM cost to today without counting a dictation, since double-tap polishing rewrites text that was never dictated.
  func recordPolishing(
    costUSD: Double, days: [DictationActivityDay], now: Date = Date()
  ) -> [DictationActivityDay] {
    merge(
      DictationActivityDay(
        date: Calendar.current.startOfDay(for: now), estimatedCostUSD: costUSD,
        polishingCostUSD: costUSD),
      into: days)
  }

  private func merge(
    _ entry: DictationActivityDay, into days: [DictationActivityDay]
  ) -> [DictationActivityDay] {
    var updated = days
    if let index = updated.firstIndex(where: {
      Calendar.current.isDate($0.date, inSameDayAs: entry.date)
    }) {
      updated[index].add(entry)
    } else {
      updated.append(entry)
    }
    do {
      defaults.set(try JSONEncoder().encode(updated), forKey: storageKey)
    } catch {
      let failure = error as NSError
      logger.error(
        "Activity encode failed domain=\(failure.domain, privacy: .public) code=\(failure.code)")
    }
    return updated
  }

  // Public list rates checked 2026-09-16, OpenAI's on 2026-10-12; Gemini uses Google's approximate blended audio/text rate.
  // Sources: https://docs.x.ai/developers/models/speech-to-text, https://elevenlabs.io/pricing/api, https://ai.google.dev/gemini-api/docs/pricing, https://developers.openai.com/api/docs/pricing.
  private func hourlyRate(_ settings: DictationSettings) -> Double {
    switch settings.provider {
    case .xai:
      settings.transcriptionMode == .realtime ? 0.20 : 0.10
    case .elevenLabs:
      (settings.transcriptionMode == .realtime ? 0.39 : 0.22)
        + (settings.keytermList.isEmpty ? 0 : 0.05)
    case .gemini:
      0.30
    case .openAI:
      0.27
    case .vercel:
      // The gateway bills each model at its provider's list rate; other models are estimated at the common $0.006 per minute.
      settings.vercelModel == DictationSettings.defaultVercelModel ? 0.10 : 0.36
    case .parakeet, .huggingFace:
      0
    }
  }
}
