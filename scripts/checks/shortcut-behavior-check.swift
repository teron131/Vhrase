// Verifies the combined tap, hold, and double-tap shortcut policy across workflow phases, and each press's switch.

@main
struct ShortcutBehaviorCheck {
  static func main() {
    let all = ShortcutGestures()

    var tap = ShortcutGestureInterpreter()
    precondition(tap.press(at: 1, status: .idle, gestures: all) == .beginRecording)
    precondition(tap.release(at: 1.1, status: .recording, gestures: all) == .none)
    precondition(tap.press(at: 2, status: .recording, gestures: all) == .finishRecording)
    precondition(tap.release(at: 2.1, status: .transcribing, gestures: all) == .none)

    var hold = ShortcutGestureInterpreter()
    precondition(hold.press(at: 1, status: .idle, gestures: all) == .beginRecording)
    precondition(hold.release(at: 1.5, status: .recording, gestures: all) == .finishRecording)

    var startupHold = ShortcutGestureInterpreter()
    precondition(startupHold.press(at: 1, status: .idle, gestures: all) == .beginRecording)
    precondition(
      startupHold.release(at: 1.5, status: .preparing, gestures: all) == .cancelRecording)

    var doubleTap = ShortcutGestureInterpreter()
    precondition(doubleTap.press(at: 1, status: .idle, gestures: all) == .beginRecording)
    precondition(doubleTap.release(at: 1.05, status: .preparing, gestures: all) == .none)
    precondition(
      doubleTap.press(at: 1.2, status: .preparing, gestures: all) == .cancelRecordingAndPolishText)
    precondition(doubleTap.release(at: 1.25, status: .adjusting, gestures: all) == .none)

    var processing = ShortcutGestureInterpreter()
    precondition(processing.press(at: 1, status: .transcribing, gestures: all) == .none)
    precondition(processing.press(at: 1.1, status: .transcribing, gestures: all) == .none)
    precondition(processing.release(at: 1.2, status: .transcribing, gestures: all) == .none)

    // Hold off: letting go after a long press keeps recording until the next press.
    var tapOnly = ShortcutGestures()
    tapOnly.holdToTalk = false
    var toggle = ShortcutGestureInterpreter()
    precondition(toggle.press(at: 1, status: .idle, gestures: tapOnly) == .beginRecording)
    precondition(toggle.release(at: 1.5, status: .recording, gestures: tapOnly) == .none)
    precondition(toggle.press(at: 3, status: .recording, gestures: tapOnly) == .finishRecording)

    // Tap off: a quick press drops the recording it started, and a second quick press still polishes.
    var holdOnly = ShortcutGestures()
    holdOnly.tapToToggle = false
    var pushToTalk = ShortcutGestureInterpreter()
    precondition(pushToTalk.press(at: 1, status: .idle, gestures: holdOnly) == .beginRecording)
    precondition(
      pushToTalk.release(at: 1.1, status: .recording, gestures: holdOnly) == .cancelRecording)
    precondition(
      pushToTalk.press(at: 1.2, status: .idle, gestures: holdOnly) == .cancelRecordingAndPolishText)
    var pushToTalkHold = ShortcutGestureInterpreter()
    precondition(pushToTalkHold.press(at: 1, status: .idle, gestures: holdOnly) == .beginRecording)
    precondition(
      pushToTalkHold.release(at: 1.5, status: .recording, gestures: holdOnly) == .finishRecording)

    // Double-tap off: a quick second press finishes the recording instead of polishing.
    var noPolish = ShortcutGestures()
    noPolish.doubleTapToPolish = false
    var quickPair = ShortcutGestureInterpreter()
    precondition(quickPair.press(at: 1, status: .idle, gestures: noPolish) == .beginRecording)
    precondition(quickPair.release(at: 1.05, status: .recording, gestures: noPolish) == .none)
    precondition(
      quickPair.press(at: 1.2, status: .recording, gestures: noPolish) == .finishRecording)

    precondition(
      ShortcutGestureInterpreter.summary(all)
        == "Tap to toggle · hold to talk · double-tap to restyle")
    precondition(
      ShortcutGestureInterpreter.summary(holdOnly) == "Hold to talk · double-tap to restyle")

    var settings = DictationSettings.defaults
    precondition(!settings.availableHotkeyPresets.contains(.custom))
    settings.customHotkey = CustomHotkey(keyCode: 0, modifiers: 0, display: "Custom Test")
    precondition(settings.availableHotkeyPresets.contains(.custom))
    settings.shortcutGestures.tapToToggle = false
    settings.shortcutGestures.holdToTalk = false
    do {
      try settings.validateLocalConfiguration()
      preconditionFailure("Turning off both tap and hold must be rejected")
    } catch {}
    print("shortcut behavior ok")
  }
}
