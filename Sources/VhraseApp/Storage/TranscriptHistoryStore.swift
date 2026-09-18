// Persists the complete local history of finalized transcript records.

import Foundation

final class TranscriptHistoryStore {
  private let defaults: UserDefaults
  private let historyKey = "transcriptHistory"
  private let savingKey = "saveTranscriptHistory"

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
      NSLog("Vhrase history decode failed: \(error.localizedDescription)")
      return []
    }
  }

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
      NSLog("Vhrase history encode failed: \(error.localizedDescription)")
    }
  }
}
