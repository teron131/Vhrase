// Shows the active recording's waveform and running time by observing the meter directly, so the surfaces around them are not re-evaluated with every level or second.

import SwiftUI

struct RecordingWaveformView: View {
  @ObservedObject var meter: RecordingMeter
  /// False rests the line as quiet dots, for a surface that stays on screen between recordings.
  var isLive = true
  let barCount: Int
  var tint = VhraseTheme.statusRecording
  let height: CGFloat

  var body: some View {
    WaveformView(
      history: isLive ? meter.waveformHistory : [], barCount: barCount, tint: tint, height: height)
  }
}

/// Callers set the font and color.
struct RecordingElapsedTime: View {
  @ObservedObject var meter: RecordingMeter

  var body: some View {
    Text(meter.elapsedTime)
      .contentTransition(.numericText())
  }
}
