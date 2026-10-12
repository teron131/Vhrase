// Presents a quiet recording pill without stealing focus from the app receiving dictation.

import AppKit
import SwiftUI

/// Keeps active dictation to a waveform or progress indicator, revealing controls only when approached.
struct RecorderHUDView: View {
  /// One capsule size for every workflow state, so the panel never resizes or shifts between states.
  static let size = CGSize(width: 184, height: 52)

  @ObservedObject var appState: AppState
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var showsControls = false

  var body: some View {
    Group {
      if case .failed(let message) = appState.status {
        failureContent(message)
      } else {
        capsuleContent
      }
    }
    .frame(
      width: Self.size.width,
      height: Self.size.height
    )
    .background {
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .fill(VhraseTheme.recorderBackground)
    }
    .overlay {
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .strokeBorder(VhraseTheme.recorderBorder, lineWidth: 1)
        .allowsHitTesting(false)
    }
    .foregroundStyle(.white)
    .environment(\.colorScheme, .dark)
    .fixedSize()
    .background {
      RecorderHoverTracking { showsControls = $0 }
    }
    .animation(
      VhraseMotion.respectingReduceMotion(VhraseMotion.snappy, reduceMotion: reduceMotion),
      value: showsControls
    )
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Vhrase workflow")
  }

  @ViewBuilder
  private var capsuleContent: some View {
    switch appState.status {
    case .recording:
      ZStack {
        RecorderWaveform(level: appState.recordingLevel)
          .overlay { waveformScrim }
          .contentShape(Rectangle())
          .onTapGesture { showsControls = true }
          .accessibilityElement(children: .ignore)
          .accessibilityHidden(false)
          .accessibilityLabel("Recording")
          .accessibilityValue(appState.presentation.elapsedTime)
          .accessibilityAction(named: "Finish recording") { appState.toggleRecording() }
          .accessibilityAction(named: "Cancel recording") { appState.cancelRecording() }

        HStack {
          hudButton("Cancel recording", systemImage: "xmark") {
            appState.cancelRecording()
          }
          Spacer()
          hudButton("Finish recording", systemImage: "checkmark") {
            appState.toggleRecording()
          }
          .accessibilityHint("Stops recording and transcribes the captured audio")
        }
        .opacity(showsControls ? 1 : 0)
        .padding(.horizontal, 12)
      }
      .help(
        "Recording · \(appState.presentation.elapsedTime). Hover or click the waveform for controls."
      )
    case .preparing:
      ZStack {
        activityIndicator("Starting microphone")
        HStack {
          Spacer()
          hudButton("Cancel", systemImage: "xmark") { appState.cancelRecording() }
            .opacity(showsControls ? 1 : 0)
        }
        .padding(.horizontal, 12)
      }
    case .transcribing:
      if appState.canCancelTranscription {
        ZStack {
          activityIndicator(
            appState.parakeetModel.isPreparing
              ? "Preparing Parakeet for this Mac"
              : "Transcribing with \(appState.settings.provider.title)")
          HStack {
            Spacer()
            hudButton("Cancel transcription", systemImage: "xmark") {
              appState.cancelTranscription()
            }
            .opacity(showsControls ? 1 : 0)
          }
          .padding(.horizontal, 12)
        }
      } else {
        activityIndicator("Transcribing with \(appState.settings.provider.title)")
      }
    case .adjusting:
      if appState.isTextPolishing {
        ZStack {
          activityIndicator("Polishing focused text")
          HStack {
            Spacer()
            hudButton("Cancel text polishing", systemImage: "xmark") {
              appState.cancelTextPolish()
            }
            .opacity(showsControls ? 1 : 0)
          }
          .padding(.horizontal, 12)
        }
      } else {
        activityIndicator("Applying writing preferences")
      }
    case .completed:
      HStack(spacing: 8) {
        Image(systemName: appState.lastCompletion.completionSystemImage)
          .font(.system(size: 13, weight: .semibold))
          .accessibilityHidden(true)
        Text(appState.lastCompletion.completionTitle)
          .font(.callout.weight(.medium))
          .lineLimit(1)
      }
      .help(appState.lastCompletion.completionDetail)
      .accessibilityElement(children: .combine)
      .contextMenu {
        if appState.lastCompletion.isTranscript, !appState.lastTranscript.isEmpty {
          Button("Copy transcript") { appState.copyLastTranscript() }
        }
        Button("Dismiss") { appState.dismissWorkflowOutcome() }
      }
      .onTapGesture { appState.dismissWorkflowOutcome() }
      .accessibilityAction(named: "Dismiss") { appState.dismissWorkflowOutcome() }
    case .idle:
      Image(systemName: "mic")
        .accessibilityLabel("Ready")
    case .failed:
      EmptyView()
    }
  }

  /// Fades the waveform's ends into the pill while the recording controls show, so the stream passes behind them.
  /// The stops stay solid across each 28-point control and clear within the next 14 points.
  private var waveformScrim: some View {
    LinearGradient(
      stops: [
        .init(color: VhraseTheme.recorderBackground, location: 0),
        .init(color: VhraseTheme.recorderBackground, location: 0.19),
        .init(color: .clear, location: 0.28),
        .init(color: .clear, location: 0.72),
        .init(color: VhraseTheme.recorderBackground, location: 0.81),
        .init(color: VhraseTheme.recorderBackground, location: 1),
      ],
      startPoint: .leading,
      endPoint: .trailing
    )
    .opacity(showsControls ? 1 : 0)
    .allowsHitTesting(false)
  }

  private func activityIndicator(_ title: String) -> some View {
    ProgressView()
      .controlSize(.small)
      .tint(.white)
      .accessibilityLabel(title)
      .help(title)
  }

  /// Keeps failure feedback on the same baseline as every other state while retaining immediate recovery.
  private func failureContent(_ message: String) -> some View {
    HStack(spacing: 8) {
      Image(systemName: "exclamationmark.circle")
        .font(.system(size: 13, weight: .semibold))
        .accessibilityHidden(true)
      Text("Failed")
        .font(.callout.weight(.medium))
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(message)
        .accessibilityLabel("Vhrase failed: \(message)")
      hudButton("Try again", systemImage: "arrow.clockwise") { appState.retryLastWorkflow() }
      hudButton("Dismiss", systemImage: "xmark") { appState.dismissWorkflowOutcome() }
    }
    .padding(.horizontal, 12)
  }

  private func hudButton(
    _ title: String,
    systemImage: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: 11, weight: .semibold))
        .frame(width: 28, height: 28)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .help(title)
    .accessibilityLabel(title)
  }

  private var cornerRadius: CGFloat {
    Self.size.height / 2
  }
}

/// Tracks the pointer even when another app is active, as expected for a non-activating recorder panel.
private struct RecorderHoverTracking: NSViewRepresentable {
  var onHover: (Bool) -> Void

  func makeNSView(context: Context) -> TrackingView {
    TrackingView(onHover: onHover)
  }

  func updateNSView(_ view: TrackingView, context: Context) {
    view.onHover = onHover
  }

  final class TrackingView: NSView {
    var onHover: (Bool) -> Void

    init(onHover: @escaping (Bool) -> Void) {
      self.onHover = onHover
      super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
      super.updateTrackingAreas()
      trackingAreas.forEach(removeTrackingArea)
      addTrackingArea(
        NSTrackingArea(
          rect: .zero,
          options: [
            .mouseEnteredAndExited, .activeAlways, .inVisibleRect, .enabledDuringMouseDrag,
          ],
          owner: self,
          userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) { onHover(true) }
    override func mouseExited(with event: NSEvent) { onHover(false) }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
  }
}
