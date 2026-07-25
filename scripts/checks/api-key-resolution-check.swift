// Verifies development credentials resolve without Keychain access while saved values retain precedence.

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
    LLM_API_KEY='file-llm'
    IGNORED_KEY=ignored
    """.write(to: fixtureURL, atomically: true, encoding: .utf8)

    let environment = try APIKeyStore.developmentEnvironment(
      fileURL: fixtureURL,
      baseEnvironment: [SecretKey.xaiAPIKey.rawValue: "shell-xai"]
    )
    precondition(environment[SecretKey.xaiAPIKey.rawValue] == "shell-xai")
    precondition(environment[SecretKey.elevenLabsAPIKey.rawValue] == "file-elevenlabs")
    precondition(environment[SecretKey.llmAPIKey.rawValue] == "file-llm")
    precondition(environment["IGNORED_KEY"] == nil)

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
        savedValue: ""
      ) == "file-llm"
    )
    precondition(store.usesEnvironmentFallback(for: .llmAPIKey, savedValue: ""))
    precondition(!store.usesEnvironmentFallback(for: .llmAPIKey, savedValue: "saved-llm"))

    print("API key development resolution ok")
  }
}
