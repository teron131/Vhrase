// Maps microphone levels to waveform motion for standard and live recording surfaces.

import Foundation

enum WaveformResponse {
  case standard
  case live

  var animationDuration: Double {
    switch self {
    case .standard:
      0.1
    case .live:
      0.045
    }
  }
}

enum WaveformLevelResponse {
  private static let noiseFloor = 0.012
  private static let liveSensitivity = 1.55

  static func displayLevel(_ level: Double, response: WaveformResponse) -> Double {
    guard response == .live else {
      return min(max(level, 0), 1)
    }
    return min(1, pow(audibleLevel(level), 0.48) * liveSensitivity)
  }

  /// The level's share of the range above the ambient noise floor, so silence reads as zero and loudness stays proportional.
  static func audibleLevel(_ level: Double) -> Double {
    let clampedLevel = min(max(level, 0), 1)
    return max(0, clampedLevel - noiseFloor) / (1 - noiseFloor)
  }
}
