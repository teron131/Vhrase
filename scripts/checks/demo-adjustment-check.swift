// Verifies the production local demo adjustment remains deterministic and provider-free.

@main
struct DemoAdjustmentCheck {
    static func main() {
        let input = "Please send this custom dictation demo to OpenAI and xAI using ElevenLabs."
        let output = DemoAdjustmentPreview().adjust(input)
        precondition(output.contains("OpenAI"))
        precondition(output == input)

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
        print("demo adjustment preview ok")
    }
}
