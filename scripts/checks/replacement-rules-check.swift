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

    // Delimiter priority is independent of position, and only its first occurrence separates the rule.
    let examples = [
      (" name => value => suffix ", "name", "value => suffix"),
      ("name -> value -> suffix", "name", "value -> suffix"),
      ("name = value = suffix", "name", "value = suffix"),
      ("name = alias -> preferred => final", "name = alias -> preferred", "final"),
      ("name = alias -> final", "name = alias", "final"),
      (" 發音 😀 => 正字 👩🏽‍💻 = 保留 ", "發音 😀", "正字 👩🏽‍💻 = 保留"),
    ]
    for (rule, source, target) in examples {
      let replacement = TextReplacement(rule: rule)
      precondition(replacement?.source == source)
      precondition(replacement?.target == target)
    }
    for rule in ["", "no delimiter", " => target", "source -> ", " = "] {
      precondition(TextReplacement(rule: rule) == nil)
    }
    print("replacement rules ok")
  }
}
