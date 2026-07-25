// Applies user-defined literal replacement rules to transcript text.

import Foundation

struct TextReplacementProcessor {
  func apply(_ replacements: [TextReplacement], to text: String) -> String {
    replacements.reduce(text) { current, replacement in
      current.replacingOccurrences(
        of: replacement.source,
        with: replacement.target,
        options: [.caseInsensitive, .diacriticInsensitive]
      )
    }
  }
}
