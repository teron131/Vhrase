// Verifies user-facing transcript history metadata formatting.

import Foundation

@main
struct HistoryMetadataCheck {
  static func main() {
    let adjusted = TranscriptHistoryItem(
      id: UUID(),
      createdAt: Date(timeIntervalSince1970: 0),
      text: "Hello",
      provider: "xAI Realtime",
      transcriptionMode: "Realtime",
      cleanup: .llm,
      targetAppName: "Code",
      targetAppBundleIdentifier: "com.microsoft.VSCode"
    )
    precondition(
      DictationPresentation.historyMetadata(adjusted, relativeTo: nil)
        == "xAI Realtime · Realtime · LLM cleanup · → Code"
    )

    let fallback = TranscriptHistoryItem(
      id: UUID(),
      createdAt: Date(timeIntervalSince1970: 0),
      text: "Hello",
      provider: "ElevenLabs",
      transcriptionMode: "Upload",
      cleanup: .localFallback,
      targetAppName: nil,
      targetAppBundleIdentifier: nil
    )
    precondition(
      DictationPresentation.historyMetadata(fallback, relativeTo: nil)
        == "ElevenLabs · Upload · Local fallback"
    )

    print("history metadata ok")
  }
}
