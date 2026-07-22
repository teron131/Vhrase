// Renders Vhrase's shared full-size and compact recording affordance.

import SwiftUI

enum RecordHeroButtonStyle {
    case hero
    case compact

    var diameter: CGFloat {
        switch self {
        case .hero: 72
        case .compact: 40
        }
    }
}

struct RecordHeroButton: View {
    let presentation: DictationPresentation
    let recordingLevel: Double
    let style: RecordHeroButtonStyle
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false
    @State private var isHovered = false
    @State private var ringRotation = 0.0
    @State private var ambientRingIsExpanded = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if style == .hero {
                    signalRings
                }

                if presentation.status.isProcessing {
                    Circle()
                        .stroke(
                            VhraseTheme.statusProcessing.opacity(0.72),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 7])
                        )
                        .frame(width: style.diameter + 18, height: style.diameter + 18)
                        .rotationEffect(.degrees(ringRotation))
                }

                if isRecording {
                    Circle()
                        .stroke(VhraseTheme.statusRecording.opacity(0.5), lineWidth: 2 + 4 * normalizedLevel)
                        .frame(width: style.diameter + 10, height: style.diameter + 10)
                }

                Circle()
                    .fill(buttonFill)
                    .frame(width: style.diameter, height: style.diameter)
                    .shadow(color: glowColor, radius: style == .hero ? 24 : 10, y: style == .hero ? 8 : 3)

                if isPreparing {
                    ProgressView()
                        .controlSize(style == .hero ? .large : .small)
                        .tint(.white)
                } else {
                    Image(systemName: presentation.recordButtonSystemImage)
                        .font(.system(size: style == .hero ? 25 : 15, weight: .bold))
                        .foregroundStyle(iconColor)
                }
            }
            .frame(
                width: style == .hero ? style.diameter + 76 : style.diameter + 12,
                height: style == .hero ? style.diameter + 76 : style.diameter + 12
            )
            .scaleEffect(buttonScale)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(presentation.recordAction == .disabled)
        .accessibilityLabel(presentation.recordButtonTitle)
        .accessibilityHint(presentation.recordButtonSubtitle(style: style == .hero ? .full : .compact))
        .onHover { isHovered = $0 }
        .animation(
            VhraseMotion.respectingReduceMotion(VhraseMotion.snappy, reduceMotion: reduceMotion),
            value: isHovered
        )
        .animation(
            VhraseMotion.respectingReduceMotion(VhraseMotion.levelEase, reduceMotion: reduceMotion),
            value: recordingLevel
        )
        .animation(
            VhraseMotion.respectingReduceMotion(VhraseMotion.settle, reduceMotion: reduceMotion),
            value: presentation.status
        )
        .onAppear(perform: updateMotion)
        .onChange(of: presentation.status) { _, _ in
            updateMotion()
        }
    }

    private var signalRings: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(
                        signalColor.opacity(0.16 - Double(index) * 0.035),
                        lineWidth: 1
                    )
                    .frame(
                        width: style.diameter + CGFloat(30 + index * 20),
                        height: style.diameter + CGFloat(30 + index * 20)
                    )
                    .scaleEffect(
                        (ambientRingIsExpanded ? 1.055 : 1)
                            * (isRecording ? 1 + normalizedLevel * CGFloat(index + 1) * 0.035 : 1)
                    )
            }
        }
        .accessibilityHidden(true)
    }

    private var isPreparing: Bool {
        presentation.status == .preparing
    }

    private var isRecording: Bool {
        presentation.status == .recording
    }

    private var normalizedLevel: CGFloat {
        min(max(CGFloat(recordingLevel), 0), 1)
    }

    private var signalColor: Color {
        switch presentation.status {
        case .recording:
            VhraseTheme.statusRecording
        case .preparing, .transcribing, .adjusting:
            VhraseTheme.statusProcessing
        default:
            VhraseTheme.accent
        }
    }

    private var buttonScale: CGFloat {
        let pulseScale: CGFloat = isRecording && isPulsing ? 1.045 : 1
        let hoverScale: CGFloat = isHovered && !reduceMotion ? 1.035 : 1
        return pulseScale * hoverScale
    }

    private var buttonFill: Color {
        if isRecording || isPreparing {
            return VhraseTheme.statusRecording
        }
        return presentation.coreRecordingReady && presentation.status.canStartRecording
            ? VhraseTheme.accent
            : VhraseTheme.field
    }

    private var iconColor: Color {
        presentation.coreRecordingReady || isRecording || isPreparing ? .white : VhraseTheme.inkSecondary
    }

    private var glowColor: Color {
        guard style == .hero, presentation.coreRecordingReady else {
            return .clear
        }
        return (isRecording ? VhraseTheme.statusRecording : VhraseTheme.accent).opacity(0.35)
    }

    /// Restarts only the motion relevant to the newly entered workflow state.
    private func updateMotion() {
        isPulsing = false
        ringRotation = 0
        ambientRingIsExpanded = false
        guard !reduceMotion else {
            return
        }
        if style == .hero {
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                ambientRingIsExpanded = true
            }
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
