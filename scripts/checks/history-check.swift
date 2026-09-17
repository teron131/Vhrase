// Verifies the current transcript-history record round trips through its persisted JSON shape.

import Foundation

@main
struct HistoryCheck {
  static func main() throws {
    let item = TranscriptHistoryItem(
      id: UUID(),
      createdAt: Date(timeIntervalSince1970: 1_800_000_000),
      text: "Hello from dictation.",
      provider: "xAI Realtime",
      transcriptionMode: "Realtime",
      cleanup: .llm,
      targetAppName: "Code",
      targetAppBundleIdentifier: "com.microsoft.VSCode"
    )

    let data = try JSONEncoder().encode([item])
    let decoded = try JSONDecoder().decode([TranscriptHistoryItem].self, from: data)
    precondition(decoded == [item])
    precondition(decoded[0].wordCount == 3)
    precondition(decoded[0].recordingSeconds == nil)
    var measured = item
    measured.recordingSeconds = 12.5
    measured.transcriptionSeconds = 0.82
    measured.processingSeconds = 1.94
    let measuredData = try JSONEncoder().encode(measured)
    let measuredDecoded = try JSONDecoder().decode(TranscriptHistoryItem.self, from: measuredData)
    precondition(measuredDecoded == measured)
    var oldShape = try JSONSerialization.jsonObject(with: measuredData) as! [String: Any]
    oldShape.removeValue(forKey: "recordingSeconds")
    oldShape.removeValue(forKey: "transcriptionSeconds")
    oldShape.removeValue(forKey: "processingSeconds")
    let oldData = try JSONSerialization.data(withJSONObject: oldShape)
    let oldItem = try JSONDecoder().decode(TranscriptHistoryItem.self, from: oldData)
    precondition(oldItem == item)

    let suiteName = "Vhrase.History.Check.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      preconditionFailure("Could not create isolated history defaults")
    }
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }
    let store = TranscriptHistoryStore(defaults: defaults)
    precondition(store.savesHistory)
    store.setSavingEnabled(false)
    precondition(!store.savesHistory)
    precondition(store.prepend(item, to: []).isEmpty)
    store.setSavingEnabled(true)
    precondition(store.prepend(item, to: []).first == item)
    _ = store.prepend(measured, to: [])
    let reopenedStore = TranscriptHistoryStore(defaults: defaults)
    precondition(reopenedStore.load() == [measured])

    print("history record ok")
  }
}
