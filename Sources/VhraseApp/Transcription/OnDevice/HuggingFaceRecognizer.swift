// Runs Hugging Face recognition on this Mac behind the shared transcript contract, keeping one Python server warm while memory permits and releasing it on inactivity or memory pressure.

import Foundation
import OSLog

/// Owns the helper's `serve` process; starting it never downloads a model, because the Hub client runs offline there.
actor HuggingFaceRecognizer: SpeechToTextClient {
  /// Avoids repeated cold starts during a working session; memory pressure can end the warm period sooner.
  static let idleUnloadDelay = Duration.seconds(600)

  private var server: HuggingFaceServer?
  private var idleUnloadTask: Task<Void, Never>?
  private var activeRequests = 0
  private var shutdown: (id: UUID, task: Task<Void, Never>)?
  private let memoryPressureSource: any DispatchSourceMemoryPressure
  private var isMemoryConstrained = false
  private let logger = Logger(subsystem: "local.codex.Vhrase", category: "HuggingFace")

  init() {
    let source = DispatchSource.makeMemoryPressureSource(
      eventMask: [.normal, .warning, .critical], queue: .global(qos: .utility))
    memoryPressureSource = source
    source.setEventHandler { [weak self, weak source] in
      guard let event = source?.data else { return }
      let isElevated = !event.intersection([.warning, .critical]).isEmpty
      Task { [weak self] in await self?.handleMemoryPressure(isElevated: isElevated) }
    }
    source.activate()
  }

  deinit {
    memoryPressureSource.cancel()
  }

  /// Starts the server and loads a model ahead of transcription, typically while the user is still speaking.
  func load(model: String) async throws {
    guard !isMemoryConstrained else { return }
    let started = ContinuousClock.now
    let reply = try await request(["op": "load", "model": model])
    let seconds = started.duration(to: .now) / .seconds(1)
    logger.notice(
      "Model loaded device=\(reply.device ?? "", privacy: .public) precision=\(reply.precision ?? "", privacy: .public) seconds=\(seconds, format: .fixed(precision: 2))"
    )
  }

  /// Transcribes a finished recording with the model named in settings; the language code reaches only multilingual Whisper models, and cancellation stops the server without returning text.
  func transcribe(fileURL: URL, settings: DictationSettings) async throws -> TranscriptionResult {
    let model = settings.huggingFaceModel.trimmingCharacters(in: .whitespacesAndNewlines)
    guard HuggingFaceModel.isInstalled(model) else {
      throw HuggingFaceError.notDownloaded(model)
    }
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
  func unload() async {
    idleUnloadTask?.cancel()
    idleUnloadTask = nil
    guard let server else {
      await shutdown?.task.value
      return
    }
    self.server = nil
    await stop(server)
  }

  /// Gives idle model memory back under system pressure; an active request finishes before its helper is released, and speculative warm-ups wait for normal pressure.
  func handleMemoryPressure(isElevated: Bool) async {
    isMemoryConstrained = isElevated
    guard isElevated else { return }
    await unloadIfIdle()
  }

  /// Sends one request to the running server, starting it when needed; a server that stopped is forgotten so the next request starts a fresh one.
  private func request(_ payload: [String: String]) async throws -> HuggingFaceServer.Reply {
    idleUnloadTask?.cancel()
    activeRequests += 1
    defer {
      activeRequests -= 1
      scheduleIdleUnload()
    }
    if let server, server.isStopping {
      self.server = nil
      await stop(server)
    }
    await shutdown?.task.value
    try Task.checkCancellation()
    let server = try server ?? HuggingFaceServer()
    self.server = server
    let reply: HuggingFaceServer.Reply
    do {
      reply = try await server.exchange(payload)
      try Task.checkCancellation()
    } catch {
      if self.server === server {
        self.server = nil
        await stop(server)
      }
      if Task.isCancelled { throw CancellationError() }
      throw error
    }
    guard reply.ok else {
      throw HuggingFaceError.failed(reply.error ?? "Hugging Face recognition failed.")
    }
    return reply
  }

  /// Keeps a replacement from loading while a cancelled or idle helper is still releasing its model.
  private func stop(_ server: HuggingFaceServer) async {
    let id = UUID()
    let task = Task { await server.stop() }
    shutdown = (id, task)
    await task.value
    if shutdown?.id == id { shutdown = nil }
  }

  private func scheduleIdleUnload() {
    // A warm-up reply may arrive while a transcription is queued or running in the same server.
    guard activeRequests == 0, server != nil else { return }
    idleUnloadTask?.cancel()
    let delay = isMemoryConstrained ? .zero : Self.idleUnloadDelay
    idleUnloadTask = Task { [weak self] in
      do {
        try await Task.sleep(for: delay)
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      // A new request can start after the timer wakes but before this actor resumes.
      await self?.unloadIfIdle()
    }
  }

  private func unloadIfIdle() async {
    guard activeRequests == 0 else { return }
    await unload()
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

  var isStopping: Bool { helper.isStopping }

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

  func stop() async {
    helper.stop()
    await helper.waitForExit()
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
