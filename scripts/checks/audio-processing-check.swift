// Exercises actual PCM enhancement for gain safety, noise attenuation, quiet speech, and end-of-recording drainage.

@preconcurrency import AVFoundation
import Foundation

@main
struct AudioProcessingCheck {
  static func main() throws {
    try verifyGain()
    try verifyAutomaticLeveling()
    try verifyNoiseReduction()
    try verifyDrain()
    try verifyMeterLevels()
    try verifyLiveControls()
    print("audio processing check passed")
  }

  private static func verifyGain() throws {
    let original = pcm((0..<1_600).map { Int16($0 % 2 == 0 ? 1_000 : -1_000) })
    let bypass = try AudioPreprocessor(noiseReductionDB: 0, gainDB: 0)
    precondition(bypass.process(original) == original)
    let boost = try AudioPreprocessor(noiseReductionDB: 0, gainDB: 6)
    let adjusted = samples(boost.process(original))
    precondition(adjusted[0] > 1_990 && adjusted[0] < 2_000)
    precondition(adjusted[1] == -adjusted[0])
    let extremes = pcm((0..<1_600).map { $0 % 2 == 0 ? Int16.max : Int16.min })
    let limited = samples(boost.process(extremes))
    precondition(
      limited[0] == Int16.max && limited[1] == Int16.min, "Gain must never wrap PCM polarity.")
  }

  private static func verifyAutomaticLeveling() throws {
    let processor = try AudioPreprocessor(
      noiseReductionDB: 0, gainDB: 0, automaticVolumeLeveling: true)
    for _ in 0..<20 { _ = processor.process(Data(repeating: 0, count: 3_200)) }
    let tone = (0..<1_600).map { Int16(1_000 * sin(Double($0) * 2 * .pi * 440 / 16_000)) }
    var result = [Int16]()
    for _ in 0..<20 { result = samples(processor.process(pcm(tone))) }
    precondition(energy(result) > energy(tone) * 1.1, "Automatic leveling should lift quiet input.")
    precondition(energy(result) < energy(tone) * 4.1, "Automatic boost must stay within 6 dB.")
    let silence = try AudioPreprocessor(
      noiseReductionDB: 0, gainDB: 0, automaticVolumeLeveling: true)
    for _ in 0..<20 {
      precondition(energy(samples(silence.process(Data(repeating: 0, count: 3_200)))) == 0)
    }
  }

  private static func verifyNoiseReduction() throws {
    let processor = try AudioPreprocessor(noiseReductionDB: 6, gainDB: 0)
    var seed: UInt32 = 42
    var before = 0.0
    var after = 0.0
    for frame in 0..<60 {
      let noise = (0..<1_600).map { _ -> Int16 in
        seed = seed &* 1_664_525 &+ 1_013_904_223
        return Int16(Int(seed >> 16) % 401 - 200)
      }
      let result = samples(processor.process(pcm(noise)))
      if frame >= 40 {
        before += energy(noise)
        after += energy(result)
      }
    }
    precondition(
      after < before * 0.8, "Mild suppression must reduce a learned stationary noise floor.")
    let quietSpeech = try AudioPreprocessor(noiseReductionDB: 6, gainDB: 0)
    let silence = Data(repeating: 0, count: 3_200)
    for _ in 0..<10 { _ = quietSpeech.process(silence) }
    let tone = (0..<1_600).map { Int16(200 * sin(Double($0) * 2 * .pi * 440 / 16_000)) }
    let result = samples(quietSpeech.process(pcm(tone)))
    precondition(
      energy(result) > energy(tone) * 0.1, "Quiet speech-band audio must remain audible.")
  }

  private static func verifyDrain() throws {
    let format = PCM16AudioConverter.format
    let empty = PCM16AudioConverter(
      inputFormat: format, preprocessor: try AudioPreprocessor(noiseReductionDB: 6, gainDB: 0))
    precondition(empty.finish().isEmpty, "No audio must not become a fabricated silent recording.")
    let converter = PCM16AudioConverter(
      inputFormat: format, preprocessor: try AudioPreprocessor(noiseReductionDB: 6, gainDB: 0))
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_600)!
    buffer.frameLength = 1_600
    let input = buffer.int16ChannelData![0]
    for index in 0..<1_600 {
      input[index] = index < 1_440 ? 0 : Int16(2_000 * sin(Double(index) * 2 * .pi * 440 / 16_000))
    }
    let initial = converter.convert(buffer)
    let final = converter.finish()
    precondition(!initial.isEmpty && !final.isEmpty)
    precondition((initial + final).allSatisfy { $0.data.count == 3_200 })
    precondition(
      final.contains { energy(samples($0.data)) > 0 }, "Delayed final speech must be drained.")
    precondition(converter.finish().isEmpty, "Finalization must not duplicate audio.")
  }

  private static func verifyLiveControls() throws {
    let format = PCM16AudioConverter.format
    let converter = PCM16AudioConverter(inputFormat: format)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_600)!
    buffer.frameLength = 1_600
    for index in 0..<1_600 { buffer.int16ChannelData![0][index] = 1_000 }
    let original = converter.convert(buffer).first!
    var settings = DictationSettings.defaults
    settings.automaticVolumeLeveling = false
    settings.noiseReductionDB = 0
    settings.inputGainDB = 6
    try converter.updateProcessing(settings: settings)
    let louder = converter.convert(buffer)
    precondition(louder.count == 1 && louder[0].level > original.level * 1.9)
    settings.inputGainDB = -6
    try converter.updateProcessing(settings: settings)
    let quieter = converter.convert(buffer)
    precondition(quieter.count == 1 && quieter[0].level < original.level * 0.51)
    precondition(louder[0].inputLevel == quieter[0].inputLevel)
  }

  private static func pcm(_ samples: [Int16]) -> Data {
    samples.withUnsafeBytes { Data($0) }
  }

  private static func verifyMeterLevels() throws {
    let format = PCM16AudioConverter.format
    let converter = PCM16AudioConverter(
      inputFormat: format, preprocessor: try AudioPreprocessor(noiseReductionDB: 0, gainDB: 6))
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_600)!
    buffer.frameLength = 1_600
    for index in 0..<1_600 { buffer.int16ChannelData![0][index] = 1_000 }
    let chunk = converter.convert(buffer).first!
    precondition(abs(chunk.inputLevel - 6_000.0 / 32_767) < 0.001)
    precondition(
      chunk.level > chunk.inputLevel * 1.9,
      "Gain changes processed audio, not the raw microphone meter.")
  }

  private static func samples(_ data: Data) -> [Int16] {
    data.withUnsafeBytes { bytes in
      stride(from: 0, to: data.count, by: 2).map {
        bytes.loadUnaligned(fromByteOffset: $0, as: Int16.self).littleEndian
      }
    }
  }

  private static func energy(_ samples: [Int16]) -> Double {
    samples.reduce(0) { $0 + Double($1) * Double($1) }
  }
}
