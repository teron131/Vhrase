// Owns one microphone recording from startup to recognized text, so dictation and the setup test share capture, the silence check, the provider transport, and temporary-audio cleanup.

import Foundation

/// Realtime modes stream audio to an open provider session while capturing; after-stop modes hand the finished audio file to the client. A step that fails releases the microphone, the session, and the temporary audio before throwing, so callers only decide what to show.
@MainActor
final class TranscriptionRecording {
  private let settings: DictationSettings
  private let apiKey: String
  private let client: any SpeechToTextClient
  private let recorder = AudioRecorder()
  private let speechPresence = SpeechPresenceGate()
  private var session: RealtimeTranscriptionSession?
  private var audioURL: URL?
  private var isCancelled = false

  init(settings: DictationSettings, apiKey: String, client: any SpeechToTextClient) {
    self.settings = settings
    self.apiKey = apiKey
    self.client = client
  }

  /// Seconds of captured audio, known once `stop` returns.
  var recordedSeconds: Double {
    recorder.recordedSeconds
  }

  /// `onLevel` receives each 100 ms chunk's processed level on the audio thread. `onFailure` reports capture that broke after startup, once the recording has released its resources.
  func start(
    onLevel: (@Sendable (Double) -> Void)? = nil,
    onPartialTranscript: @escaping @Sendable (String) -> Void,
    onFailure: @escaping @MainActor (Error) -> Void
  ) async throws {
    do {
      // A recording cancelled before its startup ran must not open a paid realtime session.
      try ensureActive()
      let session =
        settings.transcriptionMode == .realtime
        ? try RealtimeTranscriptionSession.start(
          settings: settings, apiKey: apiKey, onPartialTranscript: onPartialTranscript)
        : nil
      self.session = session
      let speechPresence = speechPresence
      try await recorder.start(settings: settings) { chunk in
        speechPresence.observe(level: chunk.level)
        session?.sendAudioChunk(chunk.data)
        onLevel?(chunk.level)
      } onFailure: { [weak self] error in
        self?.cancel()
        onFailure(error)
      }
      try ensureActive()
    } catch {
      cancel()
      throw error
    }
  }

  /// Stops the microphone and drains its audio, refusing a recording in which nothing audible was heard so silence is never sent for recognition.
  func stop() async throws {
    do {
      try ensureActive()
      audioURL = try await recorder.stop()
      try ensureActive()
      guard speechPresence.hasLikelySpeech else {
        throw RecordingContentError.noSpeechDetected
      }
    } catch {
      cancel()
      throw error
    }
  }

  /// Returns the provider's transcript of the stopped recording and deletes its audio.
  func transcribe() async throws -> TranscriptionResult {
    do {
      try ensureActive()
      guard let audioURL else {
        throw RecordingContentError.notStopped
      }
      let result: TranscriptionResult
      if let session {
        result = try await session.finish()
      } else {
        result = try await client.transcribe(fileURL: audioURL, settings: settings)
      }
      // A provider that ignores cancellation must not deliver its late transcript.
      try ensureActive()
      session = nil
      removeAudio()
      return result
    } catch {
      cancel()
      throw error
    }
  }

  /// Releases the microphone, the realtime session, and the temporary audio at once; a step still in flight throws `CancellationError` when it returns.
  func cancel() {
    isCancelled = true
    session?.cancel()
    session = nil
    recorder.cancel()
    removeAudio()
  }

  private func ensureActive() throws {
    try Task.checkCancellation()
    guard !isCancelled else {
      throw CancellationError()
    }
  }

  private func removeAudio() {
    guard let audioURL else { return }
    try? FileManager.default.removeItem(at: audioURL)
    self.audioURL = nil
  }
}

/// Accepts very quiet speech while rejecting recordings that never rise above the live waveform's noise floor.
private final class SpeechPresenceGate: @unchecked Sendable {
  private static let minimumLevel = 0.012
  private static let requiredChunks = 2

  private let lock = NSLock()
  private var audibleChunkCount = 0

  func observe(level: Double) {
    guard level > Self.minimumLevel else { return }
    lock.withLock {
      audibleChunkCount += 1
    }
  }

  var hasLikelySpeech: Bool {
    lock.withLock {
      audibleChunkCount >= Self.requiredChunks
    }
  }
}

private enum RecordingContentError: LocalizedError {
  case noSpeechDetected
  case notStopped

  var errorDescription: String? {
    switch self {
    case .noSpeechDetected: "No speech was detected."
    case .notStopped: "The recording has not finished, so there is nothing to transcribe."
    }
  }
}
