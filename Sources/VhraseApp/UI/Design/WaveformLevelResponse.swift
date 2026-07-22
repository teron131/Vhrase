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
    private static let liveNoiseFloor = 0.012
    private static let liveSensitivity = 1.55

    static func displayLevel(_ level: Double, response: WaveformResponse) -> Double {
        let clampedLevel = min(max(level, 0), 1)
        guard response == .live else {
            return clampedLevel
        }
        guard clampedLevel > liveNoiseFloor else {
            return 0
        }

        let audibleRange = (clampedLevel - liveNoiseFloor) / (1 - liveNoiseFloor)
        return min(1, pow(audibleRange, 0.48) * liveSensitivity)
    }
}
