// Binds Escape and temporary editing cleanup to the destination's actual AppKit window, including hide and close.

import AppKit
import SwiftUI

extension View {
  /// Escape goes to the active workflow first and otherwise hides the window, unless `blocksEscape` leaves it to the page, as during shortcut capture or a confirmation dialog. `onDeactivate` runs when the window resigns key, closes, or is hidden this way.
  func mainWindowEvents(
    appState: AppState,
    blocksEscape: Bool = false,
    onActivate: @escaping () -> Void = {},
    onDeactivate: @escaping () -> Void = {}
  ) -> some View {
    background {
      MainWindowEvents(
        onEscape: { window in
          guard !blocksEscape else { return false }
          if !appState.handleEscapeCommand() {
            onDeactivate()
            window.orderOut(nil)
          }
          return true
        }, onActivate: onActivate, onDeactivate: onDeactivate)
    }
  }
}

@MainActor
private struct MainWindowEvents: NSViewRepresentable {
  let onEscape: (NSWindow) -> Bool
  let onActivate: () -> Void
  let onDeactivate: () -> Void

  func makeNSView(context: Context) -> EventView {
    EventView(onEscape: onEscape, onActivate: onActivate, onDeactivate: onDeactivate)
  }

  func updateNSView(_ view: EventView, context: Context) {
    view.onEscape = onEscape
    view.onActivate = onActivate
    view.onDeactivate = onDeactivate
  }

  static func dismantleNSView(_ view: EventView, coordinator: ()) {
    view.stop()
  }

  final class EventView: NSView {
    var onEscape: (NSWindow) -> Bool
    var onActivate: () -> Void
    var onDeactivate: () -> Void
    private var eventMonitor: Any?

    init(
      onEscape: @escaping (NSWindow) -> Bool, onActivate: @escaping () -> Void,
      onDeactivate: @escaping () -> Void
    ) {
      self.onEscape = onEscape
      self.onActivate = onActivate
      self.onDeactivate = onDeactivate
      super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      stop()
      guard let window else { return }
      NotificationCenter.default.addObserver(
        self, selector: #selector(windowActivated), name: NSWindow.didBecomeKeyNotification,
        object: window)
      for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
        NotificationCenter.default.addObserver(
          self, selector: #selector(windowDeactivated), name: name, object: window)
      }
      eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        guard event.keyCode == 53, let self, let window = self.window,
          window.isVisible, event.window === window, window.attachedSheet == nil
        else { return event }
        return self.onEscape(window) ? nil : event
      }
    }

    @objc private func windowDeactivated(_ notification: Notification) {
      onDeactivate()
    }

    @objc private func windowActivated(_ notification: Notification) {
      onActivate()
    }

    func stop() {
      NotificationCenter.default.removeObserver(self)
      if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
      eventMonitor = nil
    }
  }
}
