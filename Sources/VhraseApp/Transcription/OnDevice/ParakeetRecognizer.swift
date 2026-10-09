// Runs Parakeet recognition on this Mac behind the transcript contract shared with the cloud providers, loading the model on demand and releasing it after a quiet period.

import FluidAudio
import Foundation
import OSLog

/// Serializes model loading and inference; loading reads only local files and never starts a download.
actor ParakeetRecognizer: SpeechToTextClient {
  /// Keeps roughly a working session warm without holding the model's memory in an idle menu-bar app.
  private static let idleUnloadDelay = Duration.seconds(300)

  private let directory: URL
  private var manager: AsrManager?
  private var loading: Task<AsrManager, Error>?
  private var idleUnloadTask: Task<Void, Never>?
  private let logger = Logger(subsystem: "local.codex.Vhrase", category: "Parakeet")

  init(directory: URL) {
    self.directory = directory
  }

  /// Loads the model ahead of transcription, typically while the user is still speaking.
  func load() async throws {
    _ = try await loadedManager()
    scheduleIdleUnload()
  }

  /// Transcribes a finished recording; Parakeet has no per-request settings, and cancellation stops at FluidAudio's next chunk boundary without returning text.
  func transcribe(fileURL: URL, settings: DictationSettings) async throws -> TranscriptionResult {
    let manager = try await loadedManager()
    idleUnloadTask?.cancel()
    defer { scheduleIdleUnload() }
    try Task.checkCancellation()
    var decoderState = TdtDecoderState.make()
    let result: ASRResult
    do {
      result = try await manager.transcribe(fileURL, decoderState: &decoderState)
    } catch {
      // FluidAudio may wrap the interruption in its own error; callers see one cancellation outcome.
      if Task.isCancelled { throw CancellationError() }
      throw error
    }
    try Task.checkCancellation()
    logger.notice(
      "Transcribed audioSeconds=\(result.duration, format: .fixed(precision: 1)) seconds=\(result.processingTime, format: .fixed(precision: 2))"
    )
    return TranscriptionResult(
      text: result.text.trimmingCharacters(in: .whitespacesAndNewlines),
      providerName: STTProvider.parakeet.title
    )
  }

  /// Releases the loaded model, for example before its files are removed.
  func unload() async {
    idleUnloadTask?.cancel()
    idleUnloadTask = nil
    await manager?.cleanup()
    manager = nil
  }

  /// Shares one in-flight load between warm-up and transcription so the model is never loaded twice.
  private func loadedManager() async throws -> AsrManager {
    if let manager {
      return manager
    }
    if let loading {
      return try await loading.value
    }
    let directory = directory
    let logger = logger
    let task = Task.detached(priority: .userInitiated) { () throws -> AsrManager in
      let started = ContinuousClock.now
      let models = try AsrModels.loadLocal(from: directory, version: .v3)
      let manager = AsrManager(config: .default)
      try await manager.loadModels(models)
      let seconds = started.duration(to: .now) / .seconds(1)
      logger.notice("Model loaded seconds=\(seconds, format: .fixed(precision: 2))")
      return manager
    }
    loading = task
    defer { loading = nil }
    let manager = try await task.value
    self.manager = manager
    return manager
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
