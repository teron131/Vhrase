// Verifies the deterministic local cleanup that runs when LLM polishing fails and in the Run demo dictation.

@main
struct LocalAdjustmentCheck {
  static func main() {
    let fallback = LocalAdjustmentFallback()
    precondition(
      fallback.adjust("  send this to open AI , x AI, and eleven labs  ")
        == "Send this to OpenAI, xAI, and ElevenLabs."
    )
    precondition(fallback.adjust("I like Swift") == "I like Swift.")
    precondition(fallback.adjust("It is basically correct") == "It is basically correct.")
    precondition(
      fallback.adjust("I think, you know, this is correct")
        == "I think, you know, this is correct."
    )
    precondition(
      fallback.adjust("use OPENAI, Open AI, XAI, x AI, ELEVENLABS and Eleven Labs!")
        == "Use OpenAI, OpenAI, xAI, xAI, ElevenLabs and ElevenLabs!"
    )
    precondition(
      fallback.adjust("keep reopenai, xair and elevenlabsx?")
        == "Keep reopenai, xair and elevenlabsx?"
    )
    precondition(fallback.adjust(" \t\n ").isEmpty)
    print("local adjustment ok")
  }
}
