// Owns recorder-panel visibility, sizing, and screen affinity without activating the target application.

import AppKit
import Combine
import SwiftUI

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
