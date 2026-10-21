// Names the Hugging Face models Vhrase can run on this Mac and validates a typed model ID before it reaches a download or a file path.

import Foundation

/// A model on the Hugging Face Hub, named the way the transformers pipeline takes it: `owner/name`.
struct HuggingFaceModelReference: Equatable, Sendable {
  let id: String

  /// Accepts `owner/name`, or a bare `name` for the few models without an owner. Parts follow the Hub's own character rules, so an ID can neither leave the Models folder nor collide with the cache's `--` separator.
  init(_ id: String) throws {
    let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
    let parts = trimmed.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    guard (1...2).contains(parts.count), trimmed.count <= 96, parts.allSatisfy(Self.isValidPart)
    else {
      throw ConfigurationValidationError(
        "Enter a Hugging Face model ID such as \(DictationSettings.defaultHuggingFaceModel).")
    }
    self.id = trimmed
  }

  /// The Hub cache's folder for the model: `openai/whisper-large-v3-turbo` → `models--openai--whisper-large-v3-turbo`.
  var cacheFolderName: String {
    "models--" + id.replacingOccurrences(of: "/", with: "--")
  }

  private static func isValidPart(_ part: String) -> Bool {
    let allowed = CharacterSet(
      charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
    guard let first = part.first, let last = part.last else { return false }
    return !".-".contains(first) && !".-".contains(last)
      && !part.contains("..") && !part.contains("--")
      && part.unicodeScalars.allSatisfy(allowed.contains)
  }
}
