// Verifies production parsing and case-insensitive application of transcript replacement rules.

@main
struct ReplacementRulesCheck {
  static func main() {
    let rules = [
      "open AI => OpenAI",
      "x AI -> xAI",
      "eleven labs = ElevenLabs",
    ].compactMap(TextReplacement.init(rule:))

    let output = TextReplacementProcessor().apply(
      rules,
      to: "please send this to open ai and x ai with eleven labs"
    )

    precondition(output == "please send this to OpenAI and xAI with ElevenLabs")
    print("replacement rules ok")
  }
}
