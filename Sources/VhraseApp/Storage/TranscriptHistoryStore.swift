// Persists the complete local history of finalized transcript records.

import Foundation
import OSLog

final class TranscriptHistoryStore {
  private let defaults: UserDefaults
  private let historyKey = "transcriptHistory"
  private let savingKey = "saveTranscriptHistory"
  private let logger = Logger(subsystem: "local.codex.Vhrase", category: "History")

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  var savesHistory: Bool {
    defaults.object(forKey: savingKey) == nil || defaults.bool(forKey: savingKey)
  }

  func setSavingEnabled(_ isEnabled: Bool) {
    defaults.set(isEnabled, forKey: savingKey)
  }

  func load() -> [TranscriptHistoryItem] {
    guard let data = defaults.data(forKey: historyKey) else {
      return []
    }

    do {
      return try JSONDecoder().decode([TranscriptHistoryItem].self, from: data)
    } catch {
      let failure = error as NSError
      logger.error(
        "History decode failed domain=\(failure.domain, privacy: .public) code=\(failure.code)")
      return []
    }
  }

  /// While saving is off, returns `history` unchanged, so the transcript appears nowhere in History.
  func prepend(_ item: TranscriptHistoryItem, to history: [TranscriptHistoryItem])
    -> [TranscriptHistoryItem]
  {
    guard savesHistory else {
      return history
    }

    let next = [item] + history.filter { $0.id != item.id }
    save(next)
    return next
  }

  func remove(_ item: TranscriptHistoryItem, from history: [TranscriptHistoryItem])
    -> [TranscriptHistoryItem]
  {
    let next = history.filter { $0.id != item.id }
    save(next)
    return next
  }

  func clear() {
    defaults.removeObject(forKey: historyKey)
  }

  private func save(_ history: [TranscriptHistoryItem]) {
    do {
      let data = try JSONEncoder().encode(history)
      defaults.set(data, forKey: historyKey)
    } catch {
      let failure = error as NSError
      logger.error(
        "History encode failed domain=\(failure.domain, privacy: .public) code=\(failure.code)")
    }
  }
}
