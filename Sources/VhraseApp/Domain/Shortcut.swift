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

enum ShortcutAction: Equatable, Sendable {
  case beginRecording
  case finishRecording
  case cancelRecording
  case cancelRecordingAndPolishText
  case none
}

/// Which presses of the global shortcut act; tap and hold are the two ways to start dictating, so settings keep at least one of them on.
struct ShortcutGestures: Codable, Equatable, Sendable {
  var tapToToggle = true
  var holdToTalk = true
  var doubleTapToPolish = true
}

/// Interprets one shortcut as tap-to-toggle, hold-to-record, and double-tap-to-restyle without delaying microphone startup, acting only on the gestures that are on.
struct ShortcutGestureInterpreter {
  static let holdThreshold: TimeInterval = 0.35
  static let doubleTapInterval: TimeInterval = 0.28

  static func summary(_ gestures: ShortcutGestures) -> String {
    let text = [
      gestures.tapToToggle ? "tap to toggle" : nil,
      gestures.holdToTalk ? "hold to talk" : nil,
      gestures.doubleTapToPolish ? "double-tap to restyle" : nil,
    ]
    .compactMap(\.self)
    .joined(separator: " · ")
    return text.prefix(1).uppercased() + text.dropFirst()
  }

  private var pressStartedAt: TimeInterval?
  private var startedRecordingOnPress = false
  private var ignoresCurrentRelease = false
  private var pendingTapReleasedAt: TimeInterval?

  mutating func press(
    at time: TimeInterval, status: AppStatus, gestures: ShortcutGestures
  ) -> ShortcutAction {
    guard pressStartedAt == nil else {
      return .none
    }

    pressStartedAt = time
    startedRecordingOnPress = false
    ignoresCurrentRelease = false

    if gestures.doubleTapToPolish, let pendingTapReleasedAt,
      time - pendingTapReleasedAt <= Self.doubleTapInterval
    {
      self.pendingTapReleasedAt = nil
      ignoresCurrentRelease = true
      return .cancelRecordingAndPolishText
    }
    pendingTapReleasedAt = nil

    if status.canStartRecording {
      startedRecordingOnPress = true
      return .beginRecording
    }
    if status == .preparing {
      ignoresCurrentRelease = true
      return .cancelRecording
    }
    if status == .recording {
      ignoresCurrentRelease = true
      return .finishRecording
    }
    return .none
  }

  mutating func release(
    at time: TimeInterval, status: AppStatus, gestures: ShortcutGestures
  ) -> ShortcutAction {
    guard let pressStartedAt else {
      return .none
    }
    self.pressStartedAt = nil

    if ignoresCurrentRelease {
      ignoresCurrentRelease = false
      startedRecordingOnPress = false
      return .none
    }
    guard startedRecordingOnPress else {
      return .none
    }
    startedRecordingOnPress = false

    if time - pressStartedAt < Self.holdThreshold {
      pendingTapReleasedAt = time
      // Without tap, a quick press can only be the first half of a double-tap, so the recording it started is dropped.
      guard gestures.tapToToggle else {
        return status == .preparing || status == .recording ? .cancelRecording : .none
      }
      return .none
    }
    pendingTapReleasedAt = nil
    // Without hold, letting go after a long press leaves the recording running until the next press.
    guard gestures.holdToTalk else {
      return .none
    }
    if status == .preparing {
      return .cancelRecording
    }
    return status == .recording ? .finishRecording : .none
  }

  mutating func reset() {
    pressStartedAt = nil
    startedRecordingOnPress = false
    ignoresCurrentRelease = false
    pendingTapReleasedAt = nil
  }
}
