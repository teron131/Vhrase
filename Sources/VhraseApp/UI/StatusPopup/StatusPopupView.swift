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
    .accessibilityLabel("Vhrase dictation")
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
          level: appState.recordingLevel,
          response: .live,
          barCount: 6,
          tint: .white,
          height: 20
        )
        .frame(width: 44)
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
      activityIndicator("Applying writing preferences")
    case .completed:
      HStack(spacing: 8) {
        Image(systemName: appState.lastDelivery.completionSystemImage)
          .font(.system(size: 13, weight: .semibold))
          .accessibilityHidden(true)
        Text(appState.lastDelivery.completionTitle)
          .font(.callout.weight(.medium))
          .lineLimit(1)
      }
      .help(appState.lastDelivery.completionDetail)
      .accessibilityElement(children: .combine)
      .contextMenu {
        if !appState.lastTranscript.isEmpty {
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

  /// Expands only for a failure so its explanation and recovery never depend on a tooltip.
  private func failureContent(_ message: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Label("Dictation failed", systemImage: "exclamationmark.circle")
          .font(.callout.weight(.semibold))
        Spacer()
        hudButton("Try again", systemImage: "arrow.clockwise") { appState.toggleRecording() }
        hudButton("Dismiss", systemImage: "xmark") { appState.dismissWorkflowOutcome() }
      }
      ScrollView {
        Text(message)
          .font(.caption)
          .foregroundStyle(.white.opacity(0.8))
          .frame(maxWidth: .infinity, alignment: .leading)
          .textSelection(.enabled)
      }
      .frame(maxHeight: .infinity)
    }
    .padding(14)
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
    if case .failed = appState.status { return VhraseTheme.sectionCornerRadius }
    return popupSize.height / 2
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
  private var delayedHideTask: Task<Void, Never>?
  private var statusObservation: AnyCancellable?
  private var workflowScreen: NSScreen?
  private var previousStatus: AppStatus = .idle

  init(appState: AppState) {
    self.appState = appState
    let hostingView = NSHostingView(rootView: StatusPopupView(appState: appState))

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
    panel.animationBehavior = .utilityWindow

    super.init(window: panel)

    statusObservation = appState.$status.removeDuplicates()
      .sink { [weak self] status in
        self?.update(for: status)
      }
    update(for: appState.status)
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    return nil
  }

  /// Shows active and outcome states, with completed feedback dismissed after a short confirmation.
  func update(for status: AppStatus) {
    delayedHideTask?.cancel()
    delayedHideTask = nil

    let startsNewWorkflow =
      previousStatus.canStartRecording
      && status != previousStatus
      && status.showsWorkflowPopup
    previousStatus = status

    guard status.showsWorkflowPopup, let panel = window else {
      window?.orderOut(nil)
      workflowScreen = nil
      return
    }

    if startsNewWorkflow || workflowScreen == nil {
      workflowScreen = screenAtPointer()
    }
    resizeAndPosition(panel, status: status)
    panel.orderFrontRegardless()

    DispatchQueue.main.async { [weak self, weak panel] in
      guard let self, let panel else {
        return
      }
      self.resizeAndPosition(panel, status: status)
    }

    guard status == .completed else {
      return
    }

    delayedHideTask = Task { [weak self, weak panel] in
      try? await Task.sleep(for: .seconds(4.0))
      guard !Task.isCancelled,
        self?.appState?.status == .completed
      else {
        return
      }
      panel?.orderOut(nil)
    }
  }

  private func resizeAndPosition(_ panel: NSWindow, status: AppStatus) {
    panel.setContentSize(StatusPopupContentPolicy.size(for: status))
    position(panel)
  }

  private func position(_ panel: NSWindow) {
    guard let visibleFrame = workflowScreen?.visibleFrame else {
      return
    }

    let origin = NSPoint(
      x: visibleFrame.midX - panel.frame.width / 2,
      y: visibleFrame.minY + 24
    )
    panel.setFrameOrigin(origin)
  }

  private func screenAtPointer() -> NSScreen? {
    let mouseLocation = NSEvent.mouseLocation
    return NSScreen.screens.first { $0.frame.contains(mouseLocation) }
      ?? NSScreen.main
      ?? NSScreen.screens.first
  }
}
