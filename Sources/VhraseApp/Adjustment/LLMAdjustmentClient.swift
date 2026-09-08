// Calls an OpenAI-compatible language model through a validated endpoint with optional application context.

import Foundation

final class LLMModelAccessClient: Sendable {
  private let apiKey: String
  private let baseURL: String

  init(
    apiKey: String,
    baseURL: String
  ) {
    self.apiKey = apiKey
    self.baseURL = baseURL
  }

  /// Sends a minimal completion probe through the configured model and the same route used by cleanup.
  func checkModel(_ model: String) async throws {
    let request = try Self.modelCheckRequest(
      apiKey: apiKey,
      baseURL: baseURL,
      model: model
    )
    let (data, response) = try await URLSession.shared.data(for: request)
    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
      let message =
        String(data: data, encoding: .utf8)
        ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
      throw NSError(
        domain: "Vhrase.LLMModelsHTTP",
        code: http.statusCode,
        userInfo: [NSLocalizedDescriptionKey: message]
      )
    }
  }

  static func modelCheckRequest(
    apiKey: String,
    baseURL: String,
    model: String
  ) throws -> URLRequest {
    guard !apiKey.isEmpty else {
      throw NSError(
        domain: "Vhrase.LLMModels",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "LLM API key is required to check model access."]
      )
    }
    let configuredModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !configuredModel.isEmpty else {
      throw NSError(
        domain: "Vhrase.LLMModels",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Choose an LLM model before checking access."]
      )
    }

    let payload = LLMChatRequest(
      model: configuredModel,
      messages: [
        LLMChatMessage(
          role: "user",
          content: [
            LLMChatContent(
              type: "text",
              text: "Reply with OK.",
              imageURL: nil
            )
          ]
        )
      ],
      stream: false
    )

    var request = URLRequest(
      url: try LLMEndpoint(baseURL: baseURL).appending("chat/completions")
    )
    request.httpMethod = "POST"
    request.timeoutInterval = 20
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(payload)
    return request
  }
}

final class LLMAdjustmentClient: Sendable {
  private let apiKey: String
  private let baseURL: String

  init(
    apiKey: String,
    baseURL: String
  ) {
    self.apiKey = apiKey
    self.baseURL = baseURL
  }

  func adjust(
    transcript: String,
    screenshotDataURL: String?,
    settings: DictationSettings,
    app: FrontmostApp?
  ) async throws -> String {
    try validateConfiguration()

    let promptText = """
      \(prompt(for: settings))

      \(appContextText(app))

      Transcript:
      \(transcript)
      """

    return try await adjustWithChatCompletions(
      promptText: promptText,
      screenshotDataURL: screenshotDataURL,
      model: settings.adjustmentModel
    )
  }

  /// Validates credentials and destination before callers capture or attach sensitive context.
  func validateConfiguration() throws {
    guard !apiKey.isEmpty else {
      throw NSError(
        domain: "Vhrase.Adjustment",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "LLM API key is required for LLM adjustments."]
      )
    }
    _ = try LLMEndpoint(baseURL: baseURL)
  }

  private func adjustWithChatCompletions(
    promptText: String,
    screenshotDataURL: String?,
    model: String
  ) async throws -> String {
    var content: [LLMChatContent] = []
    if let screenshotDataURL {
      content.append(
        LLMChatContent(
          type: "image_url",
          text: nil,
          imageURL: LLMChatImageURL(
            url: screenshotDataURL,
            detail: "high"
          )
        )
      )
    }
    content.append(
      LLMChatContent(
        type: "text",
        text: promptText,
        imageURL: nil
      )
    )

    let payload = LLMChatRequest(
      model: model,
      messages: [
        LLMChatMessage(
          role: "user",
          content: content
        )
      ],
      stream: false
    )

    var request = URLRequest(url: try LLMEndpoint(baseURL: baseURL).appending("chat/completions"))
    request.httpMethod = "POST"
    request.timeoutInterval = 60
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(payload)

    let (data, response) = try await URLSession.shared.data(for: request)
    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
      let message =
        String(data: data, encoding: .utf8)
        ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
      throw NSError(
        domain: "Vhrase.AdjustmentChatHTTP",
        code: http.statusCode,
        userInfo: [NSLocalizedDescriptionKey: message]
      )
    }

    return try extractChatText(from: data)
  }

  private func prompt(for settings: DictationSettings) -> String {
    var sections = [DictationSettings.defaultAdjustmentPrompt]
    let keyterms = settings.keytermList
    if !keyterms.isEmpty {
      sections.append(
        "Preferred vocabulary spellings:\n\(keyterms.joined(separator: "\n"))"
      )
    }

    let extraInstructions = settings.adjustmentPrompt
      .trimmingCharacters(in: .whitespacesAndNewlines)

    if !extraInstructions.isEmpty,
      extraInstructions != DictationSettings.defaultAdjustmentPrompt
    {
      sections.append("Additional user instructions:\n\(extraInstructions)")
    }

    return sections.joined(separator: "\n\n")
  }

  private func appContextText(_ app: FrontmostApp?) -> String {
    guard let app else {
      return "Frontmost app: Unknown"
    }

    let bundle = app.bundleIdentifier.isEmpty ? "unknown bundle id" : app.bundleIdentifier
    return "Frontmost app: \(app.name) (\(bundle))"
  }

  private func extractChatText(from data: Data) throws -> String {
    let object = try JSONSerialization.jsonObject(with: data)
    guard let dictionary = object as? [String: Any],
      let choices = dictionary["choices"] as? [[String: Any]]
    else {
      throw parseError()
    }

    let texts = choices.compactMap { choice -> String? in
      guard let message = choice["message"] as? [String: Any] else {
        return nil
      }
      return message["content"] as? String
    }

    let joined = texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    if !joined.isEmpty {
      return joined
    }

    throw parseError()
  }

  private func parseError() -> NSError {
    NSError(
      domain: "Vhrase.Adjustment",
      code: 2,
      userInfo: [NSLocalizedDescriptionKey: "Could not read adjusted text from the LLM response."]
    )
  }
}

private struct LLMChatRequest: Encodable {
  let model: String
  let messages: [LLMChatMessage]
  let stream: Bool
  let reasoningEffort = "low"

  private enum CodingKeys: String, CodingKey {
    case model
    case messages
    case stream
    case reasoningEffort = "reasoning_effort"
  }
}

private struct LLMChatMessage: Encodable {
  let role: String
  let content: [LLMChatContent]
}

private struct LLMChatContent: Encodable {
  let type: String
  let text: String?
  let imageURL: LLMChatImageURL?

  enum CodingKeys: String, CodingKey {
    case type
    case text
    case imageURL = "image_url"
  }
}

private struct LLMChatImageURL: Encodable {
  let url: String
  let detail: String
}
