// Verifies that the live popup waveform reacts to speech without animating ambient silence.

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

        print("Waveform response checks passed")
    }
}
