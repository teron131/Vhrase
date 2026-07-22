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
        print("history record ok")
    }
}
