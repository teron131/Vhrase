// Verifies the combined tap, hold, and double-tap shortcut policy across workflow phases.

@main
struct ShortcutBehaviorCheck {
  static func main() {
    var tap = ShortcutGestureInterpreter()
    precondition(tap.press(at: 1, status: .idle) == .beginRecording)
    precondition(tap.release(at: 1.1, status: .recording) == .none)
    precondition(tap.press(at: 2, status: .recording) == .finishRecording)
    precondition(tap.release(at: 2.1, status: .transcribing) == .none)

    var hold = ShortcutGestureInterpreter()
    precondition(hold.press(at: 1, status: .idle) == .beginRecording)
    precondition(hold.release(at: 1.5, status: .recording) == .finishRecording)

    var startupHold = ShortcutGestureInterpreter()
    precondition(startupHold.press(at: 1, status: .idle) == .beginRecording)
    precondition(startupHold.release(at: 1.5, status: .preparing) == .cancelRecording)

    var doubleTap = ShortcutGestureInterpreter()
    precondition(doubleTap.press(at: 1, status: .idle) == .beginRecording)
    precondition(doubleTap.release(at: 1.05, status: .preparing) == .none)
    precondition(
      doubleTap.press(at: 1.2, status: .preparing) == .cancelRecordingAndPolishText)
    precondition(doubleTap.release(at: 1.25, status: .adjusting) == .none)

    var processing = ShortcutGestureInterpreter()
    precondition(processing.press(at: 1, status: .transcribing) == .none)
    precondition(processing.press(at: 1.1, status: .transcribing) == .none)
    precondition(processing.release(at: 1.2, status: .transcribing) == .none)

    var settings = DictationSettings.defaults
    precondition(!settings.availableHotkeyPresets.contains(.custom))
    settings.customHotkey = CustomHotkey(keyCode: 0, modifiers: 0, display: "Custom Test")
    precondition(settings.availableHotkeyPresets.contains(.custom))
    print("shortcut behavior ok")
  }
}
