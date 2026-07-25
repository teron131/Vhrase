// Calls an OpenAI-compatible language model through a validated endpoint with optional application context.

import Darwin
import Foundation

final class LLMModelAccessClient: @unchecked Sendable {
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

final class LLMAdjustmentClient: @unchecked Sendable {
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

    var request = URLRequest(url: try endpoint("chat/completions"))
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
    if !settings.keytermList.isEmpty {
      sections.append(
        "Preferred vocabulary spellings:\n\(settings.keytermList.joined(separator: "\n"))"
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

  private func endpoint(_ path: String) throws -> URL {
    try LLMEndpoint(baseURL: baseURL).appending(path)
  }
}

/// Validates a user-configurable LLM base URL once and safely derives API endpoint URLs from it.
struct LLMEndpoint {
  private let baseURL: URL

  init(baseURL: String) throws {
    self.baseURL = try Self.validatedBaseURL(baseURL)
  }

  /// Returns a canonical HTTP(S) base URL after enforcing transport, authority, host, port, and path policy.
  static func validatedBaseURL(_ rawValue: String) throws -> URL {
    let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty,
      !value.contains("\\"),
      !value.unicodeScalars.contains(where: {
        CharacterSet.whitespacesAndNewlines.contains($0)
          || CharacterSet.controlCharacters.contains($0)
      }),
      var components = URLComponents(string: value),
      let rawScheme = components.scheme
    else {
      throw invalidBaseURL("LLM base URL must be an absolute HTTP or HTTPS URL.")
    }

    let scheme = rawScheme.lowercased()
    guard scheme == "http" || scheme == "https" else {
      throw invalidBaseURL("LLM base URL must use HTTP or HTTPS.")
    }
    guard components.user == nil, components.password == nil else {
      throw invalidBaseURL("LLM base URL must not include user credentials.")
    }
    guard components.query == nil, components.fragment == nil else {
      throw invalidBaseURL("LLM base URL must not include a query or fragment.")
    }
    if let componentString = components.string,
      let hostRange = components.rangeOfHost,
      componentString[hostRange.upperBound...].first == ":"
    {
      guard let portRange = components.rangeOfPort,
        !portRange.isEmpty
      else {
        throw invalidBaseURL("LLM base URL must not include an empty port.")
      }
    }
    if let port = components.port,
      !(1...65_535).contains(port)
    {
      throw invalidBaseURL("LLM base URL port must be between 1 and 65535.")
    }

    guard let encodedHost = components.percentEncodedHost,
      !encodedHost.contains("%"),
      let parsedURL = components.url,
      let host = parsedURL.host?.lowercased(),
      isValidHost(host)
    else {
      throw invalidBaseURL("LLM base URL must include a valid host.")
    }

    let isLoopback =
      host == "localhost"
      || host == "127.0.0.1"
      || host == "::1"
    guard scheme == "https" || isLoopback else {
      throw invalidBaseURL(
        "LLM base URL must use HTTPS; HTTP is allowed only for localhost, 127.0.0.1, or [::1]."
      )
    }

    components.scheme = scheme
    components.percentEncodedPath = try canonicalBasePath(components.percentEncodedPath)
    guard let canonicalURL = components.url,
      canonicalURL.host?.lowercased() == host
    else {
      throw invalidBaseURL("LLM base URL is invalid.")
    }
    return canonicalURL
  }

  /// Appends a relative API path without allowing it to replace or reinterpret the validated base URL.
  func appending(_ path: String) throws -> URL {
    let segments = path.split(
      separator: "/",
      omittingEmptySubsequences: false
    )
    guard !segments.isEmpty,
      segments.allSatisfy({ Self.isValidEndpointPathSegment($0) })
    else {
      throw Self.invalidBaseURL("LLM endpoint path is invalid.")
    }

    return segments.reduce(baseURL) { url, segment in
      url.appendingPathComponent(String(segment), isDirectory: false)
    }
  }

  /// Rejects repeated separators, traversal, and encoded separators while preserving ordinary gateway prefixes such as `/v1`.
  private static func canonicalBasePath(_ path: String) throws -> String {
    guard path.isEmpty || path.hasPrefix("/") else {
      throw invalidBaseURL("LLM base URL path is invalid.")
    }
    guard !path.isEmpty else {
      return ""
    }

    var segments = Array(
      path.split(
        separator: "/",
        omittingEmptySubsequences: false
      )
      .dropFirst()
    )
    if segments.last?.isEmpty == true {
      segments.removeLast()
    }

    for segment in segments {
      guard !segment.isEmpty,
        let decoded = String(segment).removingPercentEncoding,
        !decoded.isEmpty,
        decoded != ".",
        decoded != "..",
        !decoded.contains("/"),
        !decoded.contains("\\"),
        !decoded.contains("?"),
        !decoded.contains("#"),
        !decoded.unicodeScalars.contains(where: {
          CharacterSet.whitespacesAndNewlines.contains($0)
            || CharacterSet.controlCharacters.contains($0)
        })
      else {
        throw invalidBaseURL("LLM base URL path is ambiguous.")
      }
    }

    return segments.isEmpty ? "" : "/\(segments.joined(separator: "/"))"
  }

  private static func isValidEndpointPathSegment(_ segment: Substring) -> Bool {
    guard !segment.isEmpty,
      segment != ".",
      segment != ".."
    else {
      return false
    }

    return segment.utf8.allSatisfy { byte in
      isASCIIAlphaNumeric(byte)
        || byte == 0x2D
        || byte == 0x2E
        || byte == 0x5F
        || byte == 0x7E
    }
  }

  private static func isValidHost(_ host: String) -> Bool {
    if isIPv4Address(host) || isIPv6Address(host) {
      return true
    }
    if host.utf8.allSatisfy({ byte in
      (0x30...0x39).contains(byte) || byte == 0x2E
    }) {
      return false
    }

    let labels = host.split(
      separator: ".",
      omittingEmptySubsequences: false
    )
    guard !labels.isEmpty,
      host.utf8.count <= 253
    else {
      return false
    }

    return labels.allSatisfy { label in
      guard let first = label.utf8.first,
        let last = label.utf8.last,
        (1...63).contains(label.utf8.count),
        isASCIIAlphaNumeric(first),
        isASCIIAlphaNumeric(last)
      else {
        return false
      }
      return label.utf8.allSatisfy { byte in
        isASCIIAlphaNumeric(byte) || byte == 0x2D
      }
    }
  }

  private static func isIPv4Address(_ host: String) -> Bool {
    var address = in_addr()
    return host.withCString { pointer in
      inet_pton(AF_INET, pointer, &address) == 1
    }
  }

  private static func isIPv6Address(_ host: String) -> Bool {
    var address = in6_addr()
    return host.withCString { pointer in
      inet_pton(AF_INET6, pointer, &address) == 1
    }
  }

  private static func isASCIIAlphaNumeric(_ byte: UInt8) -> Bool {
    (0x30...0x39).contains(byte)
      || (0x41...0x5A).contains(byte)
      || (0x61...0x7A).contains(byte)
  }

  private static func invalidBaseURL(_ description: String) -> NSError {
    NSError(
      domain: "Vhrase.LLMEndpoint",
      code: 1,
      userInfo: [NSLocalizedDescriptionKey: description]
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
