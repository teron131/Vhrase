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

        print("history record ok")
    }
}
