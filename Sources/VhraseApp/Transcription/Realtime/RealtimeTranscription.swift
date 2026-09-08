// Defines realtime transcription clients, provider sessions, and shared transport contracts.

import Foundation

protocol RealtimeTranscriptionSession: Sendable {
  func sendAudioChunk(_ data: Data)
  func finish() async throws -> TranscriptionResult
  func cancel()
}

protocol RealtimeSpeechToTextClient: Sendable {
  func start(
    settings: DictationSettings,
    onPartialTranscript: @escaping @Sendable (String) -> Void
  ) throws -> RealtimeTranscriptionSession
}

final class XAIRealtimeTranscriptionClient: RealtimeSpeechToTextClient {
  private let apiKey: String

  init(apiKey: String) {
    self.apiKey = apiKey
  }

  func start(
    settings: DictationSettings,
    onPartialTranscript: @escaping @Sendable (String) -> Void
  ) throws -> RealtimeTranscriptionSession {
    guard !apiKey.isEmpty else {
      throw realtimeMissingKey("XAI_API_KEY")
    }

    var components = URLComponents(string: "wss://api.x.ai/v1/stt")!
    components.queryItems = try XAITranscriptionContract.realtimeQueryItems(settings: settings)

    var request = URLRequest(url: components.url!)
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    return XAIRealtimeTranscriptionSession(
      request: request,
      onPartialTranscript: onPartialTranscript
    )
  }
}

final class ElevenLabsRealtimeTranscriptionClient: RealtimeSpeechToTextClient {
  private let apiKey: String

  init(apiKey: String) {
    self.apiKey = apiKey
  }

  func start(
    settings: DictationSettings,
    onPartialTranscript: @escaping @Sendable (String) -> Void
  ) throws -> RealtimeTranscriptionSession {
    guard !apiKey.isEmpty else {
      throw realtimeMissingKey("ELEVENLABS_API_KEY")
    }

    var components = URLComponents(string: "wss://api.elevenlabs.io/v1/speech-to-text/realtime")!
    components.queryItems = try ElevenLabsTranscriptionContract.realtimeQueryItems(
      settings: settings)

    var request = URLRequest(url: components.url!)
    request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
    return ElevenLabsRealtimeTranscriptionSession(
      request: request,
      onPartialTranscript: onPartialTranscript
    )
  }
}

/// Bounds audio captured while a provider WebSocket is waiting for its ready event.
struct PreReadyAudioQueue {
  static let maximumBufferedSeconds = 15
  static let maximumBufferedByteCount = maximumBufferedSeconds * 16_000 * MemoryLayout<Int16>.size

  private let maximumByteCount: Int
  private var chunks: [Data] = []
  private(set) var byteCount = 0

  init(maximumByteCount: Int = Self.maximumBufferedByteCount) {
    precondition(maximumByteCount > 0)
    self.maximumByteCount = maximumByteCount
  }

  mutating func append(
    _ data: Data,
    providerName: String
  ) throws {
    guard data.count <= maximumByteCount - byteCount else {
      throw RealtimeSessionError.preReadyAudioOverflow(
        providerName: providerName,
        maximumSeconds: Self.maximumBufferedSeconds
      )
    }
    chunks.append(data)
    byteCount += data.count
  }

  mutating func drain() -> [Data] {
    let drained = chunks
    removeAll()
    return drained
  }

  mutating func removeAll() {
    chunks.removeAll()
    byteCount = 0
  }
}

enum RealtimeSessionError: LocalizedError, Equatable {
  case preReadyAudioOverflow(providerName: String, maximumSeconds: Int)

  var errorDescription: String? {
    switch self {
    case .preReadyAudioOverflow(let providerName, let maximumSeconds):
      "\(providerName) did not become ready before \(maximumSeconds) seconds of audio accumulated. The realtime session was stopped."
    }
  }
}

final class XAIRealtimeTranscriptionSession: RealtimeTranscriptionSession, @unchecked Sendable {
  private let webSocket: URLSessionWebSocketTask
  private let accumulator: RealtimeTranscriptAccumulator
  private let sendQueue = DispatchQueue(label: "Vhrase.XAIRealtimeSend")
  private var isReady = false
  private var pendingAudio = PreReadyAudioQueue()
  private var finishRequested = false
  private var didSendAudioDone = false
  private var isTerminal = false

  init(
    request: URLRequest,
    onPartialTranscript: @escaping @Sendable (String) -> Void
  ) {
    accumulator = RealtimeTranscriptAccumulator(
      providerName: "xAI Realtime",
      onPartialTranscript: onPartialTranscript
    )
    webSocket = URLSession.shared.webSocketTask(with: request)
    webSocket.resume()
    Task { [weak self] in
      await self?.receiveLoop()
    }
  }

  func sendAudioChunk(_ data: Data) {
    guard !data.isEmpty else {
      return
    }

    sendQueue.async {
      guard !self.isTerminal, !self.finishRequested else {
        return
      }
      if self.isReady {
        self.sendLocked(.data(data))
      } else {
        do {
          try self.pendingAudio.append(data, providerName: "xAI Realtime")
        } catch {
          self.terminateLocked(error: error, closeCode: .goingAway)
        }
      }
    }
  }

  func finish() async throws -> TranscriptionResult {
    sendQueue.async {
      guard !self.isTerminal else {
        return
      }
      self.finishRequested = true
      if self.isReady {
        self.flushPendingLocked()
        self.sendAudioDoneLocked()
      }
    }
    do {
      let result = try await waitForRealtimeResult(accumulator)
      terminate(closeCode: .normalClosure)
      return result
    } catch {
      terminate(closeCode: .goingAway)
      throw error
    }
  }

  func cancel() {
    terminate(error: CancellationError(), closeCode: .goingAway)
  }

  private func receiveLoop() async {
    do {
      while !Task.isCancelled {
        let message = try await webSocket.receive()
        switch try await handle(message) {
        case .continueReceiving:
          continue
        case .completed:
          terminate(closeCode: .normalClosure)
          return
        case .failed:
          terminate(closeCode: .goingAway)
          return
        }
      }
    } catch {
      terminate(error: error, closeCode: .goingAway)
    }
  }

  private func handle(
    _ message: URLSessionWebSocketTask.Message
  ) async throws -> RealtimeEventOutcome {
    guard case .string(let text) = message else {
      return .continueReceiving
    }

    let event = try JSONDecoder().decode(XAIRealtimeEvent.self, from: Data(text.utf8))
    if event.type == "transcript.created" {
      markReady()
    }
    return await accumulator.handleXAI(event)
  }

  private func markReady() {
    sendQueue.async {
      guard !self.isTerminal, !self.isReady else {
        return
      }
      self.isReady = true
      self.flushPendingLocked()
      if self.finishRequested {
        self.sendAudioDoneLocked()
      }
    }
  }

  private func flushPendingLocked() {
    for chunk in pendingAudio.drain() {
      sendLocked(.data(chunk))
    }
  }

  private func sendAudioDoneLocked() {
    guard !didSendAudioDone else {
      return
    }
    didSendAudioDone = true
    sendLocked(.string(#"{"type":"audio.done"}"#))
  }

  private func sendLocked(_ message: URLSessionWebSocketTask.Message) {
    webSocket.send(message) { [weak self] error in
      if let error {
        self?.terminate(error: error, closeCode: .goingAway)
      }
    }
  }

  private func terminate(
    error: Error? = nil,
    closeCode: URLSessionWebSocketTask.CloseCode
  ) {
    sendQueue.async {
      self.terminateLocked(error: error, closeCode: closeCode)
    }
  }

  private func terminateLocked(
    error: Error?,
    closeCode: URLSessionWebSocketTask.CloseCode
  ) {
    guard !isTerminal else {
      return
    }
    isTerminal = true
    pendingAudio.removeAll()
    webSocket.cancel(with: closeCode, reason: nil)
    if let error {
      Task {
        await accumulator.fail(error)
      }
    }
  }
}

final class ElevenLabsRealtimeTranscriptionSession: RealtimeTranscriptionSession,
  @unchecked Sendable
{
  private let webSocket: URLSessionWebSocketTask
  private let accumulator: RealtimeTranscriptAccumulator
  private let sendQueue = DispatchQueue(label: "Vhrase.ElevenLabsRealtimeSend")
  private var isReady = false
  private var pendingAudio = PreReadyAudioQueue()
  private var finishRequested = false
  private var didSendFinalCommit = false
  private var isTerminal = false

  init(
    request: URLRequest,
    onPartialTranscript: @escaping @Sendable (String) -> Void
  ) {
    accumulator = RealtimeTranscriptAccumulator(
      providerName: "ElevenLabs Realtime",
      onPartialTranscript: onPartialTranscript
    )
    webSocket = URLSession.shared.webSocketTask(with: request)
    webSocket.resume()
    Task { [weak self] in
      await self?.receiveLoop()
    }
  }

  func sendAudioChunk(_ data: Data) {
    guard !data.isEmpty else {
      return
    }

    sendQueue.async {
      guard !self.isTerminal, !self.finishRequested else {
        return
      }
      if self.isReady {
        self.sendAudioLocked(data)
      } else {
        do {
          try self.pendingAudio.append(data, providerName: "ElevenLabs Realtime")
        } catch {
          self.terminateLocked(error: error, closeCode: .goingAway)
        }
      }
    }
  }

  func finish() async throws -> TranscriptionResult {
    sendQueue.async {
      guard !self.isTerminal else {
        return
      }
      self.finishRequested = true
      if self.isReady {
        self.flushPendingLocked()
        self.sendFinalCommitLocked()
      }
    }
    do {
      let result = try await waitForRealtimeResult(accumulator)
      terminate(closeCode: .normalClosure)
      return result
    } catch {
      terminate(closeCode: .goingAway)
      throw error
    }
  }

  func cancel() {
    terminate(error: CancellationError(), closeCode: .goingAway)
  }

  private func receiveLoop() async {
    do {
      while !Task.isCancelled {
        let message = try await webSocket.receive()
        switch try await handle(message) {
        case .continueReceiving:
          continue
        case .completed:
          terminate(closeCode: .normalClosure)
          return
        case .failed:
          terminate(closeCode: .goingAway)
          return
        }
      }
    } catch {
      terminate(error: error, closeCode: .goingAway)
    }
  }

  private func handle(
    _ message: URLSessionWebSocketTask.Message
  ) async throws -> RealtimeEventOutcome {
    guard case .string(let text) = message else {
      return .continueReceiving
    }

    let event = try JSONDecoder().decode(ElevenLabsRealtimeEvent.self, from: Data(text.utf8))
    if event.message_type == "session_started" {
      markReady()
    }
    return await accumulator.handleElevenLabs(event)
  }

  private func markReady() {
    sendQueue.async {
      guard !self.isTerminal, !self.isReady else {
        return
      }
      self.isReady = true
      self.flushPendingLocked()
      if self.finishRequested {
        self.sendFinalCommitLocked()
      }
    }
  }

  private func flushPendingLocked() {
    for chunk in pendingAudio.drain() {
      sendAudioLocked(chunk)
    }
  }

  private func sendAudioLocked(_ data: Data) {
    sendPayloadLocked(
      ElevenLabsInputAudioChunk(
        audio_base_64: data.base64EncodedString(),
        commit: false,
        sample_rate: 16_000
      ))
  }

  /// Marks the next committed transcript as the response to this session's explicit final commit.
  private func sendFinalCommitLocked() {
    guard !didSendFinalCommit else {
      return
    }
    didSendFinalCommit = true
    Task { [weak self] in
      guard let self else {
        return
      }
      await accumulator.beginElevenLabsFinishCommit()
      sendQueue.async {
        guard !self.isTerminal else {
          return
        }
        self.sendPayloadLocked(
          ElevenLabsInputAudioChunk(
            audio_base_64: "",
            commit: true,
            sample_rate: 16_000
          ))
      }
    }
  }

  private func sendPayloadLocked(_ payload: ElevenLabsInputAudioChunk) {
    do {
      let data = try JSONEncoder().encode(payload)
      let text = String(decoding: data, as: UTF8.self)
      webSocket.send(.string(text)) { [weak self] error in
        if let error {
          self?.terminate(error: error, closeCode: .goingAway)
        }
      }
    } catch {
      terminate(error: error, closeCode: .goingAway)
    }
  }

  private func terminate(
    error: Error? = nil,
    closeCode: URLSessionWebSocketTask.CloseCode
  ) {
    sendQueue.async {
      self.terminateLocked(error: error, closeCode: closeCode)
    }
  }

  private func terminateLocked(
    error: Error?,
    closeCode: URLSessionWebSocketTask.CloseCode
  ) {
    guard !isTerminal else {
      return
    }
    isTerminal = true
    pendingAudio.removeAll()
    webSocket.cancel(with: closeCode, reason: nil)
    if let error {
      Task {
        await accumulator.fail(error)
      }
    }
  }
}

enum RealtimeEventOutcome: Sendable {
  case continueReceiving
  case completed
  case failed
}

struct XAIRealtimeEvent: Decodable {
  let type: String
  let text: String?
  let is_final: Bool?
  let speech_final: Bool?
  let duration: Double?
  let message: String?
}

struct ElevenLabsRealtimeEvent: Decodable {
  static let errorMessageTypes: Set<String> = [
    "auth_error",
    "chunk_size_exceeded",
    "commit_throttled",
    "error",
    "input_error",
    "insufficient_audio_activity",
    "queue_overflow",
    "quota_exceeded",
    "rate_limited",
    "resource_exhausted",
    "session_time_limit_exceeded",
    "transcriber_error",
    "unaccepted_terms",
  ]

  let message_type: String
  let text: String?
  let error: String?

  var isError: Bool {
    Self.errorMessageTypes.contains(message_type)
  }

  init(
    message_type: String,
    text: String? = nil,
    error: String? = nil
  ) {
    self.message_type = message_type
    self.text = text
    self.error = error
  }
}

private struct ElevenLabsInputAudioChunk: Encodable {
  let message_type = "input_audio_chunk"
  let audio_base_64: String
  let commit: Bool
  let sample_rate: Int
}

private func realtimeMissingKey(_ name: String) -> NSError {
  NSError(
    domain: "Vhrase.Realtime",
    code: 1,
    userInfo: [
      NSLocalizedDescriptionKey:
        "\(name) is missing. Add it in Settings before using realtime transcription."
    ]
  )
}
