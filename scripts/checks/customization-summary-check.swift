// Verifies the production customization summary for populated and automatic-language settings.

@main
struct CustomizationSummaryCheck {
  static func main() {
    var populated = DictationSettings.defaults
    populated.language = "en"
    populated.keyterms = "OpenAI\nxAI\nElevenLabs"
    populated.replacementRules = "open AI => OpenAI\nx AI => xAI"
    populated.adjustWithLLM = true
    precondition(populated.customizationSummary == "en · 3 keyterms · 2 replacements · LLM cleanup")

    var automatic = DictationSettings.defaults
    automatic.language = ""
    automatic.keyterms = "VoiceInk"
    automatic.replacementRules = ""
    automatic.adjustWithLLM = false
    precondition(
      automatic.customizationSummary
        == "Auto language · 1 keyterm · 0 replacements · Raw transcript")
    print("customization summary ok")
  }
}
