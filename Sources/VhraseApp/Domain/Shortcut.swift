// Defines keyboard shortcut choices and maps key edges to recorder actions.

import Foundation

enum HotkeyPreset: String, CaseIterable, Codable, Identifiable, Sendable {
  case fn
  case controlOptionSpace
  case commandShiftSpace
  case controlOptionD
  case custom
  case disabled

  var id: String { rawValue }

  var title: String {
    switch self {
    case .fn: "Fn / Globe"
    case .controlOptionSpace: "Control Option Space"
    case .commandShiftSpace: "Command Shift Space"
    case .controlOptionD: "Control Option D"
    case .custom: "Custom"
    case .disabled: "Disabled"
    }
  }

  var display: String {
    switch self {
    case .fn: "Fn/Globe"
    case .controlOptionSpace: "⌃⌥Space"
    case .commandShiftSpace: "⌘⇧Space"
    case .controlOptionD: "⌃⌥D"
    case .custom: "Custom"
    case .disabled: "Off"
    }
  }
}

struct CustomHotkey: Codable, Equatable, Sendable {
  let keyCode: UInt32
  let modifiers: UInt32
  let display: String
}

enum ShortcutBehavior: String, CaseIterable, Codable, Identifiable, Sendable {
  case toggle
  case holdToRecord

  var id: String { rawValue }

  var title: String {
    switch self {
    case .toggle: "Toggle"
    case .holdToRecord: "Hold"
    }
  }

  var summary: String {
    switch self {
    case .toggle: "Press once to start or stop"
    case .holdToRecord: "Hold shortcut while speaking"
    }
  }

  /// Converts a shortcut edge and workflow phase into the one legal recorder action.
  func action(for event: ShortcutEvent, status: AppStatus) -> ShortcutAction {
    switch (self, event) {
    case (.toggle, .pressed):
      if status == .preparing || status == .recording || status.canStartRecording {
        return .toggleRecording
      }
      return .none
    case (.toggle, .released):
      return .none
    case (.holdToRecord, .pressed):
      return status.canStartRecording ? .beginRecording : .none
    case (.holdToRecord, .released):
      if status == .preparing {
        return .cancelRecording
      }
      return status == .recording ? .finishRecording : .none
    }
  }
}

enum ShortcutEvent: Sendable {
  case pressed
  case released
}

enum ShortcutAction: Equatable, Sendable {
  case toggleRecording
  case beginRecording
  case finishRecording
  case cancelRecording
  case none
}
