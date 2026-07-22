// Persists a bounded local history of finalized transcript records.

import Foundation

final class TranscriptHistoryStore {
    private let defaults = UserDefaults.standard
    private let key = "transcriptHistory"
    private let limit = 30

    func load() -> [TranscriptHistoryItem] {
        guard let data = defaults.data(forKey: key) else {
            return []
        }

        do {
            return try JSONDecoder().decode([TranscriptHistoryItem].self, from: data)
        } catch {
            NSLog("Vhrase history decode failed: \(error.localizedDescription)")
            return []
        }
    }

    func prepend(_ item: TranscriptHistoryItem, to history: [TranscriptHistoryItem]) -> [TranscriptHistoryItem] {
        let next = [item] + history.filter { $0.id != item.id }
        let trimmed = Array(next.prefix(limit))
        save(trimmed)
        return trimmed
    }

    func remove(_ item: TranscriptHistoryItem, from history: [TranscriptHistoryItem]) -> [TranscriptHistoryItem] {
        let next = history.filter { $0.id != item.id }
        save(next)
        return next
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }

    private func save(_ history: [TranscriptHistoryItem]) {
        do {
            let data = try JSONEncoder().encode(history)
            defaults.set(data, forKey: key)
        } catch {
            NSLog("Vhrase history encode failed: \(error.localizedDescription)")
        }
    }
}
