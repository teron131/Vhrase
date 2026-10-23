// Verifies the current transcript-history record round trips through its persisted JSON shape.

import Foundation

@main
struct HistoryCheck {
  static func main() throws {
    var item = TranscriptHistoryItem(
      id: UUID(),
      createdAt: Date(timeIntervalSince1970: 1_800_000_000),
      text: "Hello from dictation.",
      provider: "xAI Realtime",
      transcriptionMode: "Realtime",
      cleanup: .llm,
      targetAppName: "Code",
      targetAppBundleIdentifier: "com.microsoft.VSCode"
    )
    let historicalStyle = PolishStyle(
      title: "Rephrase", instruction: "The instruction that actually ran.")
    item.refinement = LLMRefinement(
      input: "hello from dictation",
      output: "Hello from dictation.",
      model: "test/model",
      systemInstruction: "Polish the transcript.",
      includedScreenshot: false,
      usage: LLMUsage(inputTokens: 2_480, outputTokens: 120),
      style: historicalStyle
    )

    let data = try JSONEncoder().encode([item])
    let decoded = try JSONDecoder().decode([TranscriptHistoryItem].self, from: data)
    precondition(decoded == [item])
    precondition(decoded[0].refinement?.style == historicalStyle)
    precondition(decoded[0].refinement?.style != PolishStyle.rephrase)
    let records = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
    let savedResult = records[0]["refinement"] as! [String: Any]
    let savedStyle = savedResult["style"] as! [String: Any]
    precondition(Set(savedStyle.keys) == ["title", "instruction"])
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
    oldShape.removeValue(forKey: "refinement")
    oldShape.removeValue(forKey: "recordingSeconds")
    oldShape.removeValue(forKey: "transcriptionSeconds")
    oldShape.removeValue(forKey: "processingSeconds")
    let oldData = try JSONSerialization.data(withJSONObject: oldShape)
    let oldItem = try JSONDecoder().decode(TranscriptHistoryItem.self, from: oldData)
    var itemWithoutNewFields = item
    itemWithoutNewFields.refinement = nil
    precondition(oldItem == itemWithoutNewFields)
    var withoutUsage = try JSONSerialization.jsonObject(with: measuredData) as! [String: Any]
    var savedRefinement = withoutUsage["refinement"] as! [String: Any]
    savedRefinement.removeValue(forKey: "usage")
    savedRefinement.removeValue(forKey: "style")
    withoutUsage["refinement"] = savedRefinement
    let unmeasured = try JSONDecoder().decode(
      TranscriptHistoryItem.self, from: JSONSerialization.data(withJSONObject: withoutUsage))
    precondition(unmeasured.refinement?.output == "Hello from dictation.")
    precondition(unmeasured.refinement?.usage == nil)
    precondition(unmeasured.refinement?.style == nil)
    precondition(unmeasured.cleanupTitle == "Refine")

    // A fixed suite keeps repeated runs from leaving one preferences file each in ~/Library/Preferences.
    let suiteName = "Vhrase.HistoryCheck"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      preconditionFailure("Could not create isolated history defaults")
    }
    defaults.removePersistentDomain(forName: suiteName)
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
    let existingHistory = (0..<39).map { index in
      TranscriptHistoryItem(
        id: UUID(),
        createdAt: Date(timeIntervalSince1970: Double(index)),
        text: "Saved transcript \(index)",
        provider: "Test",
        transcriptionMode: "Upload",
        cleanup: .raw,
        targetAppName: nil,
        targetAppBundleIdentifier: nil
      )
    }
    let completeHistory = store.prepend(measured, to: existingHistory)
    precondition(completeHistory.count == 40)
    let reopenedStore = TranscriptHistoryStore(defaults: defaults)
    precondition(reopenedStore.load() == completeHistory)

    print("history record ok")
  }
}
