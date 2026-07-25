// Registers and dispatches Carbon-based global keyboard shortcuts for dictation control.

import Carbon
import Foundation

@MainActor
final class GlobalHotkeyManager {
  private var hotkeyRef: EventHotKeyRef?
  private var eventHandlerRef: EventHandlerRef?
  private var onPressed: (() -> Void)?
  private var onReleased: (() -> Void)?

  func register(
    _ settings: DictationSettings,
    onPressed: @escaping () -> Void,
    onReleased: @escaping () -> Void
  ) {
    self.onPressed = onPressed
    self.onReleased = onReleased
    unregisterHotkey()

    guard let definition = CarbonHotkeyDefinition(settings: settings) else {
      return
    }

    installHandlerIfNeeded()

    let hotkeyID = EventHotKeyID(
      signature: OSType(0x4344_4943),
      id: UInt32(definition.id)
    )
    let status = RegisterEventHotKey(
      definition.keyCode,
      definition.modifiers,
      hotkeyID,
      GetApplicationEventTarget(),
      0,
      &hotkeyRef
    )

    if status != noErr {
      NSLog("Vhrase failed to register hotkey \(settings.hotkeyDisplay): \(status)")
    }
  }

  private func unregisterHotkey() {
    guard let hotkeyRef else {
      return
    }
    UnregisterEventHotKey(hotkeyRef)
    self.hotkeyRef = nil
  }

  private func installHandlerIfNeeded() {
    guard eventHandlerRef == nil else {
      return
    }

    var eventTypes = [
      EventTypeSpec(
        eventClass: OSType(kEventClassKeyboard),
        eventKind: UInt32(kEventHotKeyPressed)
      ),
      EventTypeSpec(
        eventClass: OSType(kEventClassKeyboard),
        eventKind: UInt32(kEventHotKeyReleased)
      ),
    ]

    let pointer = Unmanaged.passUnretained(self).toOpaque()
    let status = InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, userData in
        guard let userData else {
          return noErr
        }
        let manager = Unmanaged<GlobalHotkeyManager>
          .fromOpaque(userData)
          .takeUnretainedValue()
        let eventKind = event.map { GetEventKind($0) } ?? UInt32(kEventHotKeyPressed)
        Task { @MainActor in
          if eventKind == UInt32(kEventHotKeyReleased) {
            manager.onReleased?()
          } else {
            manager.onPressed?()
          }
        }
        return noErr
      },
      eventTypes.count,
      &eventTypes,
      pointer,
      &eventHandlerRef
    )

    if status != noErr {
      NSLog("Vhrase failed to install hotkey handler: \(status)")
    }
  }
}

private struct CarbonHotkeyDefinition {
  let id: Int
  let keyCode: UInt32
  let modifiers: UInt32

  init?(settings: DictationSettings) {
    switch settings.hotkeyPreset {
    case .fn:
      return nil
    case .controlOptionSpace:
      id = 1
      keyCode = UInt32(kVK_Space)
      modifiers = UInt32(controlKey | optionKey)
    case .commandShiftSpace:
      id = 2
      keyCode = UInt32(kVK_Space)
      modifiers = UInt32(cmdKey | shiftKey)
    case .controlOptionD:
      id = 3
      keyCode = UInt32(kVK_ANSI_D)
      modifiers = UInt32(controlKey | optionKey)
    case .custom:
      guard let customHotkey = settings.customHotkey else {
        return nil
      }
      id = 4
      keyCode = customHotkey.keyCode
      modifiers = customHotkey.modifiers
    case .disabled:
      return nil
    }
  }
}
