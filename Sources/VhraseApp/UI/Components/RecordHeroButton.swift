// Renders the record control that sits inside a mic bar: a white disc carrying the bar's state color, still until the workflow changes.

import SwiftUI

enum RecordHeroButtonStyle {
  case hero
  case compact

  var diameter: CGFloat {
    switch self {
    case .hero: 50
    case .compact: 36
    }
  }
}

struct RecordHeroButton: View {
  let presentation: DictationPresentation
  /// Observed here so the level ring follows the microphone without re-evaluating the surface around the button.
  @ObservedObject var meter: RecordingMeter
  let style: RecordHeroButtonStyle
  let action: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isPulsing = false
  @State private var isHovered = false
  @State private var ringRotation = 0.0

  var body: some View {
    Button(action: action) {
      ZStack {
        if presentation.status.isProcessing {
          Circle()
            .stroke(
              Color.white.opacity(0.85),
              style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 6])
            )
            .frame(width: style.diameter + 12, height: style.diameter + 12)
            .rotationEffect(.degrees(ringRotation))
        }

        if isRecording {
          Circle()
            .stroke(Color.white.opacity(0.5), lineWidth: 2 + 4 * normalizedLevel)
            .frame(width: style.diameter + 8, height: style.diameter + 8)
        }

        Circle()
          .fill(discFill)
          .frame(width: style.diameter, height: style.diameter)

        if isPreparing {
          ProgressView()
            .controlSize(.small)
            .tint(VhraseTheme.statusRecording)
        } else {
          Image(systemName: presentation.recordButtonSystemImage)
            .font(.system(size: style == .hero ? 21 : 15, weight: .bold))
            .foregroundStyle(presentation.micBarTint ?? VhraseTheme.inkSecondary)
        }
      }
      .frame(width: style.diameter + 16, height: style.diameter + 16)
      .scaleEffect(buttonScale)
      .contentShape(Circle())
    }
    .buttonStyle(PressableButtonStyle(pressedScale: 0.88))
    .disabled(presentation.recordAction == .disabled)
    .accessibilityLabel(presentation.recordButtonTitle)
    .accessibilityHint(presentation.recordButtonSubtitle(style: style == .hero ? .full : .compact))
    .help(presentation.recordButtonTitle)
    .onHover { isHovered = $0 }
    .animation(
      VhraseMotion.respectingReduceMotion(VhraseMotion.bounce, reduceMotion: reduceMotion),
      value: isHovered
    )
    .animation(
      VhraseMotion.respectingReduceMotion(VhraseMotion.levelEase, reduceMotion: reduceMotion),
      value: meter.level
    )
    .animation(
      VhraseMotion.respectingReduceMotion(VhraseMotion.bounce, reduceMotion: reduceMotion),
      value: presentation.status
    )
    .onAppear(perform: updateMotion)
    .onChange(of: presentation.status) { _, _ in
      updateMotion()
    }
  }

  private var isPreparing: Bool {
    presentation.status == .preparing
  }

  private var isRecording: Bool {
    presentation.status == .recording
  }

  private var normalizedLevel: CGFloat {
    min(max(CGFloat(meter.level), 0), 1)
  }

  private var buttonScale: CGFloat {
    let pulseScale: CGFloat = isRecording && isPulsing ? 1.05 : 1
    let hoverScale: CGFloat = isHovered && !reduceMotion ? 1.06 : 1
    return pulseScale * hoverScale
  }

  /// White reads on every colored bar; the neutral setup bar gets a quiet disc instead.
  private var discFill: Color {
    presentation.micBarTint == nil ? VhraseTheme.field : .white
  }

  private func updateMotion() {
    isPulsing = false
    ringRotation = 0
    guard !reduceMotion else {
      return
    }
    if isRecording {
      withAnimation(VhraseMotion.pulse) {
        isPulsing = true
      }
    }
    if presentation.status.isProcessing {
      withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
        ringRotation = 360
      }
    }
  }
}
