// Captures a custom macOS keyboard shortcut and translates it into Vhrase's hotkey contract.

import AppKit
import Carbon
import SwiftUI

/// Captures one key equivalent from AppKit while SwiftUI owns the stored shortcut.
struct HotkeyCaptureView: NSViewRepresentable {
  @Binding var isCapturing: Bool
  let onCapture: (CustomHotkey) -> Void
  let onFnCapture: () -> Void
  let onCancel: () -> Void
  let onUnsupported: (String) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  func makeNSView(context: Context) -> CaptureView {
    let view = CaptureView()
    view.onCapture = context.coordinator.capture
    view.onFnCapture = context.coordinator.captureFn
    view.onCancel = context.coordinator.cancel
    view.onUnsupported = context.coordinator.unsupported
    return view
  }

  func updateNSView(_ nsView: CaptureView, context: Context) {
    context.coordinator.parent = self
    nsView.onCapture = context.coordinator.capture
    nsView.onFnCapture = context.coordinator.captureFn
    nsView.onCancel = context.coordinator.cancel
    nsView.onUnsupported = context.coordinator.unsupported
    nsView.setCapturing(isCapturing)
  }

  static func dismantleNSView(_ nsView: CaptureView, coordinator: Coordinator) {
    nsView.setCapturing(false)
  }

  final class Coordinator {
    var parent: HotkeyCaptureView

    init(parent: HotkeyCaptureView) {
      self.parent = parent
    }

    @MainActor
    func capture(_ hotkey: CustomHotkey) {
      parent.onCapture(hotkey)
      parent.isCapturing = false
    }

    @MainActor
    func captureFn() {
      parent.onFnCapture()
      parent.isCapturing = false
    }

    @MainActor
    func cancel() {
      parent.onCancel()
      parent.isCapturing = false
    }

    @MainActor
    func unsupported(_ message: String) {
      parent.onUnsupported(message)
    }
  }

  final class CaptureView: NSView {
    private var isCapturing = false
    private var eventMonitor: Any?
    var onCapture: ((CustomHotkey) -> Void)?
    var onFnCapture: (() -> Void)?
    var onCancel: (() -> Void)?
    var onUnsupported: ((String) -> Void)?

    override var acceptsFirstResponder: Bool {
      true
    }

    func setCapturing(_ isCapturing: Bool) {
      self.isCapturing = isCapturing
      if isCapturing {
        startMonitoring()
      } else {
        stopMonitoring()
      }
    }

    override func keyDown(with event: NSEvent) {
      guard isCapturing else {
        super.keyDown(with: event)
        return
      }

      _ = handleCaptureEvent(event)
    }

    override func flagsChanged(with event: NSEvent) {
      guard isCapturing else {
        super.flagsChanged(with: event)
        return
      }

      _ = handleCaptureEvent(event)
    }

    private func startMonitoring() {
      guard eventMonitor == nil else {
        return
      }

      window?.makeKey()
      eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) {
        [weak self] event in
        guard let self, self.isCapturing else {
          return event
        }

        return self.handleCaptureEvent(event) ? nil : event
      }
    }

    private func stopMonitoring() {
      guard let eventMonitor else {
        return
      }

      NSEvent.removeMonitor(eventMonitor)
      self.eventMonitor = nil
    }

    private func handleCaptureEvent(_ event: NSEvent) -> Bool {
      if event.type == .keyDown, event.keyCode == UInt16(kVK_Escape) {
        onCancel?()
        return true
      }

      if event.modifierFlags.contains(.function) {
        onFnCapture?()
        return true
      }

      guard event.type == .keyDown else {
        return false
      }

      guard let hotkey = CustomHotkey(event: event) else {
        onUnsupported?("Use Control, Option, Command, or Shift with a key.")
        NSSound.beep()
        return true
      }

      onCapture?(hotkey)
      return true
    }
  }
}

extension CustomHotkey {
  fileprivate init?(event: NSEvent) {
    let carbonModifiers = event.modifierFlags.carbonHotkeyModifiers
    guard carbonModifiers != 0,
      let keyName = event.hotkeyKeyName
    else {
      return nil
    }

    self.init(
      keyCode: UInt32(event.keyCode),
      modifiers: carbonModifiers,
      display: event.modifierFlags.hotkeyDisplayPrefix + keyName
    )
  }
}

extension NSEvent.ModifierFlags {
  fileprivate var carbonHotkeyModifiers: UInt32 {
    let flags = intersection(.deviceIndependentFlagsMask)
    var modifiers: UInt32 = 0

    if flags.contains(.command) {
      modifiers |= UInt32(cmdKey)
    }
    if flags.contains(.control) {
      modifiers |= UInt32(controlKey)
    }
    if flags.contains(.option) {
      modifiers |= UInt32(optionKey)
    }
    if flags.contains(.shift) {
      modifiers |= UInt32(shiftKey)
    }

    return modifiers
  }

  fileprivate var hotkeyDisplayPrefix: String {
    let flags = intersection(.deviceIndependentFlagsMask)
    var parts: [String] = []

    if flags.contains(.command) {
      parts.append("⌘")
    }
    if flags.contains(.control) {
      parts.append("⌃")
    }
    if flags.contains(.option) {
      parts.append("⌥")
    }
    if flags.contains(.shift) {
      parts.append("⇧")
    }

    return parts.joined()
  }
}

extension NSEvent {
  fileprivate var hotkeyKeyName: String? {
    switch Int(keyCode) {
    case kVK_Space:
      return "Space"
    case kVK_Return:
      return "Return"
    case kVK_Tab:
      return "Tab"
    case kVK_Delete:
      return "Delete"
    case kVK_ForwardDelete:
      return "Forward Delete"
    case kVK_LeftArrow:
      return "Left"
    case kVK_RightArrow:
      return "Right"
    case kVK_UpArrow:
      return "Up"
    case kVK_DownArrow:
      return "Down"
    default:
      guard
        let character = charactersIgnoringModifiers?.trimmingCharacters(
          in: .whitespacesAndNewlines),
        !character.isEmpty
      else {
        return nil
      }
      return character.uppercased()
    }
  }
}
