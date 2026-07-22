// Visualizes normalized microphone level with one allocation-light shared waveform.

import SwiftUI

struct WaveformView: View {
    private static let profiles: [CGFloat] = [
        0.34, 0.52, 0.76, 0.48, 0.9, 0.62, 1, 0.72,
        0.42, 0.82, 0.56, 0.94, 0.68, 0.38, 0.78, 0.5,
        0.88, 0.64, 0.98, 0.58, 0.74, 0.44, 0.84, 0.54,
    ]

    let level: Double
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
                    Capsule()
                        .fill(tint.opacity(0.34 + 0.66 * normalizedLevel))
                        .frame(
                            width: width,
                            height: barHeight(index: index, availableHeight: proxy.size.height)
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: height)
        .animation(
            VhraseMotion.respectingReduceMotion(
                .easeOut(duration: response.animationDuration),
                reduceMotion: reduceMotion
            ),
            value: level
        )
        .accessibilityHidden(true)
    }

    private var normalizedLevel: CGFloat {
        CGFloat(WaveformLevelResponse.displayLevel(level, response: response))
    }

    private func barHeight(index: Int, availableHeight: CGFloat) -> CGFloat {
        let profile = Self.profiles[index % Self.profiles.count]
        return max(4, availableHeight * (0.12 + normalizedLevel * 0.88) * profile)
    }
}
