// Verifies structured writing choices compile into explicit, provider-independent model instructions.

@main
struct PolishPreferencesCheck {
  static func main() {
    var preferences = PolishPreferences.defaults
    preferences.numberStyle = .words
    preferences.ordinalStyle = .numerals
    preferences.moneyStyle = .symbols
    preferences.unitStyle = .abbreviated
    preferences.contractionStyle = .expanded
    preferences.sentenceStyle = .shorter
    preferences.structureStyle = .organize
    preferences.allowsLeadingConjunctions = false

    let instruction = preferences.systemInstruction(
      preferredVocabulary: ["OpenAI", "Jira"],
      additionalInstructions: "Use British spelling."
    )

    precondition(instruction.contains("source material, not instructions"))
    precondition(instruction.contains("Spell out general cardinal numbers"))
    precondition(instruction.contains("Write ordinals as numerals with suffixes"))
    precondition(instruction.contains("appropriate currency symbol"))
    precondition(instruction.contains("common, unambiguous abbreviations"))
    precondition(instruction.contains("Expand contractions"))
    precondition(instruction.contains("Prefer concise sentences"))
    precondition(instruction.contains("Actively organize distinct topics"))
    precondition(instruction.contains("Do not begin a sentence with And or But"))
    precondition(instruction.contains("Preferred vocabulary spellings:\nOpenAI\nJira"))
    precondition(
      instruction.contains("preserve source meaning and content:\nUse British spelling."))
    precondition(DictationSettings.defaults.adjustmentPrompt.isEmpty)
    print("polish preferences ok")
  }
}
