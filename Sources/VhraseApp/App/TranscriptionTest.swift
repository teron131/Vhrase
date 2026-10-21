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
  private var recording: TranscriptionRecording?
  private var operation: Task<Void, Never>?
  private var countdown: Task<Void, Never>?

  func start(settings: DictationSettings, apiKey: String, client: SpeechToTextClient) {
    guard !state.isActive else { return }
    let recording = TranscriptionRecording(settings: settings, apiKey: apiKey, client: client)
    self.recording = recording
    partialTranscript = ""
    state = .starting
    operation = Task {
      do {
        try await recording.start(
          onPartialTranscript: { [weak self, weak recording] text in
            Task { @MainActor in
              guard let self, let recording, self.recording === recording else { return }
              self.partialTranscript = text
            }
          },
          onFailure: { [weak self, weak recording] error in
            guard let self, let recording, self.recording === recording else { return }
            self.fail(error)
          })
        try ensureCurrent(recording)
        operation = nil
        state = .recording(secondsRemaining: Self.recordingSeconds)
        countdown = Task {
          do {
            for remaining in (0..<Self.recordingSeconds).reversed() {
              try await Task.sleep(for: .seconds(1))
              try ensureCurrent(recording)
              if remaining == 0 {
                stopAndTranscribe()
              } else {
                state = .recording(secondsRemaining: remaining)
              }
            }
          } catch {}
        }
      } catch {
        guard self.recording === recording else { return }
        fail(error)
      }
    }
  }

  /// Ends capture early, or at five seconds when the countdown calls it, and publishes the recognized text in `state`.
  func stopAndTranscribe() {
    guard case .recording = state, let recording else { return }
    countdown?.cancel()
    countdown = nil
    state = .transcribing
    operation = Task {
      do {
        try await recording.stop()
        try ensureCurrent(recording)
        let text = try await recording.transcribe().text
        try ensureCurrent(recording)
        release()
        state =
          text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          ? .failed("No speech was recognized. Try another short phrase.") : .completed(text)
      } catch {
        guard self.recording === recording else { return }
        fail(error)
      }
    }
  }

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

  private func ensureCurrent(_ recording: TranscriptionRecording) throws {
    try Task.checkCancellation()
    guard self.recording === recording else { throw CancellationError() }
  }

  private func release() {
    operation?.cancel()
    operation = nil
    countdown?.cancel()
    countdown = nil
    recording?.cancel()
    recording = nil
    partialTranscript = ""
  }
}
