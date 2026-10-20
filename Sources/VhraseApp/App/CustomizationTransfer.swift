// Owns bounded customization document export, validation, and sensitive-change review.

import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
struct CustomizationTransfer {
  private static let maximumBytes = 1_048_576

  enum ImportOutcome {
    case dismissed
    case reviewCancelled
    case imported(DictationSettings)
  }

  /// Returns `false` when the user cancels the save panel.
  func export(_ settings: DictationSettings) throws -> Bool {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.json]
    panel.canCreateDirectories = true
    panel.nameFieldStringValue = "VhraseCustomization.json"

    guard panel.runModal() == .OK, let url = panel.url else {
      return false
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let snapshot = CustomizationSnapshot(settings: settings)
    try encoder.encode(snapshot).write(to: url, options: .atomic)
    return true
  }

  func importSettings(replacing current: DictationSettings) throws -> ImportOutcome {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false

    guard panel.runModal() == .OK, let url = panel.url else {
      return .dismissed
    }

    let snapshot = try JSONDecoder().decode(
      CustomizationSnapshot.self,
      from: try customizationData(from: url)
    )
    try validate(snapshot)
    guard confirmSensitiveChanges(from: current, to: snapshot.settings) else {
      return .reviewCancelled
    }
    return .imported(snapshot.settings)
  }

  /// Reads only a bounded regular JSON file so import cannot allocate an attacker-controlled payload.
  private func customizationData(from url: URL) throws -> Data {
    let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
    guard values.isRegularFile == true else {
      throw CustomizationImportError.notRegularFile
    }
    if let fileSize = values.fileSize, fileSize > Self.maximumBytes {
      throw CustomizationImportError.fileTooLarge(maximumBytes: Self.maximumBytes)
    }

    let data = try Data(contentsOf: url, options: .mappedIfSafe)
    guard data.count <= Self.maximumBytes else {
      throw CustomizationImportError.fileTooLarge(maximumBytes: Self.maximumBytes)
    }
    return data
  }

  private func validate(_ snapshot: CustomizationSnapshot) throws {
    try TranscriptionContract.validate(settings: snapshot.settings)
    _ = try LLMEndpoint.validatedBaseURL(snapshot.settings.adjustmentBaseURL)
  }

  private func confirmSensitiveChanges(
    from current: DictationSettings,
    to imported: DictationSettings
  ) -> Bool {
    let changes = sensitiveChanges(from: current, to: imported)
    guard !changes.isEmpty else {
      return true
    }

    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Review sensitive customization changes"
    alert.informativeText =
      "This file will:\n\n\(changes.map { "• \($0)" }.joined(separator: "\n"))\n\nImport only files you trust. API keys are not included in customization files."
    alert.addButton(withTitle: "Import")
    alert.addButton(withTitle: "Cancel")
    return alert.runModal() == .alertFirstButtonReturn
  }

  /// Describes imported changes that expand remote sharing, clipboard retention, or system control.
  private func sensitiveChanges(
    from current: DictationSettings,
    to imported: DictationSettings
  ) -> [String] {
    var changes: [String] = []
    let currentEndpoint = current.adjustmentBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    let importedEndpoint = imported.adjustmentBaseURL.trimmingCharacters(
      in: .whitespacesAndNewlines)

    if currentEndpoint != importedEndpoint,
      let endpoint = try? LLMEndpoint.validatedBaseURL(importedEndpoint),
      let host = endpoint.host
    {
      changes.append("Change the LLM endpoint to \(host).")
    }
    if !current.adjustWithLLM, imported.adjustWithLLM {
      changes.append("Send transcripts to the configured LLM for cleanup.")
    }
    if !current.includeScreenshot, imported.includeScreenshot {
      changes.append("Include a screenshot of the target app's display in LLM cleanup requests.")
    }
    if !current.keepTranscriptOnClipboard, imported.keepTranscriptOnClipboard {
      changes.append("Keep finalized text on the clipboard after insertion.")
    }
    if current.hotkeyPreset != imported.hotkeyPreset
      || current.customHotkey != imported.customHotkey
    {
      changes.append("Change the global shortcut to \(imported.hotkeyDisplay).")
    }
    return changes
  }
}

private enum CustomizationImportError: LocalizedError {
  case notRegularFile
  case fileTooLarge(maximumBytes: Int)

  var errorDescription: String? {
    switch self {
    case .notRegularFile:
      "Customization import requires a regular JSON file."
    case .fileTooLarge(let maximumBytes):
      "Customization file exceeds the \(maximumBytes / 1_048_576) MiB limit."
    }
  }
}
