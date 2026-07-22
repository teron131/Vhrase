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

    /// Presents a destination picker and atomically writes a versioned customization snapshot.
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

    /// Reads and validates a bounded snapshot before requiring review of expanded remote or system behavior.
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

    /// Rejects stale or unsafe customization contracts before they can change persisted app behavior.
    private func validate(_ snapshot: CustomizationSnapshot) throws {
        guard snapshot.version == CustomizationSnapshot.currentVersion else {
            throw CustomizationImportError.unsupportedVersion(
                found: snapshot.version,
                expected: CustomizationSnapshot.currentVersion
            )
        }
        try TranscriptionContract.validate(settings: snapshot.settings)
        _ = try LLMEndpoint.validatedBaseURL(snapshot.settings.adjustmentBaseURL)
    }

    /// Requires an explicit review when imported settings expand remote-data or system-control behavior.
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
        alert.informativeText = "This file will:\n\n\(changes.map { "• \($0)" }.joined(separator: "\n"))\n\nImport only files you trust. API keys are not included in customization files."
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Describes only imported changes that can send more data or control another application.
    private func sensitiveChanges(
        from current: DictationSettings,
        to imported: DictationSettings
    ) -> [String] {
        var changes: [String] = []
        let currentEndpoint = current.adjustmentBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let importedEndpoint = imported.adjustmentBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)

        if currentEndpoint != importedEndpoint,
           let endpoint = try? LLMEndpoint.validatedBaseURL(importedEndpoint),
           let host = endpoint.host {
            changes.append("Change the LLM endpoint to \(host).")
        }
        if !current.adjustWithLLM, imported.adjustWithLLM {
            changes.append("Send transcripts to the configured LLM for cleanup.")
        }
        if !current.includeScreenshot, imported.includeScreenshot {
            changes.append("Include a main-display screenshot in LLM cleanup requests.")
        }
        if !current.pasteAfterTranscription, imported.pasteAfterTranscription {
            changes.append("Paste finalized text into the recorded target application.")
        }
        if current.hotkeyPreset != imported.hotkeyPreset || current.customHotkey != imported.customHotkey {
            changes.append("Change the global shortcut to \(imported.hotkeyDisplay).")
        }
        return changes
    }
}

private enum CustomizationImportError: LocalizedError {
    case notRegularFile
    case fileTooLarge(maximumBytes: Int)
    case unsupportedVersion(found: Int, expected: Int)

    var errorDescription: String? {
        switch self {
        case .notRegularFile:
            "Customization import requires a regular JSON file."
        case .fileTooLarge(let maximumBytes):
            "Customization file exceeds the \(maximumBytes / 1_048_576) MiB limit."
        case .unsupportedVersion(let found, let expected):
            "Customization version \(found) is unsupported. Export a version \(expected) file from this Vhrase release."
        }
    }
}
