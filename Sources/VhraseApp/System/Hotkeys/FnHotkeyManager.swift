// Detects Fn/Globe presses for the global shortcut by watching modifier changes, since macOS reports Fn only as a modifier flag, which Carbon hotkeys cannot register.

import AppKit
import Foundation
import OSLog

@MainActor
final class FnHotkeyManager {
  private var localMonitor: Any?
  private var globalEventTap: CFMachPort?
  private var globalEventTapSource: CFRunLoopSource?
  private var isEnabled = false
  private var wasFunctionDown = false
  private var onPressed: (() -> Void)?
  private var onReleased: (() -> Void)?
  private let logger = Logger(subsystem: "local.codex.Vhrase", category: "FnHotkey")

  func register(
    _ settings: DictationSettings,
    onPressed: @escaping () -> Void,
    onReleased: @escaping () -> Void
  ) {
    self.onPressed = onPressed
    self.onReleased = onReleased
    isEnabled = settings.hotkeyPreset == .fn
    wasFunctionDown = false
    if isEnabled {
      installMonitorsIfNeeded()
    } else {
      removeMonitors()
    }
  }

  /// Installs the global listener after Input Monitoring or Accessibility changes while Vhrase is running.
  func refreshAuthorization() {
    guard isEnabled else {
      return
    }
    installMonitorsIfNeeded()
  }

  private func installMonitorsIfNeeded() {
    if localMonitor == nil {
      localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) {
        [weak self] event in
        let isFunctionDown = event.isFunctionDown
        Task { @MainActor in
          self?.handle(isFunctionDown: isFunctionDown)
        }
        return event
      }
    }

    guard globalEventTap == nil else {
      return
    }

    let eventMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
    guard
      let eventTap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .listenOnly,
        eventsOfInterest: eventMask,
        callback: { _, type, event, userInfo in
          guard let userInfo else {
            return Unmanaged.passUnretained(event)
          }
          let manager = Unmanaged<FnHotkeyManager>
            .fromOpaque(userInfo)
            .takeUnretainedValue()
          let shouldReenable = type == .tapDisabledByTimeout || type == .tapDisabledByUserInput
          let isFunctionDown = event.flags.contains(.maskSecondaryFn)
          Task { @MainActor [weak manager] in
            if shouldReenable {
              manager?.reenableGlobalEventTap()
            } else {
              manager?.handleGlobal(isFunctionDown: isFunctionDown)
            }
          }
          return Unmanaged.passUnretained(event)
        },
        userInfo: Unmanaged.passUnretained(self).toOpaque()
      ), let source = CFMachPortCreateRunLoopSource(nil, eventTap, 0)
    else {
      logger.error(
        "Fn event tap unavailable; check Input Monitoring or Accessibility authorization")
      return
    }

    globalEventTap = eventTap
    globalEventTapSource = source
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: eventTap, enable: true)
    logger.notice("Fn event tap installed")
  }

  private func removeMonitors() {
    if let localMonitor {
      NSEvent.removeMonitor(localMonitor)
      self.localMonitor = nil
    }
    if let globalEventTapSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), globalEventTapSource, .commonModes)
      self.globalEventTapSource = nil
    }
    if let globalEventTap {
      CFMachPortInvalidate(globalEventTap)
      self.globalEventTap = nil
    }
  }

  private func reenableGlobalEventTap() {
    guard let globalEventTap else {
      return
    }
    CGEvent.tapEnable(tap: globalEventTap, enable: true)
    logger.warning("Fn event tap was disabled; reenabled and checking for a missed release")
    if wasFunctionDown,
      !CGEventSource.flagsState(.combinedSessionState).contains(.maskSecondaryFn)
    {
      handle(isFunctionDown: false)
    }
  }

  private func handleGlobal(isFunctionDown: Bool) {
    guard !NSApplication.shared.isActive else {
      return
    }
    handle(isFunctionDown: isFunctionDown)
  }

  private func handle(isFunctionDown: Bool) {
    guard isEnabled else {
      return
    }

    guard isFunctionDown != wasFunctionDown else {
      return
    }

    wasFunctionDown = isFunctionDown
    logger.notice("Fn edge down=\(isFunctionDown)")
    if isFunctionDown {
      onPressed?()
    } else {
      onReleased?()
    }
  }
}

extension NSEvent {
  fileprivate var isFunctionDown: Bool {
    modifierFlags
      .intersection(.deviceIndependentFlagsMask)
      .contains(.function)
  }
}
