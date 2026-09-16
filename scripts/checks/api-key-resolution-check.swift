// Verifies safe file-based credentials resolve without Keychain access while saved values retain precedence.

import Foundation

@main
struct APIKeyResolutionCheck {
  static func main() throws {
    precondition(SecretKey.llmAPIKey.rawValue == "LLM_API_KEY")

    let fixtureURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("vhrase-api-key-resolution-\(UUID().uuidString).env")
    defer {
      try? FileManager.default.removeItem(at: fixtureURL)
    }
    try """
    # File values fill missing launch values without executing shell syntax.
    XAI_API_KEY=file-xai
    ELEVENLABS_API_KEY="file-elevenlabs"
    GEMINI_API_KEY="file-gemini"
    LLM_API_KEY='file-llm'
    AI_GATEWAY_API_KEY=file-gateway
    LLM_BASE_URL=https://gateway.example/v1
    IGNORED_VALUE=ignored
    """.write(to: fixtureURL, atomically: true, encoding: .utf8)

    let environment = try APIKeyStore.developmentEnvironment(
      fileURL: fixtureURL,
      baseEnvironment: [SecretKey.xaiAPIKey.rawValue: "shell-xai"]
    )
    precondition(environment[SecretKey.xaiAPIKey.rawValue] == "shell-xai")
    precondition(environment[SecretKey.elevenLabsAPIKey.rawValue] == "file-elevenlabs")
    precondition(environment[SecretKey.geminiAPIKey.rawValue] == "file-gemini")
    precondition(environment[SecretKey.llmAPIKey.rawValue] == "file-llm")
    precondition(environment["AI_GATEWAY_API_KEY"] == "file-gateway")
    precondition(environment["LLM_BASE_URL"] == "https://gateway.example/v1")
    precondition(environment["IGNORED_VALUE"] == nil)

    let zshrcURL = fixtureURL.appendingPathExtension("zshrc")
    defer {
      try? FileManager.default.removeItem(at: zshrcURL)
    }
    try """
    export XAI_API_KEY="zshrc-xai"
    export ELEVENLABS_API_KEY=zshrc-elevenlabs
    export GEMINI_API_KEY=zshrc-gemini
    export AI_GATEWAY_API_KEY=zshrc-gateway
    export LLM_BASE_URL=https://zshrc-gateway.example/v1
    LLM_API_KEY=not-exported
    export LLM_API_KEY=$(ignored-command)
    export IGNORED_VALUE=ignored
    """.write(to: zshrcURL, atomically: true, encoding: .utf8)

    let zshrcEnvironment = try APIKeyStore.zshrcEnvironment(
      fileURL: zshrcURL,
      baseEnvironment: [SecretKey.xaiAPIKey.rawValue: "process-xai"]
    )
    precondition(zshrcEnvironment[SecretKey.xaiAPIKey.rawValue] == "process-xai")
    precondition(zshrcEnvironment[SecretKey.elevenLabsAPIKey.rawValue] == "zshrc-elevenlabs")
    precondition(zshrcEnvironment[SecretKey.geminiAPIKey.rawValue] == "zshrc-gemini")
    precondition(zshrcEnvironment["AI_GATEWAY_API_KEY"] == "zshrc-gateway")
    precondition(zshrcEnvironment["LLM_BASE_URL"] == "https://zshrc-gateway.example/v1")
    precondition(zshrcEnvironment[SecretKey.llmAPIKey.rawValue] == nil)
    precondition(zshrcEnvironment["IGNORED_VALUE"] == nil)

    let missingEnvironment = try APIKeyStore.developmentEnvironment(
      fileURL: fixtureURL.appendingPathExtension("missing"),
      baseEnvironment: [SecretKey.llmAPIKey.rawValue: "shell-llm"]
    )
    precondition(missingEnvironment == [SecretKey.llmAPIKey.rawValue: "shell-llm"])

    let store = APIKeyStore(environment: environment)
    precondition(
      store.effectiveValue(
        for: .llmAPIKey,
        savedValue: "saved-llm"
      ) == "saved-llm"
    )
    precondition(
      store.effectiveValue(
        for: .llmAPIKey,
        savedValue: "GEMINI_API_KEY"
      ) == "file-gemini"
    )
    precondition(
      store.effectiveValue(
        for: .llmAPIKey,
        savedValue: "AI_GATEWAY_API_KEY"
      ) == "file-gateway"
    )
    precondition(
      store.effectiveValue(
        for: .llmAPIKey,
        savedValue: "MISSING_API_KEY"
      ).isEmpty
    )
    precondition(
      store.effectiveValue(
        for: .geminiAPIKey,
        savedValue: "AI_GATEWAY_API_KEY"
      ) == "AI_GATEWAY_API_KEY"
    )
    precondition(
      store.effectiveValue(
        for: .llmAPIKey,
        savedValue: ""
      ) == "file-llm"
    )
    precondition(store.usesEnvironmentFallback(for: .llmAPIKey, savedValue: ""))
    precondition(store.usesEnvironmentFallback(for: .llmAPIKey, savedValue: "GEMINI_API_KEY"))
    precondition(
      store.usesEnvironmentFallback(for: .llmAPIKey, savedValue: "AI_GATEWAY_API_KEY"))
    precondition(!store.usesEnvironmentFallback(for: .llmAPIKey, savedValue: "MISSING_API_KEY"))
    precondition(!store.usesEnvironmentFallback(for: .llmAPIKey, savedValue: "saved-llm"))
    precondition(
      store.effectiveLLMBaseURL(savedValue: "http://localhost:8317/v1")
        == "https://gateway.example/v1"
    )
    precondition(store.usesEnvironmentLLMBaseURL)

    let referenceSuite = "Vhrase.APIKeyResolutionCheck.\(UUID().uuidString)"
    guard let referenceDefaults = UserDefaults(suiteName: referenceSuite) else {
      preconditionFailure("Could not create credential-reference defaults")
    }
    defer {
      referenceDefaults.removePersistentDomain(forName: referenceSuite)
    }
    let referenceStore = APIKeyStore(
      environment: environment,
      defaultsSuiteName: referenceSuite
    )
    precondition(referenceStore.savedLLMCredentialReference().isEmpty)
    referenceStore.saveLLMCredentialReference("AI_GATEWAY_API_KEY")
    precondition(referenceStore.savedLLMCredentialReference() == "AI_GATEWAY_API_KEY")
    referenceStore.saveLLMCredentialReference("not-a-reference")
    precondition(referenceStore.savedLLMCredentialReference().isEmpty)

    let savedConfigurationStore = APIKeyStore(environment: [:])
    precondition(
      savedConfigurationStore.effectiveLLMBaseURL(savedValue: "http://localhost:8317/v1")
        == "http://localhost:8317/v1"
    )
    precondition(!savedConfigurationStore.usesEnvironmentLLMBaseURL)

    print("API key development resolution ok")
  }
}
