// Defines provider options, customization rules, and validated dictation settings.

import Foundation

enum STTProvider: String, CaseIterable, Codable, Identifiable, Sendable {
    case xai
    case elevenLabs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .xai:
            "xAI"
        case .elevenLabs:
            "ElevenLabs"
        }
    }
}

enum TranscriptionMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case upload
    case realtime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .upload:
            "Upload"
        case .realtime:
            "Realtime"
        }
    }
}

enum ElevenLabsCommitStrategy: String, CaseIterable, Codable, Identifiable, Sendable {
    case manual
    case vad

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual:
            "Manual"
        case .vad:
            "VAD"
        }
    }
}

struct DictationSettings: Codable, Equatable, Sendable {
    var provider: STTProvider
    var transcriptionMode: TranscriptionMode
    var elevenLabsCommitStrategy: ElevenLabsCommitStrategy
    var elevenLabsNoVerbatim: Bool
    var elevenLabsVADSilenceThreshold: Double
    var elevenLabsVADThreshold: Double
    var elevenLabsMinSpeechDuration: Int
    var elevenLabsMinSilenceDuration: Int
    var language: String
    var keyterms: String
    var replacementRules: String
    var includeFillerWords: Bool
    var xaiRealtimeEndpointing: Int
    var xaiSmartTurnEnabled: Bool
    var xaiSmartTurnThreshold: Double
    var xaiSmartTurnTimeout: Int
    var pasteAfterTranscription: Bool
    var adjustWithLLM: Bool
    var useLocalAdjustmentFallback: Bool
    var adjustmentBaseURL: String
    var adjustmentModel: String
    var adjustmentPrompt: String
    var includeScreenshot: Bool
    var hotkeyPreset: HotkeyPreset
    var customHotkey: CustomHotkey?
    var shortcutBehavior: ShortcutBehavior

    static let defaultAdjustmentPrompt = """
    Rewrite the transcript into polished text that is ready to insert into the active app. Fix obvious speech-to-text mistakes, punctuation, casing, and awkward phrasing while preserving intent. Use the screenshot only as context. Return only the final text.
    """

    static let defaults = DictationSettings(
        provider: .xai,
        transcriptionMode: .upload,
        elevenLabsCommitStrategy: .manual,
        elevenLabsNoVerbatim: false,
        elevenLabsVADSilenceThreshold: 1.5,
        elevenLabsVADThreshold: 0.4,
        elevenLabsMinSpeechDuration: 100,
        elevenLabsMinSilenceDuration: 100,
        language: "en",
        keyterms: "",
        replacementRules: "",
        includeFillerWords: false,
        xaiRealtimeEndpointing: 500,
        xaiSmartTurnEnabled: false,
        xaiSmartTurnThreshold: 0.5,
        xaiSmartTurnTimeout: 1500,
        pasteAfterTranscription: true,
        adjustWithLLM: true,
        useLocalAdjustmentFallback: true,
        adjustmentBaseURL: "https://ai-gateway.vercel.sh/v1",
        adjustmentModel: "xai/grok-4.3",
        adjustmentPrompt: defaultAdjustmentPrompt,
        includeScreenshot: false,
        hotkeyPreset: .controlOptionSpace,
        customHotkey: nil,
        shortcutBehavior: .toggle
    )

    var hotkeyDisplay: String {
        guard hotkeyPreset == .custom else {
            return hotkeyPreset.display
        }
        return customHotkey?.display ?? "Custom"
    }

    var keytermList: [String] {
        keyterms
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var replacements: [TextReplacement] {
        replacementRules
            .split(whereSeparator: \.isNewline)
            .compactMap { TextReplacement(rule: String($0)) }
    }

    var customizationSummary: String {
        let languageLabel = language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Auto language" : language
        let keytermLabel = keytermList.count == 1 ? "1 keyterm" : "\(keytermList.count) keyterms"
        let replacementLabel = replacements.count == 1 ? "1 replacement" : "\(replacements.count) replacements"
        let cleanupLabel = adjustWithLLM ? "LLM cleanup" : "Raw transcript"
        return "\(languageLabel) · \(keytermLabel) · \(replacementLabel) · \(cleanupLabel)"
    }

    /// Rejects persisted or imported values that cannot be produced by Vhrase's bounded controls.
    func validateLocalConfiguration() throws {
        guard (0...5_000).contains(xaiRealtimeEndpointing) else {
            throw ConfigurationValidationError("xAI endpointing must be between 0 and 5,000 ms.")
        }
        guard (0...1).contains(xaiSmartTurnThreshold) else {
            throw ConfigurationValidationError("xAI Smart Turn threshold must be between 0 and 1.")
        }
        guard (1...5_000).contains(xaiSmartTurnTimeout) else {
            throw ConfigurationValidationError("xAI Smart Turn timeout must be between 1 and 5,000 ms.")
        }
        guard (0.3...3).contains(elevenLabsVADSilenceThreshold) else {
            throw ConfigurationValidationError("ElevenLabs VAD silence must be between 0.3 and 3 seconds.")
        }
        guard (0.1...0.9).contains(elevenLabsVADThreshold) else {
            throw ConfigurationValidationError("ElevenLabs VAD threshold must be between 0.1 and 0.9.")
        }
        guard (50...2_000).contains(elevenLabsMinSpeechDuration) else {
            throw ConfigurationValidationError("ElevenLabs minimum speech must be between 50 and 2,000 ms.")
        }
        guard (50...2_000).contains(elevenLabsMinSilenceDuration) else {
            throw ConfigurationValidationError("ElevenLabs minimum silence must be between 50 and 2,000 ms.")
        }
        guard !adjustWithLLM || !adjustmentModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ConfigurationValidationError("Choose an LLM model before enabling transcript cleanup.")
        }
        guard hotkeyPreset != .custom || customHotkey != nil else {
            throw ConfigurationValidationError("Capture a custom shortcut before selecting Custom.")
        }
    }
}

struct CustomizationSnapshot: Codable, Equatable, Sendable {
    static let currentVersion = 2

    let version: Int
    let settings: DictationSettings

    init(version: Int = Self.currentVersion, settings: DictationSettings) {
        self.version = version
        self.settings = settings
    }
}

private struct ConfigurationValidationError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}

struct TextReplacement: Sendable {
    let source: String
    let target: String

    init?(rule: String) {
        let separators = ["=>", "->", "="]
        guard let separator = separators.first(where: { rule.contains($0) }) else {
            return nil
        }

        let parts = rule.components(separatedBy: separator)
        guard parts.count >= 2 else {
            return nil
        }

        let source = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let target = parts.dropFirst().joined(separator: separator).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty, !target.isEmpty else {
            return nil
        }

        self.source = source
        self.target = target
    }
}
