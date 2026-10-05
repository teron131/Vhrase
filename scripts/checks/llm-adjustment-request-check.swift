// Verifies polishing policy is sent as a system message and editable source remains user content.

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
      _ = try await client.adjust(
        transcript: "Source", screenshotDataURL: nil, settings: .defaults, app: nil)
      preconditionFailure("Expected adjustment to fail.")
    } catch {
      precondition((error as NSError).domain == "Vhrase.AdjustmentChatHTTP")
      precondition((error as NSError).code == 403)
      precondition(error.localizedDescription == "Access denied")
    }
    print("LLM adjustment request ok")
  }
}

/// Rejects only this check's synthetic endpoint without making a network request.
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
