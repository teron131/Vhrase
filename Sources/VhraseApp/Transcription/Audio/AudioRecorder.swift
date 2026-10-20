// Captures microphone input without enabling playback processing and shares enhanced PCM between previews, WAV uploads, and realtime providers.

@preconcurrency import AVFoundation
import Foundation
import OSLog

@MainActor
final class AudioRecorder {
  private(set) var recordedSeconds = 0.0
  private let engine = AVAudioEngine()
  private var deviceCapture: DeviceAudioCapture?
  private var audioFile: AVAudioFile?
  private var outputURL: URL?
  private var tapProcessor: AudioTapProcessor?
  private var captureState: AudioCaptureState?
  private var healthTask: Task<Void, Never>?
  private var configurationObserver: NSObjectProtocol?
  private let logger = Logger(subsystem: "local.codex.Vhrase", category: "AudioRecorder")

  var isRecording: Bool {
    deviceCapture?.isRunning ?? engine.isRunning
  }

  /// Captures the system microphone and snapshots input-only enhancement settings for this recording.
  /// Failures after startup cancel capture before notifying the workflow through onFailure.
  func start(
    settings: DictationSettings = .defaults, onAudioChunk: AudioChunkHandler? = nil,
    onFailure: @escaping @MainActor (Error) -> Void
  )
    async throws
  {
    try await startCapture(
      settings: settings, savesAudio: true, onAudioChunk: onAudioChunk, onFailure: onFailure)
  }

  /// Runs the same processing path entirely in memory; no recording directory or audio file is created.
  func startPreview(
    settings: DictationSettings, onAudioChunk: @escaping AudioChunkHandler,
    onFailure: @escaping @MainActor (Error) -> Void
  )
    async throws
  {
    try await startCapture(
      settings: settings, savesAudio: false, onAudioChunk: onAudioChunk, onFailure: onFailure)
  }

  /// Reconfigures a preview without touching the input device or restarting its tap.
  func updatePreview(settings: DictationSettings) throws {
    try tapProcessor?.updateProcessing(settings: settings)
  }

  private func startCapture(
    settings: DictationSettings, savesAudio: Bool, onAudioChunk: AudioChunkHandler?,
    onFailure: @escaping @MainActor (Error) -> Void
  ) async throws {
    recordedSeconds = 0
    try Task.checkCancellation()
    let granted = await AVCaptureDevice.requestAccess(for: .audio)
    try Task.checkCancellation()
    guard granted else {
      throw NSError(
        domain: "Vhrase.Audio",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Microphone access was not granted."]
      )
    }

    let usesSelectedDevice = !settings.inputDeviceUID.isEmpty
    logger.notice("Start capture preview=\(!savesAudio) selectedDevice=\(usesSelectedDevice)")
    let deviceID = try AudioInputDevice.resolve(settings.inputDeviceUID)
    AudioInputDevice.logCaptureState(deviceID: deviceID)
    let format =
      usesSelectedDevice ? PCM16AudioConverter.format : engine.inputNode.outputFormat(forBus: 0)
    guard format.sampleRate > 0, format.channelCount > 0 else {
      throw AudioRecorderError.invalidInputFormat
    }
    logger.notice("Input format rate=\(format.sampleRate) channels=\(format.channelCount)")
    let preprocessor = try AudioPreprocessor(
      noiseReductionDB: settings.noiseReductionDB, gainDB: settings.inputGainDB,
      automaticVolumeLeveling: settings.automaticVolumeLeveling)
    let url = savesAudio ? try nextRecordingURL() : nil
    let file = try url.map {
      try AVAudioFile(
        forWriting: $0, settings: PCM16AudioConverter.format.settings,
        commonFormat: .pcmFormatInt16, interleaved: true)
    }
    let converter = PCM16AudioConverter(inputFormat: format, preprocessor: preprocessor)
    let captureState = AudioCaptureState()
    let tapProcessor = AudioTapProcessor(
      file: file,
      converter: converter,
      chunkHandler: onAudioChunk,
      captureState: captureState
    )

    do {
      if usesSelectedDevice {
        deviceCapture = try DeviceAudioCapture(
          uid: settings.inputDeviceUID,
          onBuffer: { tapProcessor.process($0) }, onError: { captureState.recordError($0) })
      } else {
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        input.installTap(
          onBus: 0,
          bufferSize: 4_096,
          format: format,
          block: Self.makeAudioTapBlock { buffer in
            tapProcessor.process(buffer)
          }
        )
      }

      audioFile = file
      outputURL = url
      self.tapProcessor = tapProcessor
      self.captureState = captureState
      if let deviceCapture {
        try await deviceCapture.start()
        guard deviceCapture.isRunning else {
          throw NSError(
            domain: "Vhrase.Audio", code: 4,
            userInfo: [
              NSLocalizedDescriptionKey:
                "The selected microphone could not start. Choose another input device."
            ])
        }
      } else {
        engine.prepare()
        try engine.start()
        configurationObserver = NotificationCenter.default.addObserver(
          forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { _ in
          captureState.recordError(AudioRecorderError.captureInterrupted)
        }
      }
      try Task.checkCancellation()
      logger.notice("Capture running")
      monitorCapture(captureState, onFailure: onFailure)
    } catch {
      let failure = error as NSError
      logger.error(
        "Capture startup failed domain=\(failure.domain, privacy: .public) code=\(failure.code)")
      stopInput()
      captureState.stopAndWait()
      audioFile = nil
      outputURL = nil
      self.tapProcessor = nil
      self.captureState = nil
      if let url { try? FileManager.default.removeItem(at: url) }
      throw error
    }
  }

  /// Detects lost delivery, including silent driver failures, using PCM arrival rather than microphone loudness.
  private func monitorCapture(
    _ state: AudioCaptureState, onFailure: @escaping @MainActor (Error) -> Void
  ) {
    state.beginMonitoring()
    healthTask = Task { [weak self] in
      while !Task.isCancelled {
        do { try await Task.sleep(for: .seconds(1)) } catch { return }
        guard let self else { return }
        guard let error = state.failure(at: ProcessInfo.processInfo.systemUptime) else { continue }
        let failure = error as NSError
        self.logger.error(
          "Capture unhealthy domain=\(failure.domain, privacy: .public) code=\(failure.code) chunks=\(state.chunkCount)"
        )
        self.cancel()
        onFailure(error)
        return
      }
    }
  }

  /// Creates a CoreAudio callback without inheriting the recorder's main-actor isolation.
  nonisolated static func makeAudioTapBlock(
    process: @escaping @Sendable (AVAudioPCMBuffer) -> Void
  ) -> AVAudioNodeTapBlock {
    { buffer, _ in
      process(buffer)
    }
  }

  /// Stops capture and drains conversion and denoising to both destinations before closing the recorded file.
  func stop() async throws -> URL {
    guard let outputURL else {
      throw AudioRecorderError.noActiveRecording
    }

    stopMonitoring()
    if let deviceCapture {
      do {
        try await deviceCapture.stop()
        self.deviceCapture = nil
      } catch {
        cancel()
        throw error
      }
    } else {
      stopInput()
    }
    captureState?.stopAndWait()
    tapProcessor?.finish()
    let recordedFrameCount = audioFile?.length ?? 0
    recordedSeconds = Double(recordedFrameCount) / PCM16AudioConverter.format.sampleRate
    let captureError = captureState?.firstError
    logger.notice(
      "Capture finished frames=\(recordedFrameCount) chunks=\(self.captureState?.chunkCount ?? 0)")
    audioFile = nil
    tapProcessor = nil
    captureState = nil
    self.outputURL = nil

    if let captureError {
      try? FileManager.default.removeItem(at: outputURL)
      throw AudioRecorderError.fileWriteFailed(captureError)
    }
    guard recordedFrameCount > 0 else {
      try? FileManager.default.removeItem(at: outputURL)
      throw AudioRecorderError.emptyRecording
    }
    return outputURL
  }

  /// Stops capture without producing a transcript and deletes the temporary recording.
  func cancel() {
    guard captureState != nil else { return }
    logger.notice("Capture cancelled chunks=\(self.captureState?.chunkCount ?? 0)")
    stopInput()
    captureState?.stopAndWait()
    audioFile = nil
    tapProcessor = nil
    captureState = nil
    if let outputURL {
      try? FileManager.default.removeItem(at: outputURL)
    }
    outputURL = nil
  }

  private func stopInput() {
    stopMonitoring()
    if let deviceCapture {
      deviceCapture.cancel()
      self.deviceCapture = nil
    } else if captureState != nil {
      engine.inputNode.removeTap(onBus: 0)
      engine.stop()
    }
  }

  private func stopMonitoring() {
    healthTask?.cancel()
    healthTask = nil
    if let configurationObserver {
      NotificationCenter.default.removeObserver(configurationObserver)
      self.configurationObserver = nil
    }
  }

  /// Best-effort removes recordings abandoned by a previous app lifetime without creating the directory.
  static func removeAbandonedRecordings() {
    guard let directory = try? recordingsDirectory(createIfNeeded: false),
      let files = try? FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
      )
    else {
      return
    }

    for file in files
    where file.pathExtension.lowercased() == "wav"
      && file.lastPathComponent.hasPrefix("recording-")
    {
      guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey]),
        values.isRegularFile == true
      else {
        continue
      }
      try? FileManager.default.removeItem(at: file)
    }
  }

  private func nextRecordingURL() throws -> URL {
    let directory = try Self.recordingsDirectory(createIfNeeded: true)

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let name = formatter.string(from: Date())
      .replacingOccurrences(of: ":", with: "-")
      .replacingOccurrences(of: ".", with: "-")

    return directory.appendingPathComponent("recording-\(name).wav")
  }

  private static func recordingsDirectory(createIfNeeded: Bool) throws -> URL {
    let base = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: createIfNeeded
    )
    let directory = base.appendingPathComponent("Vhrase/Recordings", isDirectory: true)
    if createIfNeeded {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    return directory
  }
}

enum AudioRecorderError: LocalizedError {
  case noActiveRecording
  case fileWriteFailed(Error)
  case emptyRecording
  case invalidInputFormat
  case startupTimedOut
  case shutdownTimedOut
  case captureInterrupted
  case audioDeliveryStopped

  var errorDescription: String? {
    switch self {
    case .noActiveRecording:
      "There is no active recording."
    case .fileWriteFailed(let error):
      "Vhrase could not save the recording: \(error.localizedDescription)"
    case .emptyRecording:
      "The recording contained no audio."
    case .invalidInputFormat:
      "The microphone has no usable input format. Check the device or choose another microphone."
    case .startupTimedOut:
      "The microphone did not start within \(DeviceAudioCapture.operationTimeoutSeconds) seconds. Another app or the audio device may be holding it. Try another microphone."
    case .shutdownTimedOut:
      "The microphone did not stop within \(DeviceAudioCapture.operationTimeoutSeconds) seconds. Check the audio device and other audio apps before trying again."
    case .captureInterrupted:
      "Microphone capture was interrupted or its format changed. Check other audio apps and try recording again."
    case .audioDeliveryStopped:
      "The microphone stopped delivering audio for \(AudioCaptureState.deliveryTimeoutSeconds) seconds. Check other audio apps or choose another microphone."
    }
  }
}

/// Serializes callback shutdown, the first capture error, and delivery health across audio and main queues.
final class AudioCaptureState: @unchecked Sendable {
  static let deliveryTimeoutSeconds = 5

  private let condition = NSCondition()
  private var activeCallbacks = 0
  private var isStopping = false
  private var error: Error?
  private var lastChunkTime: TimeInterval
  private var chunks = 0

  init(startedAt: TimeInterval = ProcessInfo.processInfo.systemUptime) {
    lastChunkTime = startedAt
  }

  var chunkCount: Int { condition.withLock { chunks } }

  /// Gives a newly started device its full delivery grace period without resetting audio that already arrived.
  func beginMonitoring() {
    condition.withLock {
      if chunks == 0 { lastChunkTime = ProcessInfo.processInfo.systemUptime }
    }
  }

  /// Returns `true` for the first chunk. Even zero-valued PCM counts as healthy delivery, so a quiet room cannot trigger the stall timeout.
  @discardableResult
  func recordChunk(at time: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
    condition.withLock {
      lastChunkTime = time
      chunks += 1
      return chunks == 1
    }
  }

  /// Reports the first capture error before considering a delivery stall, and suppresses failures after shutdown.
  func failure(at time: TimeInterval) -> Error? {
    condition.withLock {
      guard !isStopping else { return nil }
      return error
        ?? (time - lastChunkTime >= Double(Self.deliveryTimeoutSeconds)
          ? AudioRecorderError.audioDeliveryStopped : nil)
    }
  }

  var firstError: Error? {
    condition.withLock { error }
  }

  func beginCallback() -> Bool {
    condition.withLock {
      guard !isStopping else {
        return false
      }
      activeCallbacks += 1
      return true
    }
  }

  func endCallback() {
    condition.withLock {
      activeCallbacks -= 1
      if activeCallbacks == 0 {
        condition.broadcast()
      }
    }
  }

  /// Retains the original hardware or write failure when subsequent callbacks also fail.
  func recordError(_ error: Error) {
    condition.withLock {
      if self.error == nil {
        self.error = error
      }
    }
  }

  func stopAndWait() {
    condition.lock()
    isStopping = true
    while activeCallbacks > 0 {
      condition.wait()
    }
    condition.unlock()
  }
}

private final class AudioTapProcessor: @unchecked Sendable {
  private let logger = Logger(subsystem: "local.codex.Vhrase", category: "AudioRecorder")
  private let file: AVAudioFile?
  private let converter: PCM16AudioConverter
  private let chunkHandler: AudioChunkHandler?
  private let captureState: AudioCaptureState

  init(
    file: AVAudioFile?,
    converter: PCM16AudioConverter,
    chunkHandler: AudioChunkHandler?,
    captureState: AudioCaptureState
  ) {
    self.file = file
    self.converter = converter
    self.chunkHandler = chunkHandler
    self.captureState = captureState
  }

  func process(_ buffer: AVAudioPCMBuffer) {
    guard captureState.beginCallback() else {
      return
    }
    defer {
      captureState.endCallback()
    }
    for chunk in converter.convert(buffer) {
      writeAndSend(chunk)
    }
  }

  /// Runs after all tap callbacks complete so delayed speech reaches the WAV and realtime transport before finalization.
  func finish() {
    for chunk in converter.finish() { writeAndSend(chunk) }
  }

  func updateProcessing(settings: DictationSettings) throws {
    try converter.updateProcessing(settings: settings)
  }

  private func writeAndSend(_ chunk: AudioChunk) {
    if captureState.recordChunk() { logger.notice("First PCM chunk received") }
    defer { chunkHandler?(chunk) }
    guard let file else { return }
    do {
      let frameCount = AVAudioFrameCount(chunk.data.count / MemoryLayout<Int16>.size)
      guard
        let buffer = AVAudioPCMBuffer(
          pcmFormat: PCM16AudioConverter.format, frameCapacity: frameCount),
        let samples = buffer.int16ChannelData?[0]
      else { throw AudioRecorderError.emptyRecording }
      buffer.frameLength = frameCount
      chunk.data.copyBytes(
        to: UnsafeMutableRawBufferPointer(start: samples, count: chunk.data.count))
      try file.write(from: buffer)
    } catch {
      captureState.recordError(error)
      NSLog("Vhrase audio write failed: \(error.localizedDescription)")
    }
  }
}
