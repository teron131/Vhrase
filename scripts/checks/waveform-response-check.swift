// Verifies that live waveforms react to speech without animating ambient silence.

import Foundation

@main
struct WaveformResponseCheck {
  static func main() {
    precondition(WaveformLevelResponse.displayLevel(0, response: .live) == 0)
    precondition(WaveformLevelResponse.displayLevel(0.01, response: .live) == 0)

    let quietSpeech = WaveformLevelResponse.displayLevel(0.05, response: .live)
    let normalSpeech = WaveformLevelResponse.displayLevel(0.2, response: .live)
    precondition(quietSpeech >= 0.3)
    precondition(normalSpeech > quietSpeech)
    precondition(normalSpeech >= 0.65)
    precondition(WaveformLevelResponse.displayLevel(1, response: .live) == 1)

    precondition(WaveformLevelResponse.displayLevel(0.2, response: .standard) == 0.2)

    precondition(WaveformLevelResponse.audibleLevel(0.01) == 0)
    precondition(WaveformLevelResponse.audibleLevel(1) == 1)
    let audibleStep =
      WaveformLevelResponse.audibleLevel(0.5) - WaveformLevelResponse.audibleLevel(0.4)
    let audibleDoubleStep =
      WaveformLevelResponse.audibleLevel(0.6) - WaveformLevelResponse.audibleLevel(0.4)
    precondition(abs(audibleDoubleStep - 2 * audibleStep) < 1e-9)

    print("Waveform response checks passed")
  }
}
