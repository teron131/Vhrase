// Renders recent microphone levels chronologically, padding missing history with quiet bars.

import SwiftUI

struct WaveformView: View {
  let history: [Double]
  var response = WaveformResponse.standard
  var barCount = 24
  var tint = VhraseTheme.statusRecording
  var height: CGFloat = 54

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    GeometryReader { proxy in
      let spacing: CGFloat = 3
      let width = max(2, (proxy.size.width - CGFloat(barCount - 1) * spacing) / CGFloat(barCount))
      HStack(alignment: .center, spacing: spacing) {
        ForEach(0..<barCount, id: \.self) { index in
          let displayLevel = barLevel(index: index)
          Capsule()
            .fill(tint.opacity(0.34 + 0.66 * displayLevel))
            .frame(
              width: width,
              height: max(4, proxy.size.height * (0.12 + displayLevel * 0.88))
            )
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(height: height)
    .animation(
      VhraseMotion.respectingReduceMotion(
        .easeInOut(duration: max(0.22, response.animationDuration)),
        reduceMotion: reduceMotion
      ),
      value: history
    )
    .accessibilityHidden(true)
  }

  private func barLevel(index: Int) -> CGFloat {
    let padding = max(0, barCount - history.count)
    guard index >= padding else {
      return 0
    }
    let visibleHistory = history.suffix(barCount)
    let sampleIndex = visibleHistory.index(visibleHistory.startIndex, offsetBy: index - padding)
    return CGFloat(
      WaveformLevelResponse.displayLevel(visibleHistory[sampleIndex], response: response)
    )
  }
}
