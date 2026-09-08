// Holds at most five seconds of processed microphone PCM in memory and packages it for explicit local playback.

import Foundation

struct AudioTestClip {
  private(set) var pcm = Data()
  static let maximumByteCount = 16_000 * 2 * 5

  var isComplete: Bool { pcm.count == Self.maximumByteCount }
  var isEmpty: Bool { pcm.isEmpty }

  /// Bounds retention even if a capture callback supplies more than the remaining test duration.
  mutating func append(_ data: Data) {
    pcm.append(data.prefix(Self.maximumByteCount - pcm.count))
  }

  /// Encodes mono 16 kHz PCM16 as an in-memory WAV; no audio file is created.
  var wavData: Data {
    var data = Data("RIFF".utf8)
    append(UInt32(36 + pcm.count), to: &data)
    data.append(contentsOf: "WAVEfmt ".utf8)
    append(UInt32(16), to: &data)
    append(UInt16(1), to: &data)
    append(UInt16(1), to: &data)
    append(UInt32(16_000), to: &data)
    append(UInt32(32_000), to: &data)
    append(UInt16(2), to: &data)
    append(UInt16(16), to: &data)
    data.append(contentsOf: "data".utf8)
    append(UInt32(pcm.count), to: &data)
    data.append(pcm)
    return data
  }

  private func append<Value: FixedWidthInteger>(_ value: Value, to data: inout Data) {
    var littleEndian = value.littleEndian
    withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
  }
}
