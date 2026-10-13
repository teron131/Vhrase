// Owns a bounded setup recording and its raw transcript without delivery, adjustment, history, or activity effects.

import Combine
import Foundation

@MainActor
final class TranscriptionTest: ObservableObject {
  private static let recordingSeconds = 5

  enum State: Equatable {
    case idle
    case starting
    case recording(secondsRemaining: Int)
    case transcribing
    case completed(String)
    case failed(String)

    var isActive: Bool {
      switch self {
      case .starting, .recording, .transcribing: true
      case .idle, .completed, .failed: false
      }
    }
  }

  @Published private(set) var state: State = .idle
  @Published private(set) var partialTranscript = ""
  private var id: UUID?
  private var recorder: AudioRecorder?
  private var session: RealtimeTranscriptionSession?
  private var operation: Task<Void, Never>?
  private var countdown: Task<Void, Never>?
  private var audioURL: URL?
  private var settings: DictationSettings?
  private var client: SpeechToTextClient?
  private var speechPresence: SpeechPresenceGate?

  /// Snapshots recognition configuration for one test; realtime uses the same provider transport as dictation.
  func start(settings: DictationSettings, apiKey: String, client: SpeechToTextClient) {
    guard !state.isActive else { return }
    let id = UUID()
    let recorder = AudioRecorder()
    let speechPresence = SpeechPresenceGate()
    self.id = id
    self.recorder = recorder
    self.settings = settings
    self.client = client
    self.speechPresence = speechPresence
    partialTranscript = ""
    state = .starting
    operation = Task {
      do {
        try ensureCurrent(id)
        let session =
          try settings.transcriptionMode == .realtime
          ? RealtimeTranscriptionSession.start(settings: settings, apiKey: apiKey) {
            [weak self] text in
            Task { @MainActor in
              guard let self, self.id == id else { return }
              self.partialTranscript = text
            }
          } : nil
        self.session = session
        try await recorder.start(settings: settings) { chunk in
          speechPresence.observe(level: chunk.level)
          session?.sendAudioChunk(chunk.data)
        } onFailure: { [weak self] error in
          guard let self, self.id == id else { return }
          self.fail(error)
        }
        try ensureCurrent(id)
        operation = nil
        state = .recording(secondsRemaining: Self.recordingSeconds)
        countdown = Task {
          do {
            for remaining in (0..<Self.recordingSeconds).reversed() {
              try await Task.sleep(for: .seconds(1))
              try ensureCurrent(id)
              if remaining == 0 {
                stopAndTranscribe()
              } else {
                state = .recording(secondsRemaining: remaining)
              }
            }
          } catch {}
        }
      } catch {
        recorder.cancel()
        guard self.id == id else { return }
        fail(error)
      }
    }
  }

  /// Ends capture early or at five seconds, then returns only the provider's recognized text.
  func stopAndTranscribe() {
    guard case .recording = state, let id, let recorder, let settings, let client else { return }
    countdown?.cancel()
    countdown = nil
    state = .transcribing
    let session = session
    operation = Task {
      do {
        try ensureCurrent(id)
        let url = try await recorder.stop()
        defer { try? FileManager.default.removeItem(at: url) }
        try ensureCurrent(id)
        audioURL = url
        self.recorder = nil
        guard speechPresence?.hasLikelySpeech == true else {
          throw RecordingContentError.noSpeechDetected
        }
        let result: TranscriptionResult
        if let session {
          result = try await session.finish()
        } else {
          result = try await client.transcribe(fileURL: url, settings: settings)
        }
        try ensureCurrent(id)
        let text = result.text
        release()
        state =
          text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          ? .failed("No speech was recognized. Try another short phrase.") : .completed(text)
      } catch {
        session?.cancel()
        recorder.cancel()
        guard self.id == id else { return }
        fail(error)
      }
    }
  }

  /// Invalidates continuations before releasing capture, transport, and temporary audio.
  func cancel() {
    guard state.isActive else { return }
    release()
    state = .idle
  }

  func reportFailure(_ error: Error) {
    guard !state.isActive else { return }
    state = .failed(error.localizedDescription)
  }

  private func fail(_ error: Error) {
    release()
    state = .failed(error.localizedDescription)
  }

  private func ensureCurrent(_ id: UUID) throws {
    try Task.checkCancellation()
    guard self.id == id else { throw CancellationError() }
  }

  private func release() {
    id = nil
    operation?.cancel()
    operation = nil
    countdown?.cancel()
    countdown = nil
    recorder?.cancel()
    recorder = nil
    session?.cancel()
    session = nil
    if let audioURL { try? FileManager.default.removeItem(at: audioURL) }
    audioURL = nil
    settings = nil
    client = nil
    speechPresence = nil
    partialTranscript = ""
  }
}
