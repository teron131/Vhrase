// Monitors Escape while another app is focused so Vhrase's non-activating workflow HUD remains cancellable.

import AppKit

@MainActor
final class EscapeKeyMonitor {
  private var globalMonitor: Any?

  /// Enables a global listener only while transient workflow feedback is visible outside the active Vhrase window.
  func setEnabled(_ isEnabled: Bool, onEscape: @escaping @MainActor () -> Void) {
    if isEnabled {
      installIfNeeded(onEscape: onEscape)
    } else {
      removeMonitors()
    }
  }

  private func installIfNeeded(onEscape: @escaping @MainActor () -> Void) {
    if globalMonitor == nil {
      globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
        guard event.keyCode == 53 else {
          return
        }
        Task { @MainActor in
          onEscape()
        }
      }
    }
  }

  private func removeMonitors() {
    if let globalMonitor {
      NSEvent.removeMonitor(globalMonitor)
      self.globalMonitor = nil
    }
  }
}
