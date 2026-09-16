// Presents a quiet recording pill without stealing focus from the app receiving dictation.

import AppKit
import Combine
import SwiftUI

/// Keeps active dictation to a waveform or progress indicator, revealing controls only when approached.
struct StatusPopupView: View {
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
      width: popupSize.width,
      height: popupSize.height
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
      HStack(spacing: 8) {
        hudButton("Cancel recording", systemImage: "xmark") {
          appState.cancelRecording()
        }
        .opacity(showsControls ? 1 : 0)

        WaveformView(
          history: appState.recordingWaveformHistory,
          response: .live,
          barCount: 14,
          tint: .white,
          height: 20
        )
        .frame(width: 104)
        .contentShape(Rectangle())
        .onTapGesture { showsControls = true }
        .accessibilityElement(children: .ignore)
        .accessibilityHidden(false)
        .accessibilityLabel("Recording")
        .accessibilityValue(appState.presentation.elapsedTime)
        .accessibilityAction(named: "Finish recording") { appState.toggleRecording() }
        .accessibilityAction(named: "Cancel recording") { appState.cancelRecording() }

        hudButton("Finish recording", systemImage: "checkmark") {
          appState.toggleRecording()
        }
        .opacity(showsControls ? 1 : 0)
        .accessibilityHint("Stops recording and transcribes the captured audio")
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
      activityIndicator("Transcribing with \(appState.settings.provider.title)")
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

  private var popupSize: CGSize {
    StatusPopupContentPolicy.size(for: appState.status)
  }

  private var cornerRadius: CGFloat {
    popupSize.height / 2
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

/// Owns the non-activating panel so recorder feedback never steals focus from the target app.
@MainActor
final class RecorderHUDPanelController: NSWindowController {
  private weak var appState: AppState?
  private var statusObservation: AnyCancellable?
  private var workflowScreen: NSScreen?
  private var previousStatus: AppStatus = .idle

  init(appState: AppState) {
    self.appState = appState
    let hostingView = NSHostingView(rootView: StatusPopupView(appState: appState))
    // The controller owns panel size and origin as the SwiftUI content changes between workflow states.
    hostingView.sizingOptions = []

    let panel = NSPanel(
      contentRect: NSRect(origin: .zero, size: StatusPopupContentPolicy.size(for: .idle)),
      styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    panel.contentView = hostingView
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = false
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    panel.isFloatingPanel = true
    panel.hidesOnDeactivate = false
    panel.becomesKeyOnlyIfNeeded = true
    panel.isMovable = false
    panel.animationBehavior = .none

    super.init(window: panel)

    statusObservation = appState.$status.combineLatest(appState.$isWorkflowPopupDismissed)
      .sink { [weak self] status, isDismissed in
        self?.update(for: status, isDismissed: isDismissed)
      }
    update(for: appState.status, isDismissed: appState.isWorkflowPopupDismissed)
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    return nil
  }

  /// Mirrors the current workflow state without taking ownership of outcome timing.
  func update(for status: AppStatus, isDismissed: Bool) {
    let startsNewWorkflow =
      previousStatus.canStartRecording
      && status != previousStatus
      && status.showsWorkflowPopup
    previousStatus = status

    guard status.showsWorkflowPopup, !isDismissed, let panel = window else {
      window?.orderOut(nil)
      workflowScreen = nil
      return
    }

    if startsNewWorkflow || workflowScreen == nil {
      workflowScreen = screenAtPointer()
    }
    applyFrame(to: panel, status: status)
    panel.orderFrontRegardless()
  }

  /// Applies size and position together so AppKit never exposes its top-edge-preserving resize behavior.
  private func applyFrame(to panel: NSWindow, status: AppStatus) {
    guard let visibleFrame = workflowScreen?.visibleFrame else {
      return
    }

    let contentSize = StatusPopupContentPolicy.size(for: status)
    let frameSize = panel.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize)).size
    let frame = NSRect(
      x: visibleFrame.midX - frameSize.width / 2,
      y: visibleFrame.minY + 24,
      width: frameSize.width,
      height: frameSize.height
    )
    panel.setFrame(frame, display: panel.isVisible, animate: false)
  }

  private func screenAtPointer() -> NSScreen? {
    let mouseLocation = NSEvent.mouseLocation
    return NSScreen.screens.first { $0.frame.contains(mouseLocation) }
      ?? NSScreen.main
      ?? NSScreen.screens.first
  }
}
