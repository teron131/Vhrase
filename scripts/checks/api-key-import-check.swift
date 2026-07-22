// Verifies launch-environment credentials can be securely synchronized into an isolated Keychain service.

import Foundation

@main
struct APIKeyImportCheck {
    static func main() throws {
        let service = "Vhrase.Check.\(UUID().uuidString)"
        let launchStore = APIKeyStore(
            service: service,
            environment: [
                SecretKey.xaiAPIKey.rawValue: "test-xai-key",
                SecretKey.elevenLabsAPIKey.rawValue: "test-elevenlabs-key",
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
        try launchStore.saveEditableValue("", for: .xaiAPIKey)

        let coldLaunchStore = APIKeyStore(service: service, environment: [:])
        let savedXAIKey = try coldLaunchStore.savedValue(for: .xaiAPIKey)
        let savedElevenLabsKey = try coldLaunchStore.savedValue(for: .elevenLabsAPIKey)
        let savedLLMKey = try coldLaunchStore.savedValue(for: .llmAPIKey)
        precondition(savedXAIKey == "test-xai-key")
        precondition(savedElevenLabsKey == "test-elevenlabs-key")
        precondition(savedLLMKey == "existing-llm-key")

        print("API key environment import ok")
    }
}
