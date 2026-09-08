// Captures microphone input without enabling playback processing and shares enhanced PCM between previews, WAV uploads, and realtime providers.

@preconcurrency import AVFoundation
import Foundation

struct AudioChunk: Sendable {
  let data: Data
  let inputLevel: Double
  let level: Double
}

typealias AudioChunkHandler = @Sendable (AudioChunk) -> Void

/// Records microphone audio while keeping CoreAudio tap work off the main actor.
@MainActor
final class AudioRecorder {
  private let engine = AVAudioEngine()
  private var deviceCapture: DeviceAudioCapture?
  private var audioFile: AVAudioFile?
  private var outputURL: URL?
  private var tapProcessor: AudioTapProcessor?
  private var captureState: AudioCaptureState?

  var isRecording: Bool {
    deviceCapture?.isRunning ?? engine.isRunning
  }

  /// Captures the system microphone and snapshots input-only enhancement settings for this recording.
  func start(settings: DictationSettings = .defaults, onAudioChunk: AudioChunkHandler? = nil)
    async throws
  {
    try await startCapture(settings: settings, savesAudio: true, onAudioChunk: onAudioChunk)
  }

  /// Runs the same processing path entirely in memory; no recording directory or audio file is created.
  func startPreview(settings: DictationSettings, onAudioChunk: @escaping AudioChunkHandler)
    async throws
  {
    try await startCapture(settings: settings, savesAudio: false, onAudioChunk: onAudioChunk)
  }

  /// Reconfigures a preview without touching the input device or restarting its tap.
  func updatePreview(settings: DictationSettings) throws {
    try tapProcessor?.updateProcessing(settings: settings)
  }

  private func startCapture(
    settings: DictationSettings, savesAudio: Bool, onAudioChunk: AudioChunkHandler?
  ) async throws {
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
    _ = try AudioInputDevice.resolve(settings.inputDeviceUID)
    let format =
      usesSelectedDevice ? PCM16AudioConverter.format : engine.inputNode.outputFormat(forBus: 0)
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
          onBuffer: { tapProcessor.process($0) }, onError: { captureState.recordWriteError($0) })
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
        await deviceCapture.start()
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
      }
      try Task.checkCancellation()
    } catch {
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

  /// Creates a CoreAudio callback without inheriting the recorder's main-actor isolation.
  nonisolated static func makeAudioTapBlock(
    process: @escaping @Sendable (AVAudioPCMBuffer) -> Void
  ) -> AVAudioNodeTapBlock {
    { buffer, _ in
      process(buffer)
    }
  }

  /// Stops capture and drains conversion and denoising to both destinations before closing the recorded file.
  func stop() throws -> URL {
    guard let outputURL else {
      throw AudioRecorderError.noActiveRecording
    }

    stopInput()
    captureState?.stopAndWait()
    tapProcessor?.finish()
    let recordedFrameCount = audioFile?.length ?? 0
    let writeError = captureState?.firstWriteError
    audioFile = nil
    tapProcessor = nil
    captureState = nil
    self.outputURL = nil

    if let writeError {
      try? FileManager.default.removeItem(at: outputURL)
      throw AudioRecorderError.fileWriteFailed(writeError)
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

  /// Stops the active input backend before pending processing is drained or discarded.
  private func stopInput() {
    if let deviceCapture {
      deviceCapture.stop()
      self.deviceCapture = nil
    } else if captureState != nil {
      engine.inputNode.removeTap(onBus: 0)
      engine.stop()
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

  var errorDescription: String? {
    switch self {
    case .noActiveRecording:
      "There is no active recording."
    case .fileWriteFailed(let error):
      "Vhrase could not save the recording: \(error.localizedDescription)"
    case .emptyRecording:
      "The recording contained no audio."
    }
  }
}

private final class AudioCaptureState: @unchecked Sendable {
  private let condition = NSCondition()
  private var activeCallbacks = 0
  private var isStopping = false
  private var writeError: Error?

  var firstWriteError: Error? {
    condition.withLock { writeError }
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

  func recordWriteError(_ error: Error) {
    condition.withLock {
      if writeError == nil {
        writeError = error
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

/// Shares PCM processing and optional file writing across engine taps and explicit-device capture callbacks.
private final class AudioTapProcessor: @unchecked Sendable {
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
      captureState.recordWriteError(error)
      NSLog("Vhrase audio write failed: \(error.localizedDescription)")
    }
  }
}

final class PCM16AudioConverter: @unchecked Sendable {
  static let format = AVAudioFormat(
    commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!
  private let converter: AVAudioConverter?
  private let outputFormat = PCM16AudioConverter.format
  private let lock = NSLock()
  private var chunkFramer = PCM16ChunkFramer()
  private var preprocessor: AudioPreprocessor?
  private var receivedAudio = false
  private var isFinished = false

  init(inputFormat: AVAudioFormat, preprocessor: AudioPreprocessor? = nil) {
    self.preprocessor = preprocessor
    converter = AVAudioConverter(from: inputFormat, to: Self.format)
  }

  /// Serializes control changes with processing so a slider updates the next audio chunk safely.
  func updateProcessing(settings: DictationSettings) throws {
    try lock.withLock {
      if let preprocessor {
        try preprocessor.update(
          noiseReductionDB: settings.noiseReductionDB, gainDB: settings.inputGainDB,
          automaticVolumeLeveling: settings.automaticVolumeLeveling)
      } else {
        preprocessor = try AudioPreprocessor(
          noiseReductionDB: settings.noiseReductionDB, gainDB: settings.inputGainDB,
          automaticVolumeLeveling: settings.automaticVolumeLeveling)
      }
    }
  }

  /// Converts one tap buffer and emits only complete 100 ms PCM16 frames.
  func convert(_ buffer: AVAudioPCMBuffer) -> [AudioChunk] {
    lock.withLock {
      guard !isFinished else { return [] }
      guard let converter else {
        return []
      }

      let ratio = outputFormat.sampleRate / buffer.format.sampleRate
      let outputCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 512
      guard
        let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputCapacity)
      else {
        return []
      }

      var error: NSError?
      let inputProvider = ConverterInputProvider(buffer: buffer)
      let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
        inputProvider.next(outStatus)
      }

      guard error == nil, status != .error, outputBuffer.frameLength > 0,
        let channelData = outputBuffer.int16ChannelData
      else {
        return []
      }

      let data = Data(
        bytes: channelData[0],
        count: Int(outputBuffer.frameLength) * MemoryLayout<Int16>.size
      )
      receivedAudio = true
      return chunkFramer.append(data).map(audioChunk)
    }
  }

  /// Drains conversion, pads a partial transport chunk, and preserves the denoiser's delayed speech tail.
  func finish() -> [AudioChunk] {
    lock.withLock {
      guard !isFinished else { return [] }
      isFinished = true
      var chunks: [Data] = []
      if let converter,
        let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 3_200)
      {
        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { _, inputStatus in
          inputStatus.pointee = .endOfStream
          return nil
        }
        if error == nil, status != .error, outputBuffer.frameLength > 0,
          let channelData = outputBuffer.int16ChannelData
        {
          let data = Data(
            bytes: channelData[0],
            count: Int(outputBuffer.frameLength) * MemoryLayout<Int16>.size
          )
          chunks += chunkFramer.append(data)
        }
      }
      if let finalChunk = chunkFramer.finish() {
        chunks.append(finalChunk)
      }
      // Speex uses overlap-add; one extra silent chunk preserves its delayed final speech samples.
      if receivedAudio, preprocessor?.needsDrain == true {
        chunks.append(Data(repeating: 0, count: PCM16ChunkFramer.chunkByteCount))
      }
      return chunks.map(audioChunk)
    }
  }

  private func audioChunk(data: Data) -> AudioChunk {
    let processed = preprocessor?.process(data) ?? data
    return AudioChunk(
      data: processed, inputLevel: Self.level(from: data), level: Self.level(from: processed))
  }

  private static func level(from data: Data) -> Double {
    guard data.count >= MemoryLayout<Int16>.size else {
      return 0
    }

    let sum = data.withUnsafeBytes { bytes -> Double in
      var sum: Double = 0
      for offset in stride(from: 0, to: data.count, by: MemoryLayout<Int16>.size) {
        let sample = bytes.loadUnaligned(fromByteOffset: offset, as: Int16.self).littleEndian
        let normalized = Double(sample) / Double(Int16.max)
        sum += normalized * normalized
      }
      return sum
    }

    let sampleCount = data.count / MemoryLayout<Int16>.size
    let rms = sqrt(sum / Double(sampleCount))
    return min(1, max(0, rms * 6))
  }
}

/// Buffers mono PCM16 into the 3,200-byte frames shared by WAV writing and realtime providers.
struct PCM16ChunkFramer {
  static let chunkByteCount = 3_200

  private var remainder = Data()

  var remainderByteCount: Int {
    remainder.count
  }

  mutating func append(_ data: Data) -> [Data] {
    guard !data.isEmpty else {
      return []
    }
    remainder.append(data)

    var chunks: [Data] = []
    while remainder.count >= Self.chunkByteCount {
      chunks.append(Data(remainder.prefix(Self.chunkByteCount)))
      remainder.removeFirst(Self.chunkByteCount)
    }
    return chunks
  }

  mutating func finish() -> Data? {
    guard !remainder.isEmpty else {
      return nil
    }

    var finalChunk = remainder
    remainder.removeAll()
    finalChunk.append(
      Data(
        repeating: 0,
        count: Self.chunkByteCount - finalChunk.count
      ))
    return finalChunk
  }
}

private final class ConverterInputProvider: @unchecked Sendable {
  private var buffer: AVAudioPCMBuffer?

  init(buffer: AVAudioPCMBuffer) {
    self.buffer = buffer
  }

  func next(_ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
    guard let buffer else {
      status.pointee = .noDataNow
      return nil
    }

    self.buffer = nil
    status.pointee = .haveData
    return buffer
  }
}
