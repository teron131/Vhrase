// Calls an OpenAI-compatible language model through a validated endpoint with optional application context.

import Foundation

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
  ) async throws -> LLMRefinement {
    try validateConfiguration()

    let instruction = systemInstruction(for: settings)
    let userText = """
      \(appContextText(app))

      Transcript:
      \(transcript)
      """
    let response = try await adjustWithChatCompletions(
      systemInstruction: instruction,
      userText: userText,
      screenshotDataURL: screenshotDataURL,
      model: settings.adjustmentModel
    )

    return LLMRefinement(
      input: transcript,
      output: response.text.trimmingCharacters(in: .whitespacesAndNewlines),
      model: settings.adjustmentModel,
      systemInstruction: instruction,
      includedScreenshot: screenshotDataURL != nil,
      usage: response.usage
    )
  }

  func polish(
    text: String,
    screenshotDataURL: String?,
    settings: DictationSettings,
    app: FrontmostApp
  ) async throws -> (text: String, usage: LLMUsage?) {
    try validateConfiguration()

    let userText = """
      \(appContextText(app))

      Text:
      \(text)
      """

    return try await adjustWithChatCompletions(
      systemInstruction: systemInstruction(for: settings),
      userText: userText,
      screenshotDataURL: screenshotDataURL,
      model: settings.adjustmentModel
    )
  }

  /// Sends a minimal real completion, because a model listing cannot show whether this key may call this model.
  func checkModel(_ model: String) async throws {
    _ = try await Self.send(
      Self.modelCheckRequest(
        apiKey: apiKey,
        baseURL: baseURL,
        model: model
      ),
      errorDomain: "Vhrase.LLMModelsHTTP"
    )
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
    return try chatCompletionsRequest(
      apiKey: apiKey,
      baseURL: baseURL,
      timeout: 20,
      body: JSONEncoder().encode(payload)
    )
  }

  func listPrice(for model: String) async throws -> LLMPrice? {
    var request = URLRequest(url: try LLMEndpoint(baseURL: baseURL).appending("models"))
    request.timeoutInterval = 20
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    return try LLMPrice.listed(
      for: model.trimmingCharacters(in: .whitespacesAndNewlines),
      in: await Self.send(request, errorDomain: "Vhrase.LLMModelsHTTP"))
  }

  /// Call before capturing screen context, so nothing sensitive is gathered for a request that cannot be sent.
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
    systemInstruction: String,
    userText: String,
    screenshotDataURL: String?,
    model: String
  ) async throws -> (text: String, usage: LLMUsage?) {
    let request = try Self.chatCompletionsRequest(
      apiKey: apiKey,
      baseURL: baseURL,
      timeout: 60,
      body: Self.requestBody(
        systemInstruction: systemInstruction,
        userText: userText,
        screenshotDataURL: screenshotDataURL,
        model: model
      )
    )
    return try chatResponse(
      from: await Self.send(request, errorDomain: "Vhrase.AdjustmentChatHTTP"))
  }

  static func requestBody(
    systemInstruction: String,
    userText: String,
    screenshotDataURL: String?,
    model: String
  ) throws -> Data {
    var userContent: [LLMChatContent] = []
    if let screenshotDataURL {
      userContent.append(
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
    userContent.append(
      LLMChatContent(
        type: "text",
        text: userText,
        imageURL: nil
      )
    )

    let payload = LLMChatRequest(
      model: model,
      messages: [
        LLMChatMessage(
          role: "system",
          content: [
            LLMChatContent(
              type: "text",
              text: systemInstruction,
              imageURL: nil
            )
          ]
        ),
        LLMChatMessage(
          role: "user",
          content: userContent
        ),
      ],
      stream: false
    )
    return try JSONEncoder().encode(payload)
  }

  private static func chatCompletionsRequest(
    apiKey: String,
    baseURL: String,
    timeout: TimeInterval,
    body: Data
  ) throws -> URLRequest {
    var request = URLRequest(url: try LLMEndpoint(baseURL: baseURL).appending("chat/completions"))
    request.httpMethod = "POST"
    request.timeoutInterval = timeout
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = body
    return request
  }

  /// Throws the endpoint's own error text for a non-2xx status.
  private static func send(_ request: URLRequest, errorDomain: String) async throws -> Data {
    let (data, response) = try await URLSession.shared.data(for: request)
    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
      let message =
        String(data: data, encoding: .utf8)
        ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
      throw NSError(
        domain: errorDomain,
        code: http.statusCode,
        userInfo: [NSLocalizedDescriptionKey: message]
      )
    }
    return data
  }

  private func systemInstruction(for settings: DictationSettings) -> String {
    settings.polishPreferences.systemInstruction(
      preferredVocabulary: settings.keytermList,
      additionalInstructions: settings.adjustmentPrompt
    )
  }

  private func appContextText(_ app: FrontmostApp?) -> String {
    guard let app else {
      return "Frontmost app: Unknown"
    }

    let bundle = app.bundleIdentifier.isEmpty ? "unknown bundle id" : app.bundleIdentifier
    return "Frontmost app: \(app.name) (\(bundle))"
  }

  private func chatResponse(from data: Data) throws -> (text: String, usage: LLMUsage?) {
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
    guard !joined.isEmpty else {
      throw parseError()
    }
    guard let usage = dictionary["usage"] as? [String: Any],
      let input = usage["prompt_tokens"] as? Int,
      let output = usage["completion_tokens"] as? Int
    else {
      return (joined, nil)
    }
    return (joined, LLMUsage(inputTokens: input, outputTokens: output))
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
