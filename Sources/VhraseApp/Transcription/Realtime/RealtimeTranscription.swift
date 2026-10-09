// Streams captured PCM over one provider WebSocket, sharing ready gating, finish sequencing, and teardown across providers.

import Foundation

/// Owns one realtime WebSocket: buffers audio until the provider is ready, sends the provider's finishing message once, and resolves one transcript.
final class RealtimeTranscriptionSession: @unchecked Sendable {
  /// Providers with a realtime transport; each differs only in its ready event, audio framing, and finish handshake.
  enum Provider {
    case xai
    case elevenLabs

    var name: String {
      switch self {
      case .xai: "xAI Realtime"
      case .elevenLabs: "ElevenLabs Realtime"
      }
    }
  }

  private let provider: Provider
  private let webSocket: URLSessionWebSocketTask
  private let accumulator: RealtimeTranscriptAccumulator
  private let sendQueue = DispatchQueue(label: "Vhrase.RealtimeSend")
  private var isReady = false
  private var pendingAudio = PreReadyAudioQueue()
  private var finishRequested = false
  private var didSendFinish = false
  private var isTerminal = false

  /// Opens the selected provider's WebSocket with validated query parameters; Gemini and Parakeet have no realtime transport.
  static func start(
    settings: DictationSettings,
    apiKey: String,
    onPartialTranscript: @escaping @Sendable (String) -> Void
  ) throws -> RealtimeTranscriptionSession {
    var request: URLRequest
    let provider: Provider
    switch settings.provider {
    case .xai:
      guard !apiKey.isEmpty else {
        throw missingKey("XAI_API_KEY")
      }
      var components = URLComponents(string: "wss://api.x.ai/v1/stt")!
      components.queryItems = try XAITranscriptionContract.realtimeQueryItems(settings: settings)
      request = URLRequest(url: components.url!)
      request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
      provider = .xai
    case .elevenLabs:
      guard !apiKey.isEmpty else {
        throw missingKey("ELEVENLABS_API_KEY")
      }
      var components = URLComponents(string: "wss://api.elevenlabs.io/v1/speech-to-text/realtime")!
      components.queryItems = try ElevenLabsTranscriptionContract.realtimeQueryItems(
        settings: settings)
      request = URLRequest(url: components.url!)
      request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
      provider = .elevenLabs
    case .gemini, .parakeet:
      throw NSError(
        domain: "Vhrase.STT", code: 2,
        userInfo: [
          NSLocalizedDescriptionKey:
            "Choose \(TranscriptionMode.upload.title(for: settings.provider)) for \(settings.provider.title) transcription."
        ])
    }
    return RealtimeTranscriptionSession(
      provider: provider,
      request: request,
      onPartialTranscript: onPartialTranscript
    )
  }

  init(
    provider: Provider,
    request: URLRequest,
    onPartialTranscript: @escaping @Sendable (String) -> Void
  ) {
    self.provider = provider
    accumulator = RealtimeTranscriptAccumulator(
      providerName: provider.name,
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
          try self.pendingAudio.append(data, providerName: self.provider.name)
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
        self.sendFinishLocked()
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

  /// Releases buffered audio on the provider's ready event before the accumulator consumes that event.
  private func handle(
    _ message: URLSessionWebSocketTask.Message
  ) async throws -> RealtimeEventOutcome {
    guard case .string(let text) = message else {
      return .continueReceiving
    }

    let data = Data(text.utf8)
    switch provider {
    case .xai:
      let event = try JSONDecoder().decode(XAIRealtimeEvent.self, from: data)
      if event.type == "transcript.created" {
        markReady()
      }
      return await accumulator.handleXAI(event)
    case .elevenLabs:
      let event = try JSONDecoder().decode(ElevenLabsRealtimeEvent.self, from: data)
      if event.messageType == "session_started" {
        markReady()
      }
      return await accumulator.handleElevenLabs(event)
    }
  }

  private func markReady() {
    sendQueue.async {
      guard !self.isTerminal, !self.isReady else {
        return
      }
      self.isReady = true
      self.flushPendingLocked()
      if self.finishRequested {
        self.sendFinishLocked()
      }
    }
  }

  private func flushPendingLocked() {
    for chunk in pendingAudio.drain() {
      sendAudioLocked(chunk)
    }
  }

  private func sendAudioLocked(_ data: Data) {
    switch provider {
    case .xai:
      sendLocked(.data(data))
    case .elevenLabs:
      sendElevenLabsChunkLocked(audio: data.base64EncodedString(), commit: false)
    }
  }

  /// Sends the end-of-audio message once; ElevenLabs first marks the next commit as this session's final response.
  private func sendFinishLocked() {
    guard !didSendFinish else {
      return
    }
    didSendFinish = true
    switch provider {
    case .xai:
      sendLocked(.string(#"{"type":"audio.done"}"#))
    case .elevenLabs:
      Task { [weak self] in
        guard let self else {
          return
        }
        await accumulator.beginElevenLabsFinishCommit()
        sendQueue.async {
          guard !self.isTerminal else {
            return
          }
          self.sendElevenLabsChunkLocked(audio: "", commit: true)
        }
      }
    }
  }

  private func sendElevenLabsChunkLocked(audio: String, commit: Bool) {
    do {
      let data = try JSONEncoder().encode(
        ElevenLabsInputAudioChunk(
          audioBase64: audio,
          commit: commit,
          sampleRate: 16_000
        ))
      sendLocked(.string(String(decoding: data, as: UTF8.self)))
    } catch {
      terminate(error: error, closeCode: .goingAway)
    }
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

  private static func missingKey(_ name: String) -> NSError {
    NSError(
      domain: "Vhrase.Realtime",
      code: 1,
      userInfo: [
        NSLocalizedDescriptionKey:
          "\(name) is missing. Add it in Settings before using realtime transcription."
      ]
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

enum RealtimeEventOutcome: Sendable {
  case continueReceiving
  case completed
  case failed
}

struct XAIRealtimeEvent: Decodable {
  let type: String
  let text: String?
  let isFinal: Bool?
  let speechFinal: Bool?
  let message: String?

  private enum CodingKeys: String, CodingKey {
    case type
    case text
    case isFinal = "is_final"
    case speechFinal = "speech_final"
    case message
  }
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

  let messageType: String
  let text: String?
  let error: String?

  private enum CodingKeys: String, CodingKey {
    case messageType = "message_type"
    case text
    case error
  }

  var isError: Bool {
    Self.errorMessageTypes.contains(messageType)
  }

  init(
    messageType: String,
    text: String? = nil,
    error: String? = nil
  ) {
    self.messageType = messageType
    self.text = text
    self.error = error
  }
}

private struct ElevenLabsInputAudioChunk: Encodable {
  let messageType = "input_audio_chunk"
  let audioBase64: String
  let commit: Bool
  let sampleRate: Int

  private enum CodingKeys: String, CodingKey {
    case messageType = "message_type"
    case audioBase64 = "audio_base_64"
    case commit
    case sampleRate = "sample_rate"
  }
}
