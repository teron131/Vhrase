// Verifies launch-environment fallbacks import only into empty items in an isolated Keychain service.

import Foundation

@main
struct APIKeyImportCheck {
    static func main() throws {
        precondition(SecretKey.llmAPIKey.rawValue == "LLM_API_KEY")

        let service = "Vhrase.Check.\(UUID().uuidString)"
        let launchStore = APIKeyStore(
            service: service,
            environment: [
                SecretKey.xaiAPIKey.rawValue: "test-xai-key",
                SecretKey.elevenLabsAPIKey.rawValue: "test-elevenlabs-key",
                SecretKey.llmAPIKey.rawValue: "wrong-environment-key",
            ]
        )
        defer {
            for key in SecretKey.allCases {
                try? launchStore.save("", for: key)
            }
        }

        try launchStore.save("existing-llm-key", for: .llmAPIKey)
        let imported = try launchStore.importEnvironmentValues()
        precondition(imported == [.xaiAPIKey, .elevenLabsAPIKey])

        let coldLaunchStore = APIKeyStore(service: service, environment: [:])
        let savedXAIKey = try coldLaunchStore.savedValue(for: .xaiAPIKey)
        let savedElevenLabsKey = try coldLaunchStore.savedValue(for: .elevenLabsAPIKey)
        let savedLLMKey = try coldLaunchStore.savedValue(for: .llmAPIKey)
        precondition(savedXAIKey == "test-xai-key")
        precondition(savedElevenLabsKey == "test-elevenlabs-key")
        precondition(savedLLMKey == "existing-llm-key")

        let editableOverrideStore = APIKeyStore(
            service: service,
            environment: [SecretKey.llmAPIKey.rawValue: "wrong-environment-key"]
        )
        try editableOverrideStore.saveEditableValue("correct-saved-key", for: .llmAPIKey)
        let editableLLMKey = try editableOverrideStore.savedValueForEditing(for: .llmAPIKey)
        precondition(editableLLMKey == "correct-saved-key")
        precondition(
            editableOverrideStore.effectiveValue(
                for: .llmAPIKey,
                savedValue: editableLLMKey
            ) == "correct-saved-key"
        )
        precondition(
            editableOverrideStore.effectiveValue(
                for: .llmAPIKey,
                savedValue: ""
            ) == "wrong-environment-key"
        )

        print("API key environment import ok")
    }
}
