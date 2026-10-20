// Converts captured audio into enhanced mono PCM16 chunks shared by metering, WAV recording, and realtime transport.

@preconcurrency import AVFoundation
import Foundation

struct AudioChunk: Sendable {
  let data: Data
  let inputLevel: Double
  let level: Double
}

typealias AudioChunkHandler = @Sendable (AudioChunk) -> Void

/// Serializes resampling, enhancement updates, and final draining for one capture stream.
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
