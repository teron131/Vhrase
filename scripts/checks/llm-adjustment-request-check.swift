// Exercises production polishing transport with stubbed endpoints, including source isolation, selected-style validation, usage, and pricing.

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
      var refining = DictationSettings.defaults
      refining.adjustmentModel = "test-model"
      refining.afterTranscription = .refine
      _ = try await client.polish("Source", as: .transcript, settings: refining, app: nil)
      preconditionFailure("Expected adjustment to fail.")
    } catch {
      precondition((error as NSError).domain == "Vhrase.AdjustmentChatHTTP")
      precondition((error as NSError).code == 403)
      precondition(error.localizedDescription == "Access denied")
    }
    try await verifyUsageAndPrice()
    try await verifyStyleRequests()
    try await verifyEmptyCustom()
    try await verifyHistoryRestyle()
    await verifyBatchRestyle()
    print("LLM adjustment request ok")
  }
}

private func verifyUsageAndPrice() async throws {
  URLProtocol.registerClass(StubbedEndpoint.self)
  defer { URLProtocol.unregisterClass(StubbedEndpoint.self) }
  var settings = DictationSettings.defaults
  settings.adjustmentModel = " gpt-6-luna\n"
  settings.afterTranscription = .refine
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

private func verifyStyleRequests() async throws {
  URLProtocol.registerClass(StubbedEndpoint.self)
  defer { URLProtocol.unregisterClass(StubbedEndpoint.self) }
  let client = LLMAdjustmentClient(apiKey: "test-key", baseURL: "https://vhrase-style.invalid/v1")
  var settings = DictationSettings.defaults
  settings.adjustmentModel = "test-model"
  settings.includeScreenshot = false
  let customStyle = PolishStyle(title: "Unlisted style", instruction: "Group related ideas.")
  settings.customRestyleName = customStyle.title
  settings.customRestyleInstruction = customStyle.instruction
  for (choice, style) in zip(RestyleChoice.allCases, [PolishStyle.rephrase, .genZ, customStyle]) {
    settings.restyleChoice = choice
    for mode in DictationPolishing.allCases {
      settings.afterTranscription = mode
      for source in [PolishSource.transcript, .focusedText] {
        if source == .transcript && mode == .off {
          do {
            _ = try await client.polish("source", as: source, settings: settings, app: nil)
            preconditionFailure("Off must not send a dictation polish request.")
          } catch let error as ConfigurationValidationError {
            precondition(error.message.contains("After transcription is Off"))
          }
          continue
        }
        let expectedOperation: PolishOperation =
          source == .focusedText || mode == .restyle ? .restyle(style) : .refine
        let expected = settings.polishPreferences.systemInstruction(
          preferredVocabulary: settings.keytermList,
          additionalInstructions: settings.adjustmentPrompt, operation: expectedOperation)
        let result = try await client.polish("source", as: source, settings: settings, app: nil)
        precondition(result.operation == expectedOperation)
        precondition(result.systemInstruction == expected)
        precondition(
          result.output == expected, "The system instruction must reach the request body.")
      }
    }
  }
}

private func verifyEmptyCustom() async throws {
  URLProtocol.registerClass(StubbedEndpoint.self)
  defer { URLProtocol.unregisterClass(StubbedEndpoint.self) }
  let client = LLMAdjustmentClient(
    apiKey: "test-key", baseURL: "https://vhrase-style.invalid/v1",
    captureScreen: { _, _ in
      preconditionFailure("An empty Custom instruction must fail before screen capture.")
    })
  var settings = DictationSettings.defaults
  settings.adjustmentModel = "test-model"
  settings.restyleChoice = .custom
  settings.customRestyleInstruction = " \n\t"
  for mode in DictationPolishing.allCases {
    settings.afterTranscription = mode
    for source in [PolishSource.transcript, .focusedText] {
      let usesCustom = source == .focusedText || mode == .restyle
      settings.includeScreenshot = usesCustom
      if source == .transcript && mode == .off { continue }
      if usesCustom {
        do {
          _ = try await client.polish("source", as: source, settings: settings, app: nil)
          preconditionFailure("An empty Custom instruction was sent.")
        } catch let error as ConfigurationValidationError {
          precondition(
            error.message
              == "Enter a Custom Restyle instruction on Polishing before restyling text.")
        }
      } else {
        let result = try await client.polish("source", as: source, settings: settings, app: nil)
        precondition(result.operation == .refine)
      }
    }
  }
}

private func verifyHistoryRestyle() async throws {
  URLProtocol.registerClass(StubbedEndpoint.self)
  defer { URLProtocol.unregisterClass(StubbedEndpoint.self) }
  let client = LLMAdjustmentClient(
    apiKey: "test-key", baseURL: "https://vhrase-history.invalid/v1",
    captureScreen: { _, _ in preconditionFailure("History tests must not capture today's screen.") }
  )
  var settings = DictationSettings.defaults
  settings.restyleChoice = .custom
  settings.customRestyleName = "Concise"
  settings.customRestyleInstruction = "Keep each request concise."
  settings.adjustmentModel = "test-history-model"
  settings.includeScreenshot = true
  var item = TranscriptHistoryItem(
    id: UUID(), createdAt: Date(), text: "Previously delivered text.",
    provider: "Test", transcriptionMode: "Upload", cleanup: .llm,
    targetAppName: "Notes", targetAppBundleIdentifier: "com.apple.Notes",
    refinement: LLMRefinement(
      input: "Original dictation input.", output: "Old rewrite.", model: "old-model",
      systemInstruction: "old-instruction", includedScreenshot: true, usage: nil, style: .genZ))
  for mode in DictationPolishing.allCases {
    settings.afterTranscription = mode
    let result = try await client.replay(
      item, operation: .restyle(settings.polishStyle), settings: settings)
    precondition(result.input == "Original dictation input.")
    precondition(result.output.contains("Text:\nOriginal dictation input."))
    precondition(result.output.contains("Notes") && result.output.contains("com.apple.Notes"))
    precondition(!result.output.contains(item.text))
    precondition(result.model == "test-history-model" && result.style == settings.polishStyle)
    precondition(result.systemInstruction.contains(settings.customRestyleInstruction))
    precondition(!result.includedScreenshot && settings.includeScreenshot)
  }
  let refined = try await client.replay(item, operation: .refine, settings: settings)
  precondition(refined.output.contains("Transcript:\nOriginal dictation input."))
  precondition(refined.style == nil && !refined.includedScreenshot)
  item.refinement = nil
  let older = try await client.replay(
    item, operation: .restyle(settings.polishStyle), settings: settings)
  precondition(older.input == item.text && older.output.contains(item.text))
}

@MainActor
private func verifyBatchRestyle() async {
  URLProtocol.registerClass(BatchEndpoint.self)
  defer { URLProtocol.unregisterClass(BatchEndpoint.self) }
  let history = (0..<7).map { index in
    TranscriptHistoryItem(
      id: UUID(), createdAt: Date(timeIntervalSince1970: Double(7 - index)),
      text: "Dictation \(index)", provider: "Test", transcriptionMode: "Upload", cleanup: .raw,
      targetAppName: nil, targetAppBundleIdentifier: nil)
  }
  let samples = PolishTest.recentHistory(history)
  precondition(samples == Array(history.prefix(5)))
  var settings = DictationSettings.defaults
  settings.adjustmentModel = "test-model"
  settings.afterTranscription = .off
  settings.includeScreenshot = true
  let client = LLMAdjustmentClient(
    apiKey: "test-key", baseURL: "https://vhrase-batch.invalid/v1",
    captureScreen: { _, _ in preconditionFailure("Batch testing must not capture the screen.") })
  let test = PolishTest()
  let starts = BatchEndpoint.probe.begin()
  let first = test.start(
    history: history, operation: .restyle(settings.polishStyle), settings: settings, client: client)
  precondition(test.state.isRunning && test.state.outcomes.count == 5)
  await waitForBatchRequests(starts, count: 5)
  precondition(
    BatchEndpoint.probe.count == 5, "Five requests must start before any response is released.")
  BatchEndpoint.probe.release(mixedFailure: true)
  await first.value
  precondition(!test.state.isRunning && test.state.completedCount == 5)
  var successes = 0
  var failures = 0
  for item in samples {
    switch test.state.outcomes[item.id] {
    case .completed(let result):
      successes += 1
      precondition(
        result.input == item.text && result.style == .rephrase && !result.includedScreenshot)
    case .failed: failures += 1
    default: preconditionFailure("Each row must settle independently.")
    }
  }
  precondition(successes == 4 && failures == 1)
  precondition(test.state.outcomes[history[5].id] == nil)

  let heldStarts = BatchEndpoint.probe.begin()
  let held = test.start(
    history: history, operation: .restyle(settings.polishStyle), settings: settings, client: client)
  await waitForBatchRequests(heldStarts, count: 5)
  test.cancel()
  precondition(!test.state.isRunning && test.state.outcomes.values.allSatisfy { $0 == .cancelled })
  let replacementStarts = BatchEndpoint.probe.begin()
  let replacementItems = Array(history.suffix(2))
  let replacement = test.start(
    history: replacementItems, operation: .restyle(settings.polishStyle), settings: settings,
    client: client)
  await waitForBatchRequests(replacementStarts, count: 2)
  BatchEndpoint.probe.release(mixedFailure: false)
  await replacement.value
  await held.value
  precondition(Set(test.state.outcomes.keys) == Set(replacementItems.map(\.id)))
  for item in replacementItems {
    guard case .completed(let result) = test.state.outcomes[item.id] else {
      preconditionFailure("Cancelled requests must not overwrite the replacement batch.")
    }
    precondition(result.input == item.text)
  }

  _ = BatchEndpoint.probe.begin()
  settings.restyleChoice = .custom
  await test.start(
    history: history, operation: .restyle(settings.polishStyle), settings: settings, client: client
  ).value
  guard case .failed(let message) = test.state else {
    preconditionFailure("Expected one setup error.")
  }
  precondition(message.contains("Custom Restyle instruction") && BatchEndpoint.probe.count == 0)
  await test.start(
    history: [], operation: .restyle(settings.polishStyle), settings: settings, client: client
  ).value
  precondition(test.state == .idle && BatchEndpoint.probe.count == 0)
  test.clear()
  precondition(test.state == .idle)
  print(
    "Restyle batch: five concurrent requests, per-row failure, cancellation, replacement, and empty/setup states ok"
  )
}

private func waitForBatchRequests(_ starts: AsyncStream<Int>, count: Int) async {
  for await value in starts where value >= count { return }
  preconditionFailure("Timed out waiting for concurrent Restyle requests.")
}

private final class BatchEndpoint: URLProtocol, @unchecked Sendable {
  static let probe = BatchProbe()
  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "vhrase-batch.invalid"
  }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() { Self.probe.add(self) }
  override func stopLoading() { Self.probe.remove(self) }

  func respond(failing: Bool) {
    let response = HTTPURLResponse(
      url: request.url!, statusCode: failing ? 503 : 200, httpVersion: nil, headerFields: nil)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(
      self,
      didLoad: Data(
        (failing ? "Test failure" : #"{"choices":[{"message":{"content":"Restyled result."}}]}"#)
          .utf8))
    client?.urlProtocolDidFinishLoading(self)
  }
}

private final class BatchProbe: @unchecked Sendable {
  private let lock = NSLock()
  private var pending: [BatchEndpoint] = []
  private var starts = 0
  private var continuation: AsyncStream<Int>.Continuation?
  var count: Int { lock.withLock { starts } }

  func begin() -> AsyncStream<Int> {
    let (stream, continuation) = AsyncStream<Int>.makeStream(bufferingPolicy: .bufferingNewest(1))
    lock.withLock {
      self.continuation?.finish()
      pending = []
      starts = 0
      self.continuation = continuation
    }
    DispatchQueue.global().asyncAfter(deadline: .now() + 4) { continuation.finish() }
    return stream
  }

  func add(_ endpoint: BatchEndpoint) {
    lock.withLock {
      pending.append(endpoint)
      starts += 1
      continuation?.yield(starts)
    }
  }

  func remove(_ endpoint: BatchEndpoint) {
    lock.withLock { pending.removeAll { $0 === endpoint } }
  }

  func release(mixedFailure: Bool) {
    let requests = lock.withLock {
      let requests = pending
      pending = []
      return requests
    }
    for (index, endpoint) in requests.reversed().enumerated() {
      endpoint.respond(failing: mixedFailure && index == 2)
    }
  }
}

/// Answers chat and catalog requests like Vercel AI Gateway on `vhrase-priced.invalid`, and like an endpoint without usage or prices on `vhrase-plain.invalid`.
private final class StubbedEndpoint: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool {
    [
      "vhrase-priced.invalid", "vhrase-plain.invalid", "vhrase-style.invalid",
      "vhrase-history.invalid",
    ].contains(
      request.url?.host)
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
    let data: Data
    if ["vhrase-style.invalid", "vhrase-history.invalid"].contains(request.url?.host) {
      var requestData = request.httpBody ?? Data()
      if let stream = request.httpBodyStream {
        stream.open()
        defer { stream.close() }
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
          let count = stream.read(&buffer, maxLength: buffer.count)
          precondition(count >= 0)
          if count == 0 { break }
          requestData.append(contentsOf: buffer.prefix(count))
        }
      }
      let requestBody = try! JSONSerialization.jsonObject(with: requestData) as! [String: Any]
      let messages = requestBody["messages"] as! [[String: Any]]
      precondition(messages.count == 2 && messages[0]["role"] as? String == "system")
      let content = messages[0]["content"] as! [[String: Any]]
      var echo = content[0]["text"] as! String
      if request.url?.host == "vhrase-history.invalid" {
        precondition(requestBody["model"] as? String == "test-history-model")
        let user = messages[1]["content"] as! [[String: Any]]
        precondition(user.count == 1 && user[0]["type"] as? String == "text")
        echo = user[0]["text"] as! String
      }
      data = try! JSONSerialization.data(withJSONObject: [
        "choices": [["message": ["content": echo]]]
      ])
    } else {
      data = Data(body.utf8)
    }
    client?.urlProtocol(self, didLoad: data)
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
