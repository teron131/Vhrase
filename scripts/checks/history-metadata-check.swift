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
        == "xAI Realtime · Realtime · Refine · → Code"
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

    let customStyle = PolishStyle(
      title: "Unlisted style", instruction: "Group related ideas.")
    for style in [PolishStyle.rephrase, .genZ, customStyle] {
      var rewritten = adjusted
      rewritten.refinement = LLMRefinement(
        input: "hello", output: "Hello", model: "model", systemInstruction: "instruction",
        includedScreenshot: false, usage: nil, style: style)
      let label = "Restyle: \(style.title)"
      precondition(
        DictationPresentation.historyMetadata(rewritten, relativeTo: nil)
          == "xAI Realtime · Realtime · \(label) · → Code")
      let completion = WorkflowCompletion.textRestyled(style: style)
      precondition(completion.completionDetail.contains("Command-Z in the target app to undo"))
      precondition(completion.completionDetail.hasPrefix("Restyled with \(style.title)."))
    }
    print("history metadata ok")
  }
}
