// Verifies production customization export round trips while excluding API credentials.

import Foundation

@main
struct CustomizationSnapshotCheck {
    static func main() throws {
        var settings = DictationSettings.defaults
        settings.provider = .elevenLabs
        settings.transcriptionMode = .realtime
        settings.language = ""
        settings.keyterms = "OpenAI\nxAI"
        settings.replacementRules = "open AI => OpenAI"
        settings.adjustmentPrompt = "Keep identifiers intact."
        settings.keepTranscriptOnClipboard = true

        let snapshot = CustomizationSnapshot(settings: settings)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        let json = String(decoding: data, as: UTF8.self)
        precondition(!json.contains("\"version\""))
        precondition(!json.localizedCaseInsensitiveContains("apiKey"))
        precondition(!json.localizedCaseInsensitiveContains("XAI_API_KEY"))
        precondition(!json.localizedCaseInsensitiveContains("ELEVENLABS_API_KEY"))
        precondition(!json.localizedCaseInsensitiveContains("LLM_API_KEY"))
        precondition(json.contains("\"keepTranscriptOnClipboard\" : true"))
        precondition(!json.contains("pasteAfterTranscription"))

        let decoded = try JSONDecoder().decode(CustomizationSnapshot.self, from: data)
        precondition(decoded == snapshot)
        try decoded.settings.validateLocalConfiguration()

        var invalidSettings = decoded.settings
        invalidSettings.elevenLabsVADThreshold = 1.1
        precondition(rejectsLocalConfiguration(invalidSettings))

        let suiteName = "Vhrase.SettingsStoreCheck"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Could not create isolated settings defaults.")
        }
        defaults.removePersistentDomain(forName: suiteName)
        let store = SettingsStore(defaults: defaults)
        store.save(settings)
        precondition(store.load().language.isEmpty)
        precondition(store.load().keepTranscriptOnClipboard)
        defaults.removePersistentDomain(forName: suiteName)
        print("customization snapshot ok")
    }

    private static func rejectsLocalConfiguration(_ settings: DictationSettings) -> Bool {
        do {
            try settings.validateLocalConfiguration()
            return false
        } catch {
            return true
        }
    }
}
