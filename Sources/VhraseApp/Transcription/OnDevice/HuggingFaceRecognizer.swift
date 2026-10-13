// Runs Hugging Face recognition on this Mac behind the transcript contract shared with the cloud providers, keeping one Python server with the model named in settings and stopping it after a quiet period.

import Foundation
import OSLog

/// Owns the helper's `serve` process; starting it never downloads a model, because the Hub client runs offline there.
actor HuggingFaceRecognizer: SpeechToTextClient {
  /// Keeps roughly a working session warm without holding the model's memory in an idle menu-bar app.
  private static let idleUnloadDelay = Duration.seconds(300)

  private var server: HuggingFaceServer?
  private var idleUnloadTask: Task<Void, Never>?
  private let logger = Logger(subsystem: "local.codex.Vhrase", category: "HuggingFace")

  /// Starts the server and loads a model ahead of transcription, typically while the user is still speaking.
  func load(model: String) async throws {
    let started = ContinuousClock.now
    let reply = try await request(["op": "load", "model": model])
    let seconds = started.duration(to: .now) / .seconds(1)
    logger.notice(
      "Model loaded device=\(reply.device ?? "", privacy: .public) precision=\(reply.precision ?? "", privacy: .public) seconds=\(seconds, format: .fixed(precision: 2))"
    )
    scheduleIdleUnload()
  }

  /// Transcribes a finished recording with the model named in settings; the language code reaches only multilingual Whisper models, and cancellation stops the server without returning text.
  func transcribe(fileURL: URL, settings: DictationSettings) async throws -> TranscriptionResult {
    let model = settings.huggingFaceModel.trimmingCharacters(in: .whitespacesAndNewlines)
    guard HuggingFaceModel.isInstalled(model) else {
      throw HuggingFaceError.notDownloaded(model)
    }
    idleUnloadTask?.cancel()
    defer { scheduleIdleUnload() }
    var payload = ["op": "transcribe", "model": model, "path": fileURL.path]
    let language = settings.language.trimmingCharacters(in: .whitespacesAndNewlines)
    if !language.isEmpty {
      payload["language"] = language
    }
    let started = ContinuousClock.now
    let reply = try await request(payload)
    try Task.checkCancellation()
    let seconds = started.duration(to: .now) / .seconds(1)
    logger.notice("Transcribed seconds=\(seconds, format: .fixed(precision: 2))")
    return TranscriptionResult(
      text: (reply.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
      providerName: STTProvider.huggingFace.title
    )
  }

  /// Stops the server, which releases the model's memory, for example before its files are removed.
  func unload() {
    idleUnloadTask?.cancel()
    idleUnloadTask = nil
    server?.stop()
    server = nil
  }

  /// Sends one request to the running server, starting it when needed; a server that stopped is forgotten so the next request starts a fresh one.
  private func request(_ payload: [String: String]) async throws -> HuggingFaceServer.Reply {
    let server = try server ?? HuggingFaceServer()
    self.server = server
    do {
      let reply = try await server.exchange(payload)
      guard reply.ok else {
        throw HuggingFaceError.failed(reply.error ?? "Hugging Face recognition failed.")
      }
      return reply
    } catch let error as HuggingFaceError {
      if case .stopped = error {
        if self.server === server {
          self.server = nil
        }
        // Cancelling a request stops the server; callers see one cancellation outcome.
        if Task.isCancelled { throw CancellationError() }
      }
      throw error
    }
  }

  private func scheduleIdleUnload() {
    idleUnloadTask?.cancel()
    idleUnloadTask = Task { [weak self] in
      do {
        try await Task.sleep(for: Self.idleUnloadDelay)
      } catch {
        return
      }
      await self?.unload()
    }
  }
}

/// One running `serve` process; a serial queue pairs each request line with its reply line, so a warm-up and a transcription never read each other's answer.
private final class HuggingFaceServer: @unchecked Sendable {
  struct Reply: Decodable {
    let ok: Bool
    let text: String?
    let error: String?
    let device: String?
    let precision: String?
  }

  /// Bounds a request the Python process never answers; loading and a long dictation both finish well inside it.
  private static let requestTimeout = DispatchTimeInterval.seconds(600)

  private let helper: HuggingFaceProcess
  private let queue = DispatchQueue(label: "local.codex.Vhrase.HuggingFaceServer")
  private var buffer = Data()

  init() throws {
    helper = try HuggingFaceRuntime.start(["serve"], allowsModelDownload: false)
  }

  /// Cancelling the calling task stops the process, which is the only way to interrupt a model mid-inference.
  func exchange(_ request: [String: String]) async throws -> Reply {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        queue.async {
          continuation.resume(with: Result { try self.exchangeOnQueue(request) })
        }
      }
    } onCancel: {
      helper.stop()
    }
  }

  func stop() {
    helper.stop()
  }

  private func exchangeOnQueue(_ request: [String: String]) throws -> Reply {
    let timeout = DispatchWorkItem { [helper] in helper.stop() }
    DispatchQueue.global().asyncAfter(deadline: .now() + Self.requestTimeout, execute: timeout)
    defer { timeout.cancel() }
    do {
      try helper.input.write(contentsOf: JSONEncoder().encode(request) + Data([0x0A]))
    } catch {
      throw HuggingFaceError.stopped(helper.lastErrorLine)
    }
    guard let line = readLine() else {
      throw HuggingFaceError.stopped(helper.lastErrorLine)
    }
    return try JSONDecoder().decode(Reply.self, from: line)
  }

  /// Blocks until the server writes a whole line, or returns `nil` once it has exited.
  private func readLine() -> Data? {
    while true {
      if let newline = buffer.firstIndex(of: 0x0A) {
        let line = Data(buffer[buffer.startIndex..<newline])
        buffer = Data(buffer[buffer.index(after: newline)...])
        return line
      }
      let chunk = helper.output.availableData
      if chunk.isEmpty {
        return nil
      }
      buffer.append(chunk)
    }
  }
}
