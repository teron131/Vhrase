// Verifies polishing policy is sent as a system message and editable source remains user content, that a polish request sends the trimmed model and records whether screen context was attached, and that each request's token usage and the model's catalog price are read back.

import Foundation

@main
struct LLMAdjustmentRequestCheck {
  static func main() async throws {
    let data = try LLMAdjustmentClient.requestBody(
      systemInstruction: "SYSTEM CONTRACT",
      userText: "Transcript:\nSOURCE TEXT",
      screenshotDataURL: "data:image/png;base64,AAAA",
      model: "provider/model"
    )
    let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let messages = root["messages"] as! [[String: Any]]
    precondition(messages.count == 2)
    precondition(messages[0]["role"] as? String == "system")
    precondition(messages[1]["role"] as? String == "user")

    let systemContent = messages[0]["content"] as! [[String: Any]]
    let userContent = messages[1]["content"] as! [[String: Any]]
    precondition(systemContent.count == 1)
    precondition(systemContent[0]["text"] as? String == "SYSTEM CONTRACT")
    precondition(!String(describing: systemContent).contains("SOURCE TEXT"))
    precondition(userContent.count == 2)
    precondition(userContent[0]["type"] as? String == "image_url")
    precondition(userContent[1]["text"] as? String == "Transcript:\nSOURCE TEXT")

    // Both operations share HTTP transport but retain their distinct diagnostic domains.
    URLProtocol.registerClass(RejectedCompletion.self)
    defer { URLProtocol.unregisterClass(RejectedCompletion.self) }
    let client = LLMAdjustmentClient(apiKey: "test-key", baseURL: "https://vhrase-check.invalid/v1")
    do {
      try await client.checkModel("provider/model")
      preconditionFailure("Expected the access probe to fail.")
    } catch {
      precondition((error as NSError).domain == "Vhrase.LLMModelsHTTP")
      precondition((error as NSError).code == 403)
      precondition(error.localizedDescription == "Access denied")
    }
    do {
      _ = try await client.polish("Source", as: .transcript, settings: .defaults, app: nil)
      preconditionFailure("Expected adjustment to fail.")
    } catch {
      precondition((error as NSError).domain == "Vhrase.AdjustmentChatHTTP")
      precondition((error as NSError).code == 403)
      precondition(error.localizedDescription == "Access denied")
    }
    try await verifyUsageAndPrice()
    print("LLM adjustment request ok")
  }
}

private func verifyUsageAndPrice() async throws {
  URLProtocol.registerClass(StubbedEndpoint.self)
  defer { URLProtocol.unregisterClass(StubbedEndpoint.self) }
  var settings = DictationSettings.defaults
  settings.adjustmentModel = " gpt-6-luna\n"
  settings.includeScreenshot = true
  let priced = LLMAdjustmentClient(
    apiKey: "test-key", baseURL: "https://vhrase-priced.invalid/v1",
    captureScreen: { _, _ in "data:image/jpeg;base64,AAAA" })

  let refinement = try await priced.polish("source", as: .transcript, settings: settings, app: nil)
  let usage = LLMUsage(inputTokens: 2_480, outputTokens: 120)
  precondition(refinement.output == "Polished." && refinement.usage == usage)
  precondition(refinement.model == "gpt-6-luna" && refinement.includedScreenshot)
  let polished = try await priced.polish(
    "source", as: .focusedText, settings: settings,
    app: FrontmostApp(name: "Notes", bundleIdentifier: "com.apple.Notes"))
  precondition(polished.output == "Polished." && polished.usage == usage)

  // A bare model name finds the gateway's provider-qualified entry; the price is per token.
  let price = try await priced.listPrice(for: "gpt-6-luna")
  precondition(price == LLMPrice(inputPerToken: 0.0000001, outputPerToken: 0.0000005))
  precondition(abs(price!.cost(of: usage) - 0.000308) < 1e-12)
  let inputOnly = try await priced.listPrice(for: "gpt-6-luna-decisions")
  let unlisted = try await priced.listPrice(for: "missing-model")
  precondition(inputOnly == nil && unlisted == nil)

  // A failed capture still sends the text, without screen context.
  let plain = LLMAdjustmentClient(
    apiKey: "test-key", baseURL: "https://vhrase-plain.invalid/v1", captureScreen: { _, _ in nil })
  let unreported = try await plain.polish("source", as: .transcript, settings: settings, app: nil)
  precondition(unreported.output == "Polished." && unreported.usage == nil)
  precondition(!unreported.includedScreenshot)
  let unpublished = try await plain.listPrice(for: "gpt-6-luna")
  precondition(unpublished == nil)
}

/// Answers chat and catalog requests like Vercel AI Gateway on `vhrase-priced.invalid`, and like an endpoint without usage or prices on `vhrase-plain.invalid`.
private final class StubbedEndpoint: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool {
    ["vhrase-priced.invalid", "vhrase-plain.invalid"].contains(request.url?.host)
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let isPriced = request.url?.host == "vhrase-priced.invalid"
    let body =
      switch (request.url?.lastPathComponent, isPriced) {
      case ("completions", true):
        #"{"choices":[{"message":{"content":"Polished."}}],"usage":{"prompt_tokens":2480,"completion_tokens":120}}"#
      case ("completions", false):
        #"{"choices":[{"message":{"content":"Polished."}}]}"#
      case (_, true):
        #"{"data":[{"id":"openai/gpt-6-luna","pricing":{"input":"0.0000001","output":"0.0000005"}},{"id":"openai/gpt-6-luna-decisions","pricing":{"input":"0.0000001"}}]}"#
      case (_, false):
        #"{"data":[{"id":"gpt-6-luna","object":"model"}]}"#
      }
    let response = HTTPURLResponse(
      url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

private final class RejectedCompletion: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "vhrase-check.invalid"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let response = HTTPURLResponse(
      url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data("Access denied".utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
