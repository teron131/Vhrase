// Applies model-free noise suppression and volume leveling only to microphone samples, without accessing playback devices.

import Foundation
import speex

/// Owns one recording's denoiser state; callers serialize access through the PCM converter.
final class AudioPreprocessor {
  private var state: OpaquePointer?
  private var gain = 1.0
  private static let frameSamples = 320

  init(noiseReductionDB: Double, gainDB: Double, automaticVolumeLeveling: Bool = false) throws {
    try update(
      noiseReductionDB: noiseReductionDB, gainDB: gainDB,
      automaticVolumeLeveling: automaticVolumeLeveling)
  }

  /// Reconfigures under the converter lock without restarting capture or discarding learned noise.
  func update(noiseReductionDB: Double, gainDB: Double, automaticVolumeLeveling: Bool) throws {
    gain = pow(10, gainDB / 20)
    guard noiseReductionDB > 0 || automaticVolumeLeveling else {
      if let state { speex_preprocess_state_destroy(state) }
      state = nil
      return
    }
    if state == nil { state = speex_preprocess_state_init(Int32(Self.frameSamples), 16_000) }
    guard let state else {
      throw AudioPreprocessorError.initializationFailed
    }
    var denoise: Int32 = noiseReductionDB > 0 ? 1 : 0
    var leveling: Int32 = automaticVolumeLeveling ? 1 : 0
    var suppression = -Int32(noiseReductionDB)
    speex_preprocess_ctl(state, SPEEX_PREPROCESS_SET_DENOISE, &denoise)
    speex_preprocess_ctl(state, SPEEX_PREPROCESS_SET_NOISE_SUPPRESS, &suppression)
    speex_preprocess_ctl(state, SPEEX_PREPROCESS_SET_AGC, &leveling)
    // Keep automatic boosts modest and gradual; manual trim is applied afterward.
    var maximumGain: Int32 = 6
    var increase: Int32 = 3
    var decrease: Int32 = -12
    speex_preprocess_ctl(state, SPEEX_PREPROCESS_SET_AGC_MAX_GAIN, &maximumGain)
    speex_preprocess_ctl(state, SPEEX_PREPROCESS_SET_AGC_INCREMENT, &increase)
    speex_preprocess_ctl(state, SPEEX_PREPROCESS_SET_AGC_DECREMENT, &decrease)
  }

  deinit {
    if let state { speex_preprocess_state_destroy(state) }
  }

  var needsDrain: Bool { state != nil }

  /// Processes complete 100 ms PCM16 chunks in 20 ms denoising frames without dropping quiet audio.
  func process(_ data: Data) -> Data {
    precondition(data.count == PCM16ChunkFramer.chunkByteCount)
    if state == nil, gain == 1 { return data }
    var samples = data.withUnsafeBytes { bytes in
      stride(from: 0, to: data.count, by: 2).map {
        bytes.loadUnaligned(fromByteOffset: $0, as: Int16.self).littleEndian
      }
    }
    if let state {
      samples.withUnsafeMutableBufferPointer { buffer in
        for offset in stride(from: 0, to: buffer.count, by: Self.frameSamples) {
          speex_preprocess_run(state, buffer.baseAddress! + offset)
        }
      }
    }
    for index in samples.indices {
      let adjusted = Double(samples[index]) * gain
      samples[index] = Int16(min(Double(Int16.max), max(Double(Int16.min), adjusted))).littleEndian
    }
    return samples.withUnsafeBytes { Data($0) }
  }
}

private enum AudioPreprocessorError: LocalizedError {
  case initializationFailed

  var errorDescription: String? { "Could not initialize local audio processing." }
}
