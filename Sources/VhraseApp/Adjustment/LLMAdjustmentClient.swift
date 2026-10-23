// Shares validated OpenAI-compatible transport across dictation polishing, double-tap Restyle, and History tests, alongside model-access and pricing probes.

import Foundation

/// What a polish request rewrites, named for the model in the request's user message.
enum PolishSource {
  case transcript
  case focusedText

  fileprivate var label: String {
    switch self {
    case .transcript: "Transcript"
    case .focusedText: "Text"
    }
  }
}

final class LLMAdjustmentClient: Sendable {
  /// Captures the display showing the app, or returns `nil` when capture is unavailable.
  typealias ScreenCapture = @Sendable (FrontmostApp?, ScreenshotResolution) async -> String?

  static let captureDisplay: ScreenCapture = {
    await ScreenContext().displayJPEGDataURL(showing: $0, resolution: $1)
  }

  private let apiKey: String
  private let baseURL: String
  private let captureScreen: ScreenCapture

  init(
    apiKey: String,
    baseURL: String,
    captureScreen: @escaping ScreenCapture = captureDisplay
  ) {
    self.apiKey = apiKey
    self.baseURL = baseURL
    self.captureScreen = captureScreen
  }

  func polish(
    _ text: String,
    as source: PolishSource,
    settings: DictationSettings,
    app: FrontmostApp?
  ) async throws -> LLMRefinement {
    let operation: PolishOperation
    switch source {
    case .focusedText:
      operation = .restyle(settings.polishStyle)
    case .transcript:
      guard let selected = settings.dictationPolishOperation else {
        throw ConfigurationValidationError(
          "After transcription is Off. No dictation polishing request was sent.")
      }
      operation = selected
    }
    return try await polish(text, as: source, operation: operation, settings: settings, app: app)
  }

  /// Replays archived text through one operation with current settings, retaining its app context but never attaching today's screen to an old message.
  func replay(
    _ item: TranscriptHistoryItem, operation: PolishOperation, settings: DictationSettings
  ) async throws -> LLMRefinement {
    var settings = settings
    settings.includeScreenshot = false
    let app: FrontmostApp?
    if let name = item.targetAppName, let identifier = item.targetAppBundleIdentifier {
      app = FrontmostApp(name: name, bundleIdentifier: identifier)
    } else {
      app = nil
    }
    let source: PolishSource = operation == .refine ? .transcript : .focusedText
    return try await polish(
      item.polishInput, as: source, operation: operation, settings: settings, app: app)
  }

  /// Attaches a capture of the app's display when screen context is on; a failed capture still sends the text, and `includedScreenshot` records which happened.
  private func polish(
    _ text: String,
    as source: PolishSource,
    operation: PolishOperation,
    settings: DictationSettings,
    app: FrontmostApp?
  ) async throws -> LLMRefinement {
    if case .restyle = operation {
      try settings.validateRestyle()
    }
    try validateConfiguration(model: settings.adjustmentModel)
    let model = settings.adjustmentModel.trimmingCharacters(in: .whitespacesAndNewlines)
    let screenshotDataURL: String? =
      if settings.includeScreenshot {
        await captureScreen(app, settings.screenshotResolution)
      } else {
        nil
      }
    let instruction = settings.polishPreferences.systemInstruction(
      preferredVocabulary: settings.keytermList,
      additionalInstructions: settings.adjustmentPrompt,
      operation: operation
    )
    let userText = """
      \(appContextText(app))

      \(source.label):
      \(text)
      """
    let request = try Self.chatCompletionsRequest(
      apiKey: apiKey,
      baseURL: baseURL,
      timeout: 60,
      body: Self.requestBody(
        systemInstruction: instruction,
        userText: userText,
        screenshotDataURL: screenshotDataURL,
        model: model
      )
    )
    let response = try chatResponse(
      from: await Self.send(request, errorDomain: "Vhrase.AdjustmentChatHTTP"))
    return LLMRefinement(
      input: text,
      output: response.text,
      model: model,
      systemInstruction: instruction,
      includedScreenshot: screenshotDataURL != nil,
      usage: response.usage,
      style: operation.style
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

  /// Lets a caller fail before starting work a polish request would waste; `polish` also runs it before capturing the screen, so nothing sensitive is gathered for a request that cannot be sent.
  func validateConfiguration(model: String) throws {
    guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw NSError(
        domain: "Vhrase.Adjustment",
        code: 3,
        userInfo: [NSLocalizedDescriptionKey: "Choose an LLM model before polishing text."]
      )
    }
    guard !apiKey.isEmpty else {
      throw NSError(
        domain: "Vhrase.Adjustment",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "LLM API key is required for LLM adjustments."]
      )
    }
    _ = try LLMEndpoint(baseURL: baseURL)
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
