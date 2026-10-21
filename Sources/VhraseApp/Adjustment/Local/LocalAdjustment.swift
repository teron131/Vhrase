// Provides deterministic local transcript cleanup for fallback and demo workflows.

import Foundation

struct LocalAdjustmentFallback {
  /// `send  it to open ai , then x ai` → `Send it to OpenAI, then xAI.`
  func adjust(_ text: String) -> String {
    let normalized = normalizeProductNames(cleanWhitespace(text))
    return ensureTrailingPunctuation(sentenceCased(normalizePunctuationSpacing(normalized)))
  }

  private func cleanWhitespace(_ text: String) -> String {
    text
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func normalizeProductNames(_ text: String) -> String {
    var result = text
    let replacements = [
      "\\bopen\\s*AI\\b": "OpenAI",
      "\\bx\\s*AI\\b": "xAI",
      "\\beleven\\s*labs\\b": "ElevenLabs",
    ]

    for (pattern, replacement) in replacements {
      result = result.replacingOccurrences(
        of: pattern,
        with: replacement,
        options: [.regularExpression, .caseInsensitive]
      )
    }
    return result
  }

  private func normalizePunctuationSpacing(_ text: String) -> String {
    text.replacingOccurrences(
      of: "\\s+,",
      with: ",",
      options: .regularExpression
    )
  }

  private func sentenceCased(_ text: String) -> String {
    guard let first = text.first else {
      return text
    }
    return first.uppercased() + text.dropFirst()
  }

  private func ensureTrailingPunctuation(_ text: String) -> String {
    guard let last = text.last, !".!?".contains(last) else {
      return text
    }
    return "\(text)."
  }

}
